import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO
import UIKit

struct SessionView: View {
    @Environment(RelayController.self) private var relay
    @State private var draft = ""
    @State private var images: [ImageInput] = []
    @State private var showPhotos = false
    @State private var questionDetails = false
    @State private var questionDetent: PresentationDetent = .medium
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var loadingImages = 0
    @State private var steer = false
    @State private var editingQueue: Outgoing?
    @State private var draftBeforeEdit = ""
    @State private var imagesBeforeEdit: [ImageInput] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expectedTurn = ""
    @State private var interrupt = false
    @State private var interruptTurn = ""
    @State private var context = false
    @State private var actionsOpen = false
    @State private var queueDetails = false
    @State private var composerHeight: CGFloat = 44
    @State private var submitting = false
    @State private var scrollRequest = 0
    @FocusState private var composing: Bool

    private func machineOnline(_ session: RelaySession) -> Bool {
        relay.online && relay.machines[session.machineId]?.status == "ONLINE" && session.fresh != false
    }

    var body: some View {
        if let session = relay.current {
            VStack(spacing: 0) {
                SessionTranscript(session: session, scrollRequest: $scrollRequest, onEdit: beginQueueEdit) { answer in
                    guard editingQueue == nil else { return }
                    if !answer.isEmpty && draft != answer { draft = draft.isEmpty ? answer : draft + "\n\n" + answer }
                    composing = true
                }
                .simultaneousGesture(TapGesture().onEnded { actionsOpen = false })
                liveQuestionDock(session)
                queuedMessages(session)
                SessionHeartbeat(session: session).padding(.horizontal, 20).padding(.top, 2)
                composer(session).padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 2)
            }
                .onDrop(of: [UTType.image.identifier], isTargeted: nil) { providers in
                    guard session.capabilities.canSendImages == true, editingQueue == nil, !submitting else { return false }
                    let accepted = providers.prefix(max(0, ImageInput.maxCount - images.count - loadingImages))
                    for provider in accepted {
                        guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else { continue }
                        loadingImages += 1
                        provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                            Task { @MainActor in await importImage(data, sessionID: session.id) }
                        }
                    }
                    return !accepted.isEmpty
                }
                .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: max(1, ImageInput.maxCount - images.count - loadingImages), matching: .images)
                .onChange(of: currentQuestions(session).map(\.id)) { _, ids in if ids.isEmpty { questionDetails = false } }
                .sheet(isPresented: $questionDetails) { liveQuestionSheet(session) }
                .onChange(of: photoItems) { _, items in
                    guard !items.isEmpty else { return }
                    photoItems = []
                    for item in items.prefix(max(0, ImageInput.maxCount - images.count - loadingImages)) {
                        loadingImages += 1
                        Task { await importImage(try? await item.loadTransferable(type: Data.self), sessionID: session.id) }
                    }
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
                        }.buttonStyle(.plain).accessibilityLabel(String(localized: "Session Info", bundle: relayLocalizationBundle))
                    }
                }
                .confirmationDialog(String(localized: "Interrupt the current turn?", bundle: relayLocalizationBundle), isPresented: $interrupt, titleVisibility: .visible) {
                    Button(String(localized: "Interrupt", bundle: relayLocalizationBundle), role: .destructive) { Task { await relay.action("interrupt", expectedTurn: interruptTurn) } }
                }
                .onChange(of: relay.outbox.items.filter { $0.sessionId == session.id && $0.kind == "steer" && $0.phase == .failed && $0.errorCode != "UNKNOWN_OUTCOME" }.map(\.id)) { old, new in
                    guard draft.isEmpty, let id = new.last(where: { !old.contains($0) }),
                          let failed = relay.outbox.items.first(where: { $0.id == id }) else { return }
                    draft = failed.text; images = failed.images
                    steer = true; expectedTurn = failed.expectedTurn ?? ""
                }
                .sheet(isPresented: $queueDetails) {
                    NavigationStack {
                        ScrollView {
                            VStack(spacing: 16) {
                                ForEach(relay.outbox.pending(session: session.id)) { item in
                                    OutgoingMessageView(item: item, session: session) { item in queueDetails = false; beginQueueEdit(item) }
                                }
                            }.padding()
                        }.navigationTitle(String(localized: "Next up", bundle: relayLocalizationBundle))
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Close", bundle: relayLocalizationBundle)) { queueDetails = false } } }
                    }
                }
                .sheet(isPresented: $context) { contextSheet(session) }
                .onChange(of: session.turnId) { _, _ in actionsOpen = false }
                .onChange(of: machineOnline(session)) { _, online in if !online { actionsOpen = false } }
                .onChange(of: composing) { _, focused in if focused { actionsOpen = false } }
        } else { ContentUnavailableView(String(localized: "Session unavailable", bundle: relayLocalizationBundle), systemImage: "bubble.left.and.bubble.right") }
    }

    @ViewBuilder private func composer(_ session: RelaySession) -> some View {
        VStack(spacing: 8) {
            if session.readOnly {
                Text(String(localized: "Connect this thread to Codex to send messages.", bundle: relayLocalizationBundle)).font(.caption).foregroundStyle(.secondary)
                Button(String(localized: "Connect thread", bundle: relayLocalizationBundle)) { Task { await relay.action("attach") } }.disabled(!machineOnline(session))
            } else {
                if let editingQueue {
                    HStack {
                        Label(String(localized: "Edit queued message", bundle: relayLocalizationBundle), systemImage: "pencil").font(.caption)
                        Spacer()
                        Button(String(localized: "Cancel", bundle: relayLocalizationBundle)) {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                self.editingQueue = nil; draft = draftBeforeEdit; draftBeforeEdit = ""; images = imagesBeforeEdit; imagesBeforeEdit = []
                            }
                            relay.queueEditError = nil
                        }.font(.caption).disabled(submitting)
                    }.accessibilityIdentifier("composer.editingQueue")
                    if let error = relay.queueEditError { Text(error).font(.caption).foregroundStyle(.orange) }
                    if relay.outbox.items.first(where: { $0.id == editingQueue.id })?.phase != .queued {
                        Text(String(localized: "The message was already dispatched. Your edited text stays here.", bundle: relayLocalizationBundle)).font(.caption).foregroundStyle(.secondary)
                    }
                } else if steer {
                    HStack {
                        Label(String(localized: "Steer · send to the current turn now", bundle: relayLocalizationBundle), systemImage: "arrow.triangle.branch").font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button(String(localized: "Cancel", bundle: relayLocalizationBundle)) { steer = false }.font(.caption)
                    }
                } else if session.status == "NEEDS_YOU" {
                    Button(String(localized: "Go to request", bundle: relayLocalizationBundle), systemImage: "arrow.down.message") { scrollRequest += 1 }.font(.caption).foregroundStyle(.orange).frame(minHeight: 44)
                } else if !machineOnline(session) {
                    Text(String(localized: "Messages can be sent after reconnecting.", bundle: relayLocalizationBundle)).font(.caption).foregroundStyle(.secondary)
                }
                let kind = editingQueue != nil ? "queue_update" : steer ? "steer" : session.defaultCommand
                let available = machineOnline(session) && session.allows(kind) && (editingQueue != nil || ["READY", "WORKING"].contains(session.status))
                let canSend = available && !submitting && loadingImages == 0 && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty) && (images.isEmpty || session.capabilities.canSendImages == true)
                if !images.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(images) { image in
                            ZStack(alignment: .topTrailing) {
                                AttachmentPreview(image: image).frame(width: 72, height: 72)
                                Button { images.removeAll { $0.id == image.id } } label: {
                                    Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.primary, .regularMaterial).frame(width: 44, height: 44)
                                }.accessibilityLabel(String(localized: "Remove image", bundle: relayLocalizationBundle)).disabled(submitting)
                            }
                        }
                        Spacer()
                    }.accessibilityIdentifier("composer.attachments")
                }
                if loadingImages > 0 { ProgressView(String(localized: "Preparing image…", bundle: relayLocalizationBundle)).font(.caption) }
                HStack(alignment: .bottom, spacing: 4) {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { actionsOpen.toggle() }
                    } label: {
                        Image(systemName: actionsOpen ? "xmark" : "plus")
                            .font(.system(size: 20, weight: .regular)).foregroundStyle(.primary)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .disabled(!hasComposerActions(session))
                        .accessibilityLabel(String(localized: "Session actions", bundle: relayLocalizationBundle))
                        .accessibilityValue(actionsOpen ? String(localized: "Expanded", bundle: relayLocalizationBundle) : String(localized: "Collapsed", bundle: relayLocalizationBundle))

                    TextField(steer ? String(localized: "Change the work in progress…", bundle: relayLocalizationBundle) : session.status == "WORKING" ? String(localized: "Add a follow-up…", bundle: relayLocalizationBundle) : String(localized: "Message Codex…", bundle: relayLocalizationBundle), text: $draft, axis: .vertical)
                        .font(.body).lineLimit(1...5).focused($composing).padding(.vertical, 8)
                        .disabled(!available).accessibilityIdentifier("composer.text")
                    Button {
                        if let item = editingQueue {
                            submitting = true
                            let text = draft
                            Task {
                                defer { submitting = false }
                                if await relay.editQueued(item, text: text) {
                                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                        editingQueue = nil; draft = draftBeforeEdit; draftBeforeEdit = ""; images = imagesBeforeEdit; imagesBeforeEdit = []
                                    }
                                }
                            }
                        } else { sendDraft(session, kind: kind, targetTurn: steer ? expectedTurn : nil) }
                    } label: {
                        Image(systemName: editingQueue != nil ? "checkmark" : "arrow.up").font(.body.weight(.semibold))
                            .foregroundStyle(Color(uiColor: .systemBackground))
                            .frame(width: 32, height: 32).background(Color.primary.opacity(canSend ? 1 : 0.15), in: Circle())
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(!canSend)
                    .accessibilityLabel(editingQueue != nil ? String(localized: "Save queued message", bundle: relayLocalizationBundle) : steer ? String(localized: "Send Steer", bundle: relayLocalizationBundle) : session.status == "WORKING" ? String(localized: "Send follow-up", bundle: relayLocalizationBundle) : String(localized: "Send", bundle: relayLocalizationBundle))
                    .accessibilityIdentifier("composer.send")
                    .accessibilityHint(String(localized: "Send a new message", bundle: relayLocalizationBundle))
                }.padding(.horizontal, 2).modifier(ComposerSurface())
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { composerHeight = $0 }
                    .overlay(alignment: .bottomLeading) {
                        if actionsOpen {
                            composerActions(session)
                                .padding(.bottom, composerHeight + 30)
                                .transition(.opacity.combined(with: .offset(y: 4)))
                        }
                    }

            }
        }
    }

    private func currentQuestions(_ session: RelaySession) -> [LiveQuestion] {
        relay.liveQuestions.records.filter { $0.sessionID == session.id && $0.turnID == session.turnId }
    }
    @ViewBuilder private func liveQuestionDock(_ session: RelaySession) -> some View {
        if let first = currentQuestions(session).first {
            Button { questionDetent = compactQuestion(session) ? .medium : .large; questionDetails = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "questionmark.bubble").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Live question", bundle: relayLocalizationBundle)).font(.caption.weight(.semibold))
                        Text(first.activity.questions?.first?.title ?? first.activity.text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Text(String(localized: "Reply", bundle: relayLocalizationBundle)).font(.subheadline.weight(.medium))
                    Image(systemName: "chevron.right").font(.caption2)
                }.frame(minHeight: 44).padding(.horizontal, 20).padding(.vertical, 4).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("session.liveQuestion")
        }
    }
    private func compactQuestion(_ session: RelaySession) -> Bool {
        let questions = currentQuestions(session).flatMap { $0.activity.questions ?? [] }
        return !typeSize.isAccessibilitySize && questions.count == 1
            && questions[0].title.count <= 280 && (questions[0].options?.count ?? 0) <= 3
    }
    private func liveQuestionSheet(_ session: RelaySession) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(currentQuestions(session)) { record in
                        ForEach(Array((record.activity.questions ?? []).enumerated()), id: \.offset) { index, question in
                            LiveQuestionChoices(question: question, index: index,
                                disabled: !machineOnline(session) || !session.allows("steer") || editingQueue != nil || submitting) { answer in
                                prepareReply(answer, record: record, session: session)
                            }
                        }
                    }
                    Text(String(localized: "Prepare a reply, then send it to the current turn. This live question is not a pending approval.", bundle: relayLocalizationBundle)).font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }.navigationTitle(String(localized: "Live question", bundle: relayLocalizationBundle)).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Close", bundle: relayLocalizationBundle)) { questionDetails = false } } }
        }
        .presentationDetents(compactQuestion(session) ? [.medium, .large] : [.large], selection: $questionDetent)
        .presentationDragIndicator(.visible)
        .presentationBackground(.regularMaterial)
        .onChange(of: compactQuestion(session)) { _, compact in if !compact { questionDetent = .large } }
    }
    private func prepareReply(_ answer: String, record: LiveQuestion, session: RelaySession) {
        guard editingQueue == nil, !submitting, machineOnline(session), session.turnId == record.turnID,
              relay.liveQuestions.records.contains(where: { $0.id == record.id }), session.allows("steer") else { return }
        if !answer.isEmpty && draft != answer { draft = draft.isEmpty ? answer : draft + "\n\n" + answer }
        steer = true; expectedTurn = record.turnID; questionDetails = false; composing = true
    }

    @ViewBuilder private func queuedMessages(_ session: RelaySession) -> some View {
        let pending = relay.outbox.pending(session: session.id)
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Label(String(localized: "Next up", bundle: relayLocalizationBundle), systemImage: "text.line.first.and.arrowtriangle.forward")
                    Text("\(pending.count)").foregroundStyle(.secondary)
                    Spacer()
                    Button { queueDetails = true } label: { Image(systemName: "chevron.right").frame(width: 44, height: 24) }
                        .accessibilityLabel(String(localized: "View queued messages", bundle: relayLocalizationBundle))
                }.font(.caption.weight(.medium))
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(pending) { item in
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.text).font(.subheadline).lineLimit(2)
                                    if item.imageCount > 0 { Label(String(localized: "\(item.imageCount) images", bundle: relayLocalizationBundle), systemImage: "photo").font(.caption) }
                                    Text(item.phase == .queued ? "FOLLOW-UP · QUEUED" : item.phase == .unconfirmed ? String(localized: "No longer queued · check conversation", bundle: relayLocalizationBundle) : item.phase == .failed ? item.error ?? "Send failed" : "Sending…")
                                        .font(.caption2).foregroundStyle(item.phase == .failed ? RelayPalette.failure : .secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                if item.phase == .queued && item.queueEditable {
                                    Button { beginQueueEdit(item) } label: { Image(systemName: "pencil").frame(width: 44, height: 44) }
                                        .disabled(!machineOnline(session) || !session.allows("queue_update"))
                                        .accessibilityLabel(String(localized: "Edit queued message", bundle: relayLocalizationBundle))
                                }
                            }.padding(.vertical, 6).accessibilityElement(children: .contain).accessibilityIdentifier("queue." + item.id)
                        }
                    }
                }.frame(maxHeight: pending.count == 1 ? 66 : 120)
            }.padding(.horizontal, 20).padding(.vertical, 6)
                .background(.primary.opacity(0.035)).accessibilityIdentifier("session.queue")
        }
    }

    private func hasComposerActions(_ session: RelaySession) -> Bool {
        machineOnline(session) && (session.capabilities.canSendImages == true || session.allows("steer") || session.allows("interrupt") ||
            (session.allows("queue_update") && relay.outbox.visible(session: session.id).contains { $0.phase == .queued && $0.queueEditable }))
    }

    private func composerActions(_ session: RelaySession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if session.capabilities.canSendImages == true {
                Button { actionsOpen = false; showPhotos = true } label: {
                    Label(String(localized: "Add photos", bundle: relayLocalizationBundle), systemImage: "photo")
                        .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
                }.disabled(editingQueue != nil || submitting || images.count + loadingImages >= ImageInput.maxCount)
                Divider()
            }
            if machineOnline(session) && session.allows("steer") {
                Button {
                    actionsOpen = false
                    if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty {
                        sendDraft(session, kind: "steer", targetTurn: session.turnId)
                    } else { steer.toggle(); expectedTurn = session.turnId ?? ""; composing = true }
                } label: {
                    Label(!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty ? String(localized: "Send to current turn", bundle: relayLocalizationBundle) : steer ? String(localized: "Back to follow-up", bundle: relayLocalizationBundle) : String(localized: "Steer Current Turn", bundle: relayLocalizationBundle), systemImage: "arrow.triangle.branch")
                        .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
                }.disabled(editingQueue != nil || submitting || loadingImages > 0)
            }
            if machineOnline(session) && session.allows("queue_update"), let last = relay.outbox.visible(session: session.id).last(where: { $0.phase == .queued && $0.queueEditable }) {
                Button { actionsOpen = false; beginQueueEdit(last) } label: {
                    Label(String(localized: "Edit Last Queued Message", bundle: relayLocalizationBundle), systemImage: "pencil")
                        .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
                }.disabled(submitting)
            }
            if machineOnline(session) && session.allows("interrupt") {
                Divider()
                Button(role: .destructive) { actionsOpen = false; interruptTurn = session.turnId ?? ""; interrupt = true } label: {
                    Label(String(localized: "Interrupt Turn", bundle: relayLocalizationBundle), systemImage: "stop.circle").foregroundStyle(RelayPalette.failure)
                        .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
                }
            }
        }.font(.subheadline).buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 6)
            .frame(width: 270).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.15), radius: 16, y: 4)
    }

    private func beginQueueEdit(_ item: Outgoing) {
        guard !submitting else { return }
        if editingQueue == nil { draftBeforeEdit = draft; imagesBeforeEdit = images; images = [] }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            editingQueue = item; draft = item.text; steer = false
        }
        relay.queueEditError = nil; composing = true
    }

    private func sendDraft(_ session: RelaySession, kind: String, targetTurn: String?) {
        guard !submitting else { return }
        let text = draft, attachments = images
        submitting = true
        Task {
            defer { submitting = false }
            guard relay.current?.id == session.id else { return }
            if await relay.submit(text, images: attachments, kind: kind, expectedTurn: targetTurn) {
                if draft == text { draft = "" }
                if images == attachments { images = [] }
                steer = false; scrollRequest += 1
            }
        }
    }

    private func importImage(_ data: Data?, sessionID: String) async {
        defer { loadingImages -= 1; actionsOpen = false }
        guard let data, relay.current?.id == sessionID, images.count < ImageInput.maxCount else { return }
        let prepared = await Task.detached(priority: .userInitiated) { prepareAttachment(data) }.value
        guard let prepared else { relay.error = String(localized: "This image could not be prepared. Choose a smaller photo or screenshot.", bundle: relayLocalizationBundle); return }
        if relay.current?.id == sessionID, images.count < ImageInput.maxCount { images.append(prepared) }
    }

    private func contextSheet(_ session: RelaySession) -> some View {
        NavigationStack {
            List {
                LabeledContent(String(localized: "Machine", bundle: relayLocalizationBundle), value: relay.machines[session.machineId]?.name ?? session.machineId)
                LabeledContent(String(localized: "Project", bundle: relayLocalizationBundle), value: session.project)
                LabeledContent(String(localized: "Folder", bundle: relayLocalizationBundle), value: session.cwd)
                if let branch = session.branch, !branch.isEmpty { LabeledContent("Branch", value: branch) }
                LabeledContent("Thread", value: session.threadId)
                if let machine = relay.machines[session.machineId] {
                    if let version = machine.codexVersion { LabeledContent("Codex", value: version) }
                    if let account = machine.account { LabeledContent(String(localized: "Codex Account", bundle: relayLocalizationBundle), value: account.email ?? account.kind) }
                    LabeledContent(String(localized: "Connection", bundle: relayLocalizationBundle), value: relay.machineConnectionLabel(machine.id))
                }
                if let usage = session.tokenUsage { SessionUsageView(usage: usage) }
                Text(String(localized: "This chat shows temporary recent context. History remains in Codex.", bundle: relayLocalizationBundle)).font(.footnote).foregroundStyle(.secondary)
            }.textSelection(.enabled).navigationTitle(String(localized: "Session Info", bundle: relayLocalizationBundle)).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Close", bundle: relayLocalizationBundle)) { context = false } } }
        }
    }
}

