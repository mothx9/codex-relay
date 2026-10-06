import SwiftUI

struct SessionView: View {
    @EnvironmentObject var relay: RelayController
    @State private var draft = ""
    @State private var steer = false
    @State private var expectedTurn = ""
    @State private var interrupt = false
    @State private var interruptTurn = ""
    @State private var context = false
    @State private var tools: TranscriptGroup?
    @State private var nearBottom = true
    @State private var unread = false
    @State private var submitting = false
    @State private var scrollRequest = 0
    @State private var visibleItem: String? = "transcript.bottom"
    @FocusState private var composing: Bool
    private let bottomID = "transcript.bottom"

    private var revision: [String] {
        relay.chat.items.map(\.id) + [relay.chat.items.last?.text ?? ""]
        + relay.outbox.visible(session: relay.selected).map { $0.id + $0.phase.rawValue }
        + relay.requests.values.filter { $0.sessionId == relay.selected }.map(\.id).sorted()
    }
    private func machineOnline(_ session: RelaySession) -> Bool {
        relay.online && relay.machines[session.machineId]?.status == "ONLINE"
    }

    var body: some View {
        if let session = relay.current {
            VStack(spacing: 0) {
                transcript(session)
                composer(session).padding(.horizontal, 16).padding(.vertical, 8)
            }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 3) {
                            Text(session.title).font(.headline).lineLimit(1)
                            Text("\(relay.machines[session.machineId]?.name ?? session.machineId) · \(session.project)")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Contesto della sessione", systemImage: "info.circle") { context = true }
                            Button(steer ? "Torna al follow-up" : "Modifica il turno corrente", systemImage: "arrow.triangle.branch") {
                                steer.toggle(); expectedTurn = session.turnId ?? ""; composing = true
                            }.disabled(!steer && (!machineOnline(session) || !session.allows("steer")))
                            Button("Interrompi turno", systemImage: "stop.circle", role: .destructive) {
                                interruptTurn = session.turnId ?? ""; interrupt = true
                            }.disabled(!machineOnline(session) || !session.allows("interrupt"))
                        } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
                            .accessibilityLabel("Azioni della sessione")
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Fine") { composing = false }.accessibilityIdentifier("composer.dismissKeyboard")
                    }
                }
                .confirmationDialog("Interrompere il turno in corso?", isPresented: $interrupt, titleVisibility: .visible) {
                    Button("Interrompi", role: .destructive) { Task { await relay.action("interrupt", expectedTurn: interruptTurn) } }
                }
                .sheet(item: $tools) { ToolDetailView(group: $0) }
                .sheet(isPresented: $context) { contextSheet(session) }
        } else { ContentUnavailableView("Sessione non disponibile", systemImage: "bubble.left.and.bubble.right") }
    }

    private func transcript(_ session: RelaySession) -> some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    // RecentChat is bounded. Keep rows laid out so the bottom
                    // anchor remains stable across foreground rehydration.
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(spacing: 6) {
                            Circle().fill(machineOnline(session) ? statusColor(session.status) : .secondary).frame(width: 6, height: 6)
                            Text("\(conversationStatus(session.status)) · \(machineOnline(session) ? relay.connection : "Macchina offline")")
                                .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("session.connection")
                        }
                        ForEach(TranscriptGroup.make(relay.chat.items)) { group in
                            if group.kind == .message, let activity = group.items.first {
                                ChatMessageView(activity: activity)
                            } else {
                                ToolSummaryView(group: group) { tools = group }
                            }
                        }
                        ForEach(relay.outbox.visible(session: session.id)) { item in
                            OutgoingMessageView(item: item, session: session)
                        }
                        ForEach(relay.requests.values.filter { $0.sessionId == session.id }.sorted { $0.id < $1.id }) { request in
                            PendingView(request: request)
                        }
                        if relay.chat.items.isEmpty && relay.outbox.visible(session: session.id).isEmpty {
                            Text("Il contesto recente di Codex apparirà qui.").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 24)
                        }
                        Color.clear.frame(height: 1).id(bottomID)
                            .background(GeometryReader { geometry in
                                Color.clear.preference(key: TranscriptBottom.self, value: geometry.frame(in: .named("transcript")).maxY)
                            })
                    }.scrollTargetLayout().padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
                }
                .scrollPosition(id: $visibleItem, anchor: .bottom)
                .coordinateSpace(name: "transcript")
                .scrollDismissesKeyboard(.interactively)
                .onPreferenceChange(TranscriptBottom.self) { value in
                    nearBottom = value <= viewport.size.height + 80
                    if nearBottom { unread = false }
                }
                .onChange(of: revision) { _, _ in
                    if nearBottom { DispatchQueue.main.async { proxy.scrollTo(bottomID, anchor: .bottom) } }
                    else { unread = true }
                }
                .onChange(of: scrollRequest) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(bottomID, anchor: .bottom) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if unread {
                        Button { scrollRequest += 1 } label: { Label("Messaggi recenti", systemImage: "arrow.down") }
                            .font(.caption.weight(.medium)).buttonStyle(.bordered).padding(12)
                            .accessibilityIdentifier("transcript.latest")
                    }
                }
            }
        }
    }

    @ViewBuilder private func composer(_ session: RelaySession) -> some View {
        VStack(spacing: 8) {
            if session.readOnly {
                Text("Collega questo thread a Codex per inviare messaggi.").font(.caption).foregroundStyle(.secondary)
                Button("Collega thread") { Task { await relay.action("attach") } }.disabled(!machineOnline(session))
            } else {
                if steer {
                    HStack {
                        Label("Modifica il turno in corso", systemImage: "arrow.triangle.branch").font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button("Annulla") { steer = false }.font(.caption)
                    }
                } else if session.status == "NEEDS_YOU" {
                    Text("Rispondi alla richiesta per continuare.").font(.caption).foregroundStyle(.orange)
                } else if !machineOnline(session) {
                    Text("I messaggi potranno essere inviati dopo la riconnessione.").font(.caption).foregroundStyle(.secondary)
                }
                let kind = steer ? "steer" : session.defaultCommand
                let available = machineOnline(session) && session.allows(kind) && ["READY", "WORKING"].contains(session.status)
                let canSend = available && !submitting && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                HStack(alignment: .bottom, spacing: 6) {
                    TextField(steer ? "Correggi il lavoro in corso…" : session.status == "WORKING" ? "Aggiungi un follow-up…" : "Scrivi a Codex…", text: $draft, axis: .vertical)
                        .font(.body).lineLimit(1...5).focused($composing).padding(.leading, 20).padding(.vertical, 16)
                        .disabled(!available).accessibilityIdentifier("composer.text")
                    Button {
                        let text = draft; let sessionID = session.id
                        let targetTurn = steer ? expectedTurn : nil
                        submitting = true
                        Task {
                            defer { submitting = false }
                            guard relay.current?.id == sessionID else { return }
                            if await relay.submit(text, kind: kind, expectedTurn: targetTurn) {
                                if draft == text { draft = "" }
                                steer = false; scrollRequest += 1
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up").font(.body.weight(.semibold))
                            .foregroundStyle(Color(uiColor: .systemBackground))
                            .frame(width: 44, height: 44).background(Color.primary.opacity(canSend ? 1 : 0.22), in: Circle())
                    }
                    .buttonStyle(.plain).disabled(!canSend).padding(6)
                    .accessibilityLabel(steer ? "Invia Steer" : session.status == "WORKING" ? "Invia follow-up" : "Invia")
                    .accessibilityIdentifier("composer.send")
                }.modifier(ComposerSurface())
            }
        }
    }

    private func contextSheet(_ session: RelaySession) -> some View {
        NavigationStack {
            List {
                LabeledContent("Macchina", value: relay.machines[session.machineId]?.name ?? session.machineId)
                LabeledContent("Progetto", value: session.project)
                LabeledContent("Cartella", value: session.cwd)
                if let branch = session.branch, !branch.isEmpty { LabeledContent("Branch", value: branch) }
                LabeledContent("Thread", value: session.threadId)
                Text("Questa chat mostra contesto recente ed effimero. La cronologia rimane in Codex.").font(.footnote).foregroundStyle(.secondary)
            }.textSelection(.enabled).navigationTitle("Contesto").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { context = false } } }
        }
    }
}

