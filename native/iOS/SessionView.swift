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
    @State private var userScrolling = false
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
        relay.online && relay.machines[session.machineId]?.status == "ONLINE" && session.fresh != false
    }

    var body: some View {
        if let session = relay.current {
            VStack(spacing: 0) {
                transcript(session)
                SessionHeartbeat(session: session).padding(.horizontal, RelaySpacing.page)
                composer(session).padding(.horizontal, 16).padding(.vertical, 8)
            }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Button { context = true } label: {
                            VStack(spacing: 3) {
                                Text(session.title).font(.headline).lineLimit(1).foregroundStyle(.primary)
                                Text("\(relay.machines[session.machineId]?.name ?? session.machineId) · \(session.project)")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(minHeight: 44)
                        }.buttonStyle(.plain).accessibilityLabel("Session Info")
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
                .coordinateSpace(name: "transcript")
                .accessibilityIdentifier("session.transcript")
                .accessibilityValue("\(relay.chat.items.count) items")
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(DragGesture(minimumDistance: 3)
                    .onChanged { _ in userScrolling = true; nearBottom = false }
                    .onEnded { _ in userScrolling = false })
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
                    nearBottom = !userScrolling && value <= viewport.size.height + 80
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
                    if nearBottom && !userScrolling { DispatchQueue.main.async { if nearBottom && !userScrolling { proxy.scrollTo(bottomID, anchor: .bottom) } } }
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
                        } label: { Image(systemName: "plus").frame(minWidth: 44, minHeight: 44) }
                            .accessibilityLabel("Azioni della sessione")

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
                if let machine = relay.machines[session.machineId] {
                    if let version = machine.codexVersion { LabeledContent("Codex", value: version) }
                    if let account = machine.account { LabeledContent("Codex Account", value: account.email ?? account.kind) }
                    LabeledContent("Connection", value: relay.machineConnectionLabel(machine.id))
                }
                if let usage = session.tokenUsage { SessionUsageView(usage: usage) }
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
                Menu {
                    Button("Copia messaggio completo", systemImage: "doc.on.doc") { UIPasteboard.general.string = activity.text }
                    if !user { ShareLink(item: activity.text) { Label("Condividi", systemImage: "square.and.arrow.up") } }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "ellipsis").font(.caption)
                    }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44, alignment: user ? .trailing : .leading)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Azioni del messaggio")
                    .accessibilityIdentifier("message.actions." + activity.id)
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

private func conversationStatus(_ status: String) -> String {
    ["WORKING": "In corso", "READY": "Pronto", "NEEDS_YOU": "Serve una risposta", "INACTIVE": "Inattivo", "FAILED": "Errore"][status] ?? status
}


/// Reads fleet metadata only; high-frequency transcript chunks do not invalidate it.
private struct SessionHeartbeat: View {
    @Environment(RelayController.self) private var relay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: RelaySession
    private var state: String { session.displayStatus(machine: relay.machines[session.machineId], connected: relay.online) }
    var body: some View {
        VStack(alignment: .leading, spacing: RelaySpacing.small) {
            HStack(spacing: RelaySpacing.compact) {
                SessionStatusMark(status: state)
                Text(state == "OFFLINE" ? relay.machineConnectionLabel(session.machineId) : statusLabel(state))
                    .accessibilityIdentifier("session.connection").accessibilityValue(state == "OFFLINE" ? "Offline" : "Live")
                if state == "WORKING" { ElapsedLabel(start: session.turnStarted) }
                Spacer(minLength: 0)
            }.font(.caption.weight(.medium))
            if ["OFFLINE", "SYNCING", "RECONNECTING", "DEGRADED"].contains(state) {
                LastKnownSession(session: session, machine: relay.machines[session.machineId]).accessibilityIdentifier("session.stale")
            } else if state == "WORKING", let activity = relay.liveActivities[session.id] {
                Text(activity.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .contentTransition(.opacity)
            }
        }.padding(.top, RelaySpacing.compact)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: state)
    }
}