// Owns high-frequency transcript observation and scroll state. The composer,
private struct LiveQuestionChoices: View {
    let question: AsyncQuestion
    let index: Int
    let disabled: Bool
    let prepare: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChatMarkdown(text: question.title, identifier: "liveQuestion.title.\(index)")
            ForEach(question.options ?? [], id: \.self) { option in
                Button { prepare(option) } label: {
                    HStack {
                        Text(option).multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.down.to.line")
                    }.frame(minHeight: 44)
                }.buttonStyle(.bordered).disabled(disabled)
            }
            Button(String(localized: "Write a reply", bundle: relayLocalizationBundle), systemImage: "square.and.pencil") {
                prepare("")
            }.frame(minHeight: 44).disabled(disabled)
        }
    }
}

// header and heartbeat observe only their own canonical metadata.
private struct SessionTranscript: View {
    @Environment(RelayController.self) private var relay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: RelaySession
    @Binding var scrollRequest: Int
    let onEdit: (Outgoing) -> Void
    let onQuestionReply: (String) -> Void
    private struct ActivitySelection: Identifiable {
        let group: TranscriptGroup
        let route: ActivityRoute
        var id: String { group.id + "/" + route.identity }
    }
    @State private var tools: ActivitySelection?
    @State private var scrolling = TranscriptScrollPolicy()
    @State private var initialScroll = false
    @State private var historyPositioned = false
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
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    // Keep stable geometry when reading older history and returning
                    // from the keyboard; the selected-session memory is bounded.
                    VStack(alignment: .leading, spacing: RelaySpacing.page) {
                        if relay.historyLoading {
                            ProgressView(String(localized: "Loading history…", bundle: relayLocalizationBundle)).font(.caption).frame(maxWidth: .infinity)
                        } else if relay.historyCursor != nil && !relay.chat.atCapacity {
                            Button(String(localized: "Load earlier messages", bundle: relayLocalizationBundle)) {
                                scrolling.readHistory()
                                Task { await relay.loadOlderHistory() }
                            }.frame(minHeight: 44).frame(maxWidth: .infinity).accessibilityIdentifier("history.older")
                                .accessibilityValue(String(localized: "\(relay.chat.items.count) items loaded", bundle: relayLocalizationBundle))
                                .disabled(!machineOnline(session))
                        }
                        if let error = relay.historyError {
                            Text(error).font(.caption).foregroundStyle(.secondary)
                            if relay.registry?.machines.first(where: { $0.id == session.machineId })?.access == "PAUSED" {
                                Button(String(localized: "Resume Relay on this machine", bundle: relayLocalizationBundle)) { Task { await relay.manageMachine(session.machineId, action: "resume") } }
                                    .font(.subheadline).frame(minHeight: 44)
                            }
                        }
                        if relay.chat.atCapacity || relay.chat.trimmed {
                            Text(String(localized: "The memory window is limited. Full history remains in Codex.", bundle: relayLocalizationBundle))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(TranscriptGroup.make(relay.chat.items)) { group in
                            if let activity = group.items.first, activity.kind == "context_compaction" {
                                Label(activity.state == "running" && activity.turnId == session.turnId && session.displayStatus(machine: relay.machines[session.machineId], connected: relay.online) == "WORKING" ? String(localized: "Compacting context", bundle: relayLocalizationBundle) : activity.state == "completed" ? String(localized: "Context compacted", bundle: relayLocalizationBundle) : String(localized: "Context compaction", bundle: relayLocalizationBundle), systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("context.compaction")
                            } else if group.kind == .message, let activity = group.items.first {
                                // A currently observed question has one interactive home.
                                // When retired, its original upstream item remains readable here.
                                if !relay.liveQuestions.records.contains(where: { $0.sessionID == session.id && $0.turnID == session.turnId && $0.activity.id == activity.id }) {
                                    ChatMessageView(activity: activity, images: relay.outbox.images(session: session.id, clientID: activity.clientId), liveQuestion: false, onQuestionReply: onQuestionReply).equatable()
                                }
                            } else {
                                ToolSummaryView(group: group) { route in tools = ActivitySelection(group: group, route: route) }
                            }
                        }
                        ForEach(relay.outbox.conversation(session: session.id)) { item in
                            OutgoingMessageView(item: item, session: session, onEdit: onEdit)
                        }
                        ForEach(relay.requests.values.filter { $0.sessionId == session.id }.sorted { $0.id < $1.id }) { request in
                            PendingView(request: request).id(request.presentationID)
                        }
                        if relay.chat.items.isEmpty && relay.outbox.visible(session: session.id).isEmpty {
                            Text(String(localized: "Recent Codex context will appear here.", bundle: relayLocalizationBundle)).font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 24)
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
                .modifier(TranscriptScrollInteraction(
                    begin: { scrolling.beginInteraction() },
                    end: { scrolling.endInteraction(distanceFromBottom: $0) }
                ))
                .onChange(of: viewport.size, initial: true) { _, size in
                    guard size.height > 0, !initialScroll || scrolling.shouldFollow else { return }
                    // Navigation and keyboard layout settle after this callback.
                    // Preserve the latest position only while the reader follows.
                    DispatchQueue.main.async {
                        guard scrolling.shouldFollow else { return }
                        proxy.scrollTo(bottomID, anchor: .bottom)
                        initialScroll = true
                    }
                }
                .onPreferenceChange(TranscriptBottom.self) { value in
                    // Never infer reader intent from geometry: a short upward
                    // scroll, inertia, or keyboard resize must not re-enable follow.
                    if scrolling.shouldFollow && value > viewport.size.height + 12 {
                        DispatchQueue.main.async {
                            if scrolling.shouldFollow { proxy.scrollTo(bottomID, anchor: .bottom) }
                        }
                    }
                }
                .onChange(of: relay.historyLoading) { _, loading in
                    guard !loading, !historyPositioned, relay.historyError == nil else { return }
                    historyPositioned = true
                    // The initial empty viewport can lay out before canonical
                    // history arrives. Position after that first hydration too.
                    DispatchQueue.main.async { if scrolling.shouldFollow { proxy.scrollTo(bottomID, anchor: .bottom) } }
                }
                .onChange(of: revision) { _, _ in
                    if scrolling.shouldFollow { DispatchQueue.main.async { if scrolling.shouldFollow { proxy.scrollTo(bottomID, anchor: .bottom) } } }
                }
                .onChange(of: scrollRequest) { _, _ in
                    scrolling.jumpToLatest()
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(bottomID, anchor: .bottom) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !scrolling.followsLatest && !scrolling.isInteracting {
                        Button { scrollRequest += 1 } label: { Label(String(localized: "Latest messages", bundle: relayLocalizationBundle), systemImage: "arrow.down") }
                            .labelStyle(.iconOnly).font(.subheadline.weight(.semibold)).frame(width: 44, height: 44)
                            .background(.regularMaterial, in: Circle()).buttonStyle(.plain).padding(8)
                            .accessibilityIdentifier("transcript.latest")
                    }
                }
            }
        }.sheet(item: $tools) { ToolDetailView(group: $0.group, route: $0.route) }
    }
}