private struct TranscriptBottom: PreferenceKey {
    static let defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ComposerSurface: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.primary.opacity(0.1)))
        }
    }
}

private struct ChatMessageView: View {
    let activity: Activity
    private var user: Bool { activity.kind == "userMessage" }
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if user { Spacer(minLength: 44) }
            VStack(alignment: user ? .trailing : .leading, spacing: 8) {
                Text(user ? "Tu" : "Codex").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if user {
                    Text(activity.text).font(.body).textSelection(.enabled)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
                        .accessibilityIdentifier("activity." + activity.kind + "." + activity.id)
                } else {
                    let questions = activity.questions ?? []
                    if questions.isEmpty || activity.text != questions.map(\.title).joined(separator: "\n\n") {
                        ChatMarkdown(text: activity.text, identifier: "activity." + activity.kind + "." + activity.id)
                    }
                    ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Domanda", systemImage: "questionmark.bubble").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                            Text(question.title).font(.body).textSelection(.enabled)
                                .accessibilityIdentifier("question." + activity.id + ".\(index)")
                            ForEach(Array((question.options ?? []).enumerated()), id: \.offset) { _, option in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("•").foregroundStyle(.secondary)
                                    Text(option).font(.subheadline).textSelection(.enabled)
                                }
                            }
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.orange.opacity(0.2)))
                    }
                    if activity.truncated == true { Text("Contesto parziale · consulta Codex per il contenuto completo.").font(.caption).foregroundStyle(.secondary) }
                }
            }.frame(maxWidth: .infinity, alignment: user ? .trailing : .leading)
        }
    }
}

