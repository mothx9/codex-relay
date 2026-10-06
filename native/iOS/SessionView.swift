import SwiftUI

struct SessionView: View {
    @Environment(RelayController.self) private var relay
    @State private var draft = ""
    @State private var steer = false
    @State private var editingQueue: Outgoing?
    @State private var draftBeforeEdit = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var initialScroll = false
    @State private var historyPositioned = false
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
                            if let last = relay.outbox.visible(session: session.id).last(where: { $0.phase == .queued && $0.queueEditable }) {
                                Button("Modifica ultimo messaggio in coda", systemImage: "pencil") { beginQueueEdit(last) }
                                    .disabled(!machineOnline(session) || !session.allows("queue_update") || submitting)
                            }
                            Button(steer ? "Torna al follow-up" : "Steer del turno corrente", systemImage: "arrow.triangle.branch") {
                                steer.toggle(); expectedTurn = session.turnId ?? ""; composing = true
                            }.disabled(editingQueue != nil || (!steer && (!machineOnline(session) || !session.allows("steer"))))
                            Button("Interrompi turno", systemImage: "stop.circle", role: .destructive) {
                                interruptTurn = session.turnId ?? ""; interrupt = true
                            }.disabled(!machineOnline(session) || !session.allows("interrupt"))
                        } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
                            .accessibilityLabel("Azioni della sessione")
                    }
                }
                .confirmationDialog("Interrompere il turno in corso?", isPresented: $interrupt, titleVisibility: .visible) {
                    Button("Interrompi", role: .destructive) { Task { await relay.action("interrupt", expectedTurn: interruptTurn) } }
                }
                .onChange(of: relay.outbox.items.filter { $0.sessionId == session.id && $0.kind == "steer" && $0.phase == .failed && $0.errorCode != "UNKNOWN_OUTCOME" }.map(\.id)) { old, new in
                    guard draft.isEmpty, let id = new.last(where: { !old.contains($0) }),
                          let failed = relay.outbox.items.first(where: { $0.id == id }) else { return }
                    draft = failed.text
                    steer = false
                }
                .sheet(item: $tools) { ToolDetailView(group: $0) }
                .sheet(isPresented: $context) { contextSheet(session) }
        } else { ContentUnavailableView("Sessione non disponibile", systemImage: "bubble.left.and.bubble.right") }
    }

    private func transcript(_ session: RelaySession) -> some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    // Keep stable geometry when reading older history and returning
                    // from the keyboard; the selected-session memory is bounded.
                    VStack(alignment: .leading, spacing: RelaySpacing.page) {
                        HStack(spacing: 6) {
                            Circle().fill(machineOnline(session) ? statusColor(session.status) : .secondary).frame(width: 6, height: 6)
                            Text(machineOnline(session) ? conversationStatus(session.status) : relay.machineConnectionLabel(session.machineId))
                                .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("session.connection").accessibilityValue(machineOnline(session) ? "Live" : "Offline")
                            if machineOnline(session), session.status == "WORKING" { ElapsedLabel(start: session.turnStarted) }
                        }
                        if machineOnline(session), session.status == "WORKING", let activity = relay.liveActivities[session.id] {
                            Text(activity.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        if relay.historyLoading {
                            ProgressView("Caricamento cronologia…").font(.caption).frame(maxWidth: .infinity)
                        } else if relay.historyCursor != nil && !relay.chat.atCapacity {
                            Button("Carica messaggi precedenti") {
                                nearBottom = false
                                Task { await relay.loadOlderHistory() }
                            }.frame(minHeight: 44).frame(maxWidth: .infinity).accessibilityIdentifier("history.older")
                                .accessibilityValue("\(relay.chat.items.count) elementi caricati")
                                .disabled(!machineOnline(session))
                        }
                        if let error = relay.historyError {
                            Text(error).font(.caption).foregroundStyle(.secondary)
                            if relay.registry?.machines.first(where: { $0.id == session.machineId })?.access == "PAUSED" {
                                Button("Riprendi Relay su questa macchina") { Task { await relay.manageMachine(session.machineId, action: "resume") } }
                                    .font(.subheadline).frame(minHeight: 44)
                            }
                        }
                        if relay.chat.atCapacity || relay.chat.trimmed {
                            Text("Finestra in memoria limitata. La cronologia completa rimane in Codex.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(TranscriptGroup.make(relay.chat.items)) { group in
                            if group.kind == .message, let activity = group.items.first {
                                ChatMessageView(activity: activity).equatable()
                            } else {
                                ToolSummaryView(group: group) { tools = group }
                            }
                        }
                        ForEach(relay.outbox.visible(session: session.id)) { item in
                            OutgoingMessageView(item: item, session: session, onEdit: beginQueueEdit)
                        }
                        ForEach(relay.requests.values.filter { $0.sessionId == session.id }.sorted { $0.id < $1.id }) { request in
                            PendingView(request: request).id(request.presentationID)
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
                .accessibilityIdentifier("session.transcript")
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewport.size, initial: true) { _, size in
                    guard !initialScroll, size.height > 0 else { return }
                    // Navigation may lay out the destination after its first
                    // appearance. Position only once, after that layout pass.
                    DispatchQueue.main.async {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                        initialScroll = true
                    }
                }
                .onPreferenceChange(TranscriptBottom.self) { value in
                    nearBottom = value <= viewport.size.height + 80
                    if nearBottom { unread = false }
                }
                .onChange(of: relay.historyLoading) { _, loading in
                    guard !loading, !historyPositioned, relay.historyError == nil else { return }
                    historyPositioned = true
                    // The initial empty viewport can lay out before canonical
                    // history arrives. Position after that first hydration too.
                    DispatchQueue.main.async { proxy.scrollTo(bottomID, anchor: .bottom) }
                }
                .onChange(of: revision) { _, _ in
                    if nearBottom { DispatchQueue.main.async { proxy.scrollTo(bottomID, anchor: .bottom) } }
                    else { unread = true }
                }
                .onChange(of: scrollRequest) { _, _ in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(bottomID, anchor: .bottom) }
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
                if let editingQueue {
                    HStack {
                        Label("Modifica messaggio in coda", systemImage: "pencil").font(.caption)
                        Spacer()
                        Button("Annulla") {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                self.editingQueue = nil; draft = draftBeforeEdit; draftBeforeEdit = ""
                            }
                            relay.queueEditError = nil
                        }.font(.caption).disabled(submitting)
                    }.accessibilityIdentifier("composer.editingQueue")
                    if let error = relay.queueEditError { Text(error).font(.caption).foregroundStyle(.orange) }
                    if relay.outbox.items.first(where: { $0.id == editingQueue.id })?.phase != .queued {
                        Text("Il messaggio è già partito. Il testo modificato rimane qui.").font(.caption).foregroundStyle(.secondary)
                    }
                } else if steer {
                    HStack {
                        Label("Steer · invia subito al turno corrente", systemImage: "arrow.triangle.branch").font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button("Annulla") { steer = false }.font(.caption)
                    }
                } else if session.status == "NEEDS_YOU" {
                    Button("Vai alla richiesta", systemImage: "arrow.down.message") { scrollRequest += 1 }.font(.caption).foregroundStyle(.orange).frame(minHeight: 44)
                } else if !machineOnline(session) {
                    Text("I messaggi potranno essere inviati dopo la riconnessione.").font(.caption).foregroundStyle(.secondary)
                }
                let kind = editingQueue != nil ? "queue_update" : steer ? "steer" : session.defaultCommand
                let available = machineOnline(session) && session.allows(kind) && (editingQueue != nil || ["READY", "WORKING"].contains(session.status))
                let canSend = available && !submitting && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                HStack(alignment: .bottom, spacing: 6) {
                    TextField(steer ? "Correggi il lavoro in corso…" : session.status == "WORKING" ? "Aggiungi un follow-up…" : "Scrivi a Codex…", text: $draft, axis: .vertical)
                        .font(.body).lineLimit(1...5).focused($composing).padding(.leading, 20).padding(.vertical, 16)
                        .disabled(!available).accessibilityIdentifier("composer.text")
                    Button {
                        if let item = editingQueue {
                            submitting = true
                            let text = draft
                            Task {
                                defer { submitting = false }
                                if await relay.editQueued(item, text: text) {
                                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                        editingQueue = nil; draft = draftBeforeEdit; draftBeforeEdit = ""
                                    }
                                }
                            }
                        } else { sendDraft(session, kind: kind, targetTurn: steer ? expectedTurn : nil) }
                    } label: {
                        Image(systemName: editingQueue != nil ? "checkmark" : "arrow.up").font(.body.weight(.semibold))
                            .foregroundStyle(Color(uiColor: .systemBackground))
                            .frame(width: 44, height: 44).background(Color.primary.opacity(canSend ? 1 : 0.22), in: Circle())
                    }
                    .buttonStyle(.plain).disabled(!canSend).padding(6)
                    .accessibilityLabel(editingQueue != nil ? "Salva messaggio in coda" : steer ? "Invia Steer" : session.status == "WORKING" ? "Invia follow-up" : "Invia")
                    .accessibilityIdentifier("composer.send")
                    .contextMenu {
                        if editingQueue == nil && session.allows("steer") {
                            Button("Invia ora (Steer)", systemImage: "arrow.triangle.branch") {
                                sendDraft(session, kind: "steer", targetTurn: session.turnId)
                            }.disabled(!machineOnline(session) || submitting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .accessibilityHint(session.status == "WORKING" ? "Invia in coda. Tieni premuto per inviare subito con Steer." : "Invia un nuovo messaggio")
                }.modifier(ComposerSurface())
            }
        }
    }

    private func beginQueueEdit(_ item: Outgoing) {
        guard !submitting else { return }
        if editingQueue == nil { draftBeforeEdit = draft }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            editingQueue = item; draft = item.text; steer = false
        }
        relay.queueEditError = nil; composing = true
    }

    private func sendDraft(_ session: RelaySession, kind: String, targetTurn: String?) {
        guard !submitting else { return }
        let text = draft
        submitting = true
        Task {
            defer { submitting = false }
            guard relay.current?.id == session.id else { return }
            if await relay.submit(text, kind: kind, expectedTurn: targetTurn) {
                if draft == text { draft = "" }
                steer = false; scrollRequest += 1
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

private struct ChatMessageView: View, Equatable {
    let activity: Activity
    private var user: Bool { activity.kind == "userMessage" }
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if user { Spacer(minLength: 44) }
            VStack(alignment: user ? .trailing : .leading, spacing: 8) {
                Menu {
                    Button("Copia messaggio completo", systemImage: "doc.on.doc") { UIPasteboard.general.string = activity.text }
                    if !user { ShareLink(item: activity.text) { Label("Condividi", systemImage: "square.and.arrow.up") } }
                } label: {
                    HStack(spacing: 4) {
                        Text(user ? "Tu" : "Codex")
                        Image(systemName: "chevron.down").font(.caption2)
                    }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44, alignment: user ? .trailing : .leading)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Azioni del messaggio")
                    .accessibilityIdentifier("message.actions." + activity.id)
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
                    ForEach(Array(questions.enumerated()).filter { !activity.text.contains($0.element.title) }, id: \.offset) { index, question in
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
                .environment(\.completeMessage, activity.text)
                .contextMenu {
                    Button("Copia messaggio completo", systemImage: "doc.on.doc") { UIPasteboard.general.string = activity.text }
                    if !user { ShareLink(item: activity.text) { Label("Condividi", systemImage: "square.and.arrow.up") } }
                }
        }
    }
}

private struct OutgoingMessageView: View {
    @Environment(RelayController.self) private var relay
    let item: Outgoing
    let session: RelaySession
    var onEdit: (Outgoing) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                Text(relay.queueEditingID == item.id ? "AGGIORNAMENTO IN CORSO…" : caption)
                    .font(.caption2.weight(.medium)).foregroundStyle(item.phase == .failed ? .orange : .secondary)
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: item.phase)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: relay.queueEditingID)
                if item.phase == .queued && item.queueEditable {
                    Button("Modifica", systemImage: "pencil") { onEdit(item) }.font(.caption).frame(minHeight: 44)
                        .disabled(!session.allows("queue_update") || !relay.online || relay.machines[session.machineId]?.status != "ONLINE" || relay.queueEditingID != nil)
                }
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
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var running: Int { group.items.filter { $0.state == "running" }.count }
    private var failed: Int { group.items.filter { $0.state == "failed" || $0.state == "declined" }.count }
    private var current: Activity? { group.items.last(where: { $0.state == "running" }) ?? group.items.last }
    private var state: String { running > 0 ? "WORKING" : failed > 0 ? "FAILED" : group.items.allSatisfy { $0.state == "completed" } ? "READY" : "INACTIVE" }
    private var tint: Color { group.kind == .terminal ? .blue : group.kind == .mcp ? .purple : .orange }
    private var summary: String {
        var value = toolCount(group)
        if running > 0 { value += " · \(running) in corso" }
        if failed > 0 { value += " · \(failed) \(failed == 1 ? "non riuscito" : "non riusciti")" }
        if state == "READY" { value += group.items.count == 1 ? " · completato" : " · completati" }
        return value
    }
    private var preview: String? {
        guard let current else { return nil }
        if let command = current.command { return command }
        if let tool = current.toolName { return [current.toolServer, tool].compactMap { $0 }.joined(separator: " · ") }
        if let files = current.files, !files.isEmpty {
            return files.prefix(3).map { URL(fileURLWithPath: $0.path).lastPathComponent }.joined(separator: ", ")
        }
        return nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: RelaySpacing.row) {
            Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                VStack(alignment: .leading, spacing: RelaySpacing.compact) {
                    HStack(spacing: 10) {
                        Image(systemName: toolIcon(group.kind)).font(.subheadline.weight(.medium)).foregroundStyle(tint)
                            .frame(width: 28, height: 28).background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                        Text(toolTitle(group.kind)).font(.subheadline.weight(.semibold))
                        Spacer(minLength: 4)
                        SessionStatusMark(status: state).font(.caption)
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: state)
                    if let preview {
                        if current?.command != nil { CommandPreviewView(command: preview).lineLimit(expanded ? 3 : 2) }
                        else { Text(preview).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }
                }.foregroundStyle(.primary).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(RelayRowPressStyle()).accessibilityIdentifier("tool." + group.id)
                .accessibilityValue(expanded ? "Dettagli aperti" : "Dettagli chiusi")
            if running > 0, group.kind == .terminal, let item = current, !item.commandOutput.isEmpty {
                // A bounded tail is a live preview, not another scrolling terminal.
                Text(item.commandOutput.suffix(600).split(separator: "\n", omittingEmptySubsequences: false).suffix(3).joined(separator: "\n"))
                    .font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10).overlay(alignment: .leading) { Capsule().fill(tint.opacity(0.4)).frame(width: 2) }
                    .accessibilityIdentifier("tool.live." + group.id)
            }
            if expanded {
                VStack(alignment: .leading, spacing: RelaySpacing.row) {
                    Button("Apri dettagli e output", action: open).font(.caption).frame(minHeight: 44)
                        .accessibilityIdentifier("tool.details." + group.id)
                    ForEach(group.items) { item in
                        HStack(alignment: .top, spacing: RelaySpacing.compact) {
                            SessionStatusMark(status: item.state == "running" ? "WORKING" : item.state == "failed" || item.state == "declined" ? "FAILED" : item.state == "completed" ? "READY" : "INACTIVE")
                                .font(.caption).frame(width: 20)
                            VStack(alignment: .leading, spacing: RelaySpacing.small) {
                                if let command = item.command { CommandPreviewView(command: command).lineLimit(3) }
                                else {
                                    Text(item.toolName ?? item.files?.first.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? toolTitle(group.kind))
                                        .font(.subheadline).lineLimit(3).textSelection(.enabled)
                                }
                                HStack(spacing: 8) {
                                    Text(activityState(item.state))
                                    if let code = item.exitCode { Text("Exit \(code)") }
                                    if let duration = item.durationMs { Text(String(format: "%.1f s", Double(duration) / 1000)) }
                                }.font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.transition(.opacity.combined(with: .move(edge: .top)))
            }
        }.padding(RelaySpacing.row)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(running > 0 ? tint.opacity(0.25) : Color.primary.opacity(0.04)))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: state)
    }
}

private struct ToolDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RelayController.self) private var relay
    let group: TranscriptGroup
    private var liveGroup: TranscriptGroup { TranscriptGroup.make(relay.chat.items).first { $0.id == group.id } ?? group }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    Text("Attività recente della sessione.")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(liveGroup.items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(item.toolName ?? toolTitle(group.kind)).font(.subheadline.weight(.semibold))
                                Spacer()
                                if item.state == "running" { ProgressView().controlSize(.small) }
                                Text(activityState(item.state)).font(.caption).foregroundStyle(.secondary)
                                Menu {
                                    if let command = item.command { Button("Copia comando", systemImage: "terminal") { UIPasteboard.general.string = command } }
                                    Button("Copia output completo", systemImage: "doc.on.doc") { UIPasteboard.general.string = item.command != nil ? item.commandOutput : item.text }
                                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                                    .accessibilityLabel("Azioni output")
                            }
                            if let server = item.toolServer { Text(server).font(.caption).foregroundStyle(.secondary) }
                            if let command = item.command {
                                ScrollView(.horizontal) { CommandPreviewView(command: command).fixedSize(horizontal: true, vertical: false) }
                                    .contextMenu { Button("Copia comando", systemImage: "doc.on.doc") { UIPasteboard.general.string = command } }
                            }
                            HStack {
                                if let code = item.exitCode { Text("Exit \(code)") }
                                if let milliseconds = item.durationMs { Text(String(format: "%.1f s", Double(milliseconds) / 1000)) }
                                if item.truncated == true { Text("Contenuto parziale") }
                            }.font(.caption).foregroundStyle(.secondary)
                            if item.kind == "diff" {
                                PatchView(patch: item.text)
                            } else if let files = item.files, !files.isEmpty {
                                ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                                    Text(URL(fileURLWithPath: file.path).lastPathComponent + " · " + fileChangeLabel(file.kind)).font(.subheadline)
                                    if let patch = file.patch {
                                        if patch.hasPrefix("diff --git ") || patch.hasPrefix("@@ ") || patch.contains("\n@@ ") {
                                            PatchView(patch: patch, path: file.path)
                                        } else {
                                            CodeBlockView(code: patch, language: URL(fileURLWithPath: file.path).pathExtension)
                                        }
                                    }
                                }
                            } else if group.kind == .terminal {
                                if #available(iOS 18.0, *) {
                                    TerminalOutputView(text: item.command != nil ? item.commandOutput : item.text)
                                        .accessibilityIdentifier("activity." + item.kind + "." + item.id)
                                } else {
                                    CodeBlockView(code: item.command != nil ? item.commandOutput : item.text, language: "output")
                                }
                            } else {
                            ScrollView(.horizontal) {
                                Text(item.command != nil ? item.commandOutput : item.text).font(.callout.monospaced()).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityIdentifier("activity." + item.kind + "." + item.id)
                            }.contextMenu { Button("Copia output", systemImage: "doc.on.doc") { UIPasteboard.general.string = item.command != nil ? item.commandOutput : item.text } }
                            }
                        }
                    }
                }.padding(20)
            }.navigationTitle(toolTitle(group.kind)).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("Copia tutti gli output", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = liveGroup.items.map { $0.command != nil ? $0.commandOutput : $0.text }.joined(separator: "\n\n")
                            }
                        } label: { Image(systemName: "doc.on.doc").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Copia attività")
                    }
                    ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } }
                }
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

private func activityState(_ state: String?) -> String {
    switch state { case "running": "In corso"; case "completed": "Completato"; case "failed": "Fallito"; case "declined": "Rifiutato"; default: "" }
}

private func fileChangeLabel(_ kind: String) -> String {
    switch kind { case "add", "create": "Creato"; case "delete": "Eliminato"; case "rename", "move": "Rinominato"; default: "Modificato" }
}