// Native phases include deceleration after the finger lifts. A DragGesture
// alone ends too early and can let scrollTo fight the scroll view's inertia.
private struct TranscriptScrollInteraction: ViewModifier {
    let begin: () -> Void
    let end: (Double?) -> Void
    @State private var userInitiated = false
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase, context in
                switch phase {
                case .tracking, .interacting, .decelerating:
                    if !userInitiated { userInitiated = true; begin() }
                case .idle:
                    if userInitiated {
                        userInitiated = false
                        let g = context.geometry
                        end(Double(g.contentSize.height + g.contentInsets.bottom - g.contentOffset.y - g.containerSize.height))
                    }
                default: break // Programmatic animation is not reader intent.
                }
            }
        } else {
            // iOS 17 has no scroll-phase API. Once the reader moves, require
            // Latest messages explicitly rather than guessing when inertia ends.
            content.simultaneousGesture(DragGesture(minimumDistance: 3)
                .onChanged { _ in if !userInitiated { userInitiated = true; begin() } }
                .onEnded { _ in userInitiated = false; end(nil) })
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
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.primary.opacity(0.1)))
        }
    }
}

private struct ChatMessageView: View, Equatable {
    let activity: Activity
    let images: [ImageInput]
    let liveQuestion: Bool
    let onQuestionReply: (String) -> Void
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.activity == rhs.activity && lhs.images == rhs.images && lhs.liveQuestion == rhs.liveQuestion }
    private var user: Bool { activity.kind == "userMessage" }
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if user { Spacer(minLength: 44) }
            VStack(alignment: user ? .trailing : .leading, spacing: 8) {
                if user {
                    if !images.isEmpty { HStack { ForEach(images) { AttachmentPreview(image: $0).frame(width: 108, height: 108) } } }
                    else if let count = activity.imageCount, count > 0 { Label(String(localized: "\(count) images", bundle: relayLocalizationBundle), systemImage: "photo").font(.caption).foregroundStyle(.secondary) }
                    VStack(alignment: .leading, spacing: 8) {
                        if let replies = activity.replies, !replies.isEmpty {
                            ForEach(Array(replies.enumerated()), id: \.offset) { _, reply in
                                ChatMarkdown(text: reply.question, identifier: "reply.context." + activity.id, compact: true)
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(reply.answer).font(.body).textSelection(.enabled)
                            }
                        } else if !activity.text.isEmpty { Text(activity.text).font(.body).textSelection(.enabled) }
                    }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
                        .accessibilityIdentifier("activity." + activity.kind + "." + activity.id)
                } else {
                    let questions = activity.questions ?? []
                    if questions.isEmpty || activity.text != questions.map(\.title).joined(separator: "\n\n") {
                        ChatMarkdown(text: activity.text, identifier: "activity." + activity.kind + "." + activity.id)
                    }
                    ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                        // Conversation content is readable once. Current actions have
                        // one home in the live-question dock above the composer.
                        if activity.text == questions.map(\.title).joined(separator: "\n\n") || !activity.text.contains(question.title) {
                            ChatMarkdown(text: question.title, identifier: "question." + activity.id + ".\(index)")
                        }
                        if !liveQuestion {
                            ForEach(Array((question.options ?? []).enumerated()), id: \.offset) { _, option in
                                if !activity.text.contains(option) {
                                    Text("• " + option).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }
                        }
                    }
                    if activity.truncated == true { Text(String(localized: "Partial context · see Codex for the full content.", bundle: relayLocalizationBundle)).font(.caption).foregroundStyle(.secondary) }
                }
            }.frame(maxWidth: .infinity, alignment: user ? .trailing : .leading)
                .environment(\.completeMessage, activity.text)
                .contextMenu {
                    Button(String(localized: "Copy Full Message", bundle: relayLocalizationBundle), systemImage: "doc.on.doc") { UIPasteboard.general.string = activity.text }
                    if !user { ShareLink(item: activity.text) { Label(String(localized: "Share", bundle: relayLocalizationBundle), systemImage: "square.and.arrow.up") } }
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
        let kind = item.kind == "follow_up" ? "FOLLOW-UP" : item.kind == "steer" ? "STEER" : String(localized: "NEW TURN", bundle: relayLocalizationBundle)
        let phase: String
        switch item.phase {
        case .unconfirmed: phase = String(localized: "LEFT QUEUE · VERIFYING", bundle: relayLocalizationBundle)
        case .local, .sending, .steering: phase = String(localized: "SENDING…", bundle: relayLocalizationBundle)
        case .queued: phase = String(localized: "QUEUED", bundle: relayLocalizationBundle)
        case .dispatched: phase = String(localized: "RUNNING", bundle: relayLocalizationBundle)
        case .accepted: phase = String(localized: "SENT", bundle: relayLocalizationBundle)
        case .applied: phase = String(localized: "APPLIED", bundle: relayLocalizationBundle)
        case .failed: phase = item.errorCode == "UNKNOWN_OUTCOME" ? String(localized: "VERIFY OUTCOME", bundle: relayLocalizationBundle) : String(localized: "SEND FAILED", bundle: relayLocalizationBundle)
        case .materialized: phase = ""
        }
        return kind + " · " + phase
    }
    var body: some View {
        HStack {
            Spacer(minLength: 44)
            VStack(alignment: .trailing, spacing: 8) {
                if !item.images.isEmpty { HStack { ForEach(item.images) { AttachmentPreview(image: $0).frame(width: 108, height: 108) } } }
                else if item.imageCount > 0 { Label(String(localized: "\(item.imageCount) images", bundle: relayLocalizationBundle), systemImage: "photo").font(.caption) }
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
                    Button(String(localized: "Edit", bundle: relayLocalizationBundle), systemImage: "pencil") { onEdit(item) }.font(.caption).frame(minHeight: 44)
                        .disabled(!session.allows("queue_update") || !relay.online || relay.machines[session.machineId]?.status != "ONLINE" || relay.queueEditingID != nil)
                }
                if item.phase == .unconfirmed {
                    Text(String(localized: "Codex no longer lists this message in the queue. Its outcome is not yet confirmed. Check the conversation before sending again.", bundle: relayLocalizationBundle)).font(.caption).foregroundStyle(.secondary)
                    Button(String(localized: "Discard", bundle: relayLocalizationBundle)) { relay.outbox.discard(item.id) }
                }
                if item.phase == .failed {
                    Text(item.error ?? String(localized: "Send failed", bundle: relayLocalizationBundle)).font(.caption).foregroundStyle(.orange)
                    if session.allows(item.kind) {
                        Button(item.errorCode == "UNKNOWN_OUTCOME" ? String(localized: "I checked Codex: resend", bundle: relayLocalizationBundle) : String(localized: "Retry", bundle: relayLocalizationBundle)) { Task { await relay.retry(item) } }
                            .disabled(!relay.online || relay.machines[session.machineId]?.status != "ONLINE")
                    }
                    if item.kind == "steer", session.allows(session.defaultCommand) {
                        Button(session.defaultCommand == "follow_up" ? String(localized: "Send as follow-up", bundle: relayLocalizationBundle) : String(localized: "Send as new turn", bundle: relayLocalizationBundle)) { Task { await relay.retry(item, as: session.defaultCommand) } }
                            .disabled(!relay.online || relay.machines[session.machineId]?.status != "ONLINE")
                    }
                    Button(String(localized: "Discard", bundle: relayLocalizationBundle)) { relay.outbox.discard(item.id) }
                }
            }.font(.subheadline)
        }
    }
}