private struct OutgoingMessageView: View {
    @EnvironmentObject var relay: RelayController
    let item: Outgoing
    let session: RelaySession
    private var caption: String {
        let kind = item.kind == "follow_up" ? "FOLLOW-UP" : item.kind == "steer" ? "STEER" : "NUOVO TURNO"
        let phase: String
        switch item.phase {
        case .local, .sending, .steering: phase = "INVIO…"
        case .queued: phase = "IN CODA"
        case .dispatched: phase = "IN ESECUZIONE"
        case .accepted: phase = "INVIATO"
        case .applied: phase = "APPLICATO"
        case .failed: phase = item.errorCode == "UNKNOWN_OUTCOME" ? "ESITO DA VERIFICARE" : "INVIO NON RIUSCITO"
        case .materialized: phase = ""
        }
        return kind + " · " + phase
    }
    var body: some View {
        HStack {
            Spacer(minLength: 44)
            VStack(alignment: .trailing, spacing: 8) {
                Text("Tu").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(item.text).font(.body).textSelection(.enabled)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityIdentifier("outbox." + item.id)
                Text(caption).font(.caption2.weight(.medium)).foregroundStyle(item.phase == .failed ? .orange : .secondary)
                if item.phase == .failed {
                    Text(item.error ?? "Invio fallito").font(.caption).foregroundStyle(.orange)
                    if session.allows(item.kind) {
                        Button(item.errorCode == "UNKNOWN_OUTCOME" ? "Ho verificato Codex: reinvia" : "Riprova") { Task { await relay.retry(item) } }
                            .disabled(!relay.online || relay.machines[session.machineId]?.status != "ONLINE")
                    }
                    if item.kind == "steer", session.allows(session.defaultCommand) {
                        Button("Invia come \(session.defaultCommand == "follow_up" ? "follow-up" : "nuovo turno")") { Task { await relay.retry(item, as: session.defaultCommand) } }
                            .disabled(!relay.online || relay.machines[session.machineId]?.status != "ONLINE")
                    }
                    Button("Scarta") { relay.outbox.discard(item.id) }
                }
            }.font(.subheadline)
        }
    }
}