private func conversationStatus(_ status: String) -> String {
    ["WORKING": String(localized: "Working", bundle: relayLocalizationBundle), "READY": String(localized: "Ready", bundle: relayLocalizationBundle), "NEEDS_YOU": String(localized: "Needs You", bundle: relayLocalizationBundle), "INACTIVE": String(localized: "Inactive", bundle: relayLocalizationBundle), "FAILED": String(localized: "Error", bundle: relayLocalizationBundle)][status] ?? status
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
                if state == "WORKING" {
                    WorkingText(text: relay.liveActivities[session.id].flatMap { $0.kind == "context_compaction" && $0.state == "running" ? $0.title : nil } ?? statusLabel("WORKING")).accessibilityIdentifier("session.connection")
                        .accessibilityValue(String(localized: "Live", bundle: relayLocalizationBundle))
                } else {
                    SessionStatusMark(status: state)
                    Text(state == "OFFLINE" ? relay.machineConnectionLabel(session.machineId) : statusLabel(state))
                        .accessibilityIdentifier("session.connection")
                        .accessibilityValue(state == "OFFLINE" ? String(localized: "Offline", bundle: relayLocalizationBundle) : ["SYNCING", "RECONNECTING", "DEGRADED"].contains(state) ? statusLabel(state) : String(localized: "Live", bundle: relayLocalizationBundle))
                }
                if state == "WORKING" { ElapsedLabel(start: session.turnStarted) }
                Spacer(minLength: 0)
            }.font(.caption.weight(.medium))
            if ["OFFLINE", "SYNCING", "RECONNECTING", "DEGRADED"].contains(state) {
                LastKnownSession(session: session, machine: relay.machines[session.machineId]).accessibilityIdentifier("session.stale")
            }
        }.padding(.top, RelaySpacing.compact)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: state)
    }
}

/// Only this small text mask redraws; transcript and composer do not animate.
struct WorkingText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let text: String
    var highlight: Color = .primary
    private var label: Text { Text(text) }
    var body: some View {
        label.foregroundStyle(reduceMotion ? highlight : .secondary)
            .overlay {
                if !reduceMotion {
                    GeometryReader { geometry in
                        TimelineView(.animation(minimumInterval: 1.0 / 24)) { context in
                            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.4) / 3.4
                            LinearGradient(colors: [.clear, highlight.opacity(0.95), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: geometry.size.width * 0.75)
                                .offset(x: geometry.size.width * (phase * 2 - 0.75))
                        }
                    }.mask(label).accessibilityHidden(true)
                }
            }
    }
}


/// Decode a bounded thumbnail and strip location/EXIF metadata before transport.
private func prepareAttachment(_ data: Data) -> ImageInput? {
    guard data.count <= 20 * 1024 * 1024,
          let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1600] as CFDictionary) else { return nil }
    let image = UIImage(cgImage: thumbnail)
    for quality in [0.85, 0.65, 0.45, 0.25] {
        if let encoded = image.jpegData(compressionQuality: quality), encoded.count <= ImageInput.maxBytes { return ImageInput(data: encoded) }
    }
    return nil
}

private struct AttachmentPreview: View {
    let image: ImageInput
    @State private var expanded = false
    var body: some View {
        if let bitmap = UIImage(data: image.data) {
            Button { expanded = true } label: {
                Image(uiImage: bitmap).resizable().scaledToFill().frame(maxWidth: .infinity, maxHeight: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).accessibilityLabel(String(localized: "View image", bundle: relayLocalizationBundle))
                .sheet(isPresented: $expanded) {
                    NavigationStack {
                        Image(uiImage: bitmap).resizable().scaledToFit().padding()
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Close", bundle: relayLocalizationBundle)) { expanded = false } } }
                    }
                }
        }
    }
}