private struct ToolSummaryView: View {
    let group: TranscriptGroup
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: toolIcon(group.kind)).font(.body).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text(toolTitle(group.kind)).font(.subheadline.weight(.semibold))
                    Text(toolCount(group)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }.foregroundStyle(.primary).padding(16)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.09)))
        }.buttonStyle(.plain).accessibilityIdentifier("tool." + group.id)
    }
}

private struct ToolDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let group: TranscriptGroup
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    Text("Attività recente della sessione.")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(group.items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.kind == "command_output" ? "Output" : toolTitle(group.kind)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ScrollView(.horizontal) {
                                Text(item.text).font(.callout.monospaced()).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityIdentifier("activity." + item.kind + "." + item.id)
                            }
                        }
                    }
                }.padding(20)
            }.navigationTitle(toolTitle(group.kind)).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
        }
    }
}

private func toolTitle(_ kind: TranscriptGroup.Kind) -> String {
    switch kind { case .terminal: "Terminale"; case .mcp: "MCP"; case .changes: "Modifiche"; default: "Attività" }
}
private func toolIcon(_ kind: TranscriptGroup.Kind) -> String {
    switch kind { case .terminal: "terminal"; case .mcp: "wrench.and.screwdriver"; case .changes: "doc.text"; default: "list.bullet" }
}
private func toolCount(_ group: TranscriptGroup) -> String {
    let count = group.items.count
    switch group.kind {
    case .terminal: return "\(count) \(count == 1 ? "comando" : "comandi")"
    case .mcp: return "\(count) \(count == 1 ? "operazione" : "operazioni")"
    case .changes: return "\(count) \(count == 1 ? "evento" : "eventi")"
    default: return "\(count) \(count == 1 ? "elemento" : "elementi")"
    }
}
private func conversationStatus(_ status: String) -> String {
    ["WORKING": "In corso", "READY": "Pronto", "NEEDS_YOU": "Serve una risposta", "INACTIVE": "Inattivo", "FAILED": "Errore"][status] ?? status
}

/// Render Markdown blocks using native selectable text; code keeps its spacing.
private struct ChatMarkdown: View {
    let text: String
    let identifier: String
    private struct Block {
        enum Kind { case paragraph, heading, bullet, code }
        let kind: Kind
        let text: String
    }
    private var blocks: [Block] {
        var result: [Block] = []; var paragraph: [String] = []; var code: [String] = []; var fenced = false
        func flush() {
            if !paragraph.isEmpty { result.append(Block(kind: .paragraph, text: paragraph.joined(separator: "\n"))); paragraph = [] }
        }
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flush()
                if fenced { result.append(Block(kind: .code, text: code.joined(separator: "\n"))); code = [] }
                fenced.toggle(); continue
            }
            if fenced { code.append(line); continue }
            if trimmed.isEmpty { flush(); continue }
            let heading = trimmed.prefix { $0 == "#" }
            if (1...6).contains(heading.count), trimmed.dropFirst(heading.count).hasPrefix(" ") {
                flush(); result.append(Block(kind: .heading, text: String(trimmed.dropFirst(heading.count + 1)))); continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flush(); result.append(Block(kind: .bullet, text: String(trimmed.dropFirst(2)))); continue
            }
            paragraph.append(line)
        }
        flush()
        if fenced { result.append(Block(kind: .code, text: code.joined(separator: "\n"))) }
        return result
    }
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                let id = index == 0 ? identifier : identifier + ".\(index)"
                switch block.kind {
                case .paragraph: Text(inline(block.text)).font(.body).textSelection(.enabled).accessibilityIdentifier(id)
                case .heading: Text(inline(block.text)).font(.headline).textSelection(.enabled).accessibilityAddTraits(.isHeader).accessibilityIdentifier(id)
                case .bullet:
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("•").foregroundStyle(.secondary)
                        Text(inline(block.text)).font(.body).textSelection(.enabled).accessibilityIdentifier(id)
                    }
                case .code:
                    ScrollView(.horizontal) { Text(block.text).font(.callout.monospaced()).textSelection(.enabled).accessibilityIdentifier(id) }
                        .padding(12).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
