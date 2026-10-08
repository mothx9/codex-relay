import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

@MainActor @Observable final class RelayController {
    var credential: Credential?
    var machines: [String: Machine] = [:]
    var sessions: [String: RelaySession] = [:]
    var catalogue = SessionCatalogue()
    var catalogueLoading: Set<String> = []
    var catalogueErrors: [String: String] = [:]
    private var catalogueCommands: [String: (machine: String, epoch: String?)] = [:]
    var fleetSessions: [String: RelaySession] { catalogue.merged(canonical: sessions) }
    var liveActivities: [String: LiveActivity] = [:]
    var requests: [String: PendingRequest] = [:]
    var requestProgress: [String: String] = [:]
    var requestErrors: [String: String] = [:]
    private var requestCommands: [String: String] = [:]
    var chat = RecentChat()
    var historyCursor: String?
    var historyLoading = false
    var historyError: String?
    private var historyRequestID: String?
    private var restoredWatch = false
    private var historyCorrelated = false
    private var issuedHistoryIDs: [String] = []
    var queueEditError: String?
    var queueEditingID: String?
    var queueSteeringID: String?
    private var queueSteerCommands: [String: String] = [:]
    private var queueWaiters: [String: CheckedContinuation<Bool, Never>] = [:]
    var outbox = Outbox()
    var selected: String = ""
    var returnToFleet = 0
    var routedMachine: String?
    var pendingNavigation = PendingNavigation()
    var navigationStatus: String?
    private var navigationTask: Task<Void, Never>?
    var online = false
    var connection = String(localized: "Sign-in required", bundle: relayLocalizationBundle)
    var connectionIssue: ConnectionIssue?
    var connectionAttempts = 0
    var error: String?
    var registry: DeviceRegistry?
    var accounts: [AccountEntry] = []
    var diagnostics: RelayDiagnostics?
    var diagnosticsUpdatedAt: Date?
    var settingsProgress: [String: String] = [:]
    var settingsErrors: [String: String] = [:]
    var notificationAllowed = false
    var notificationsEnabled = false
    var appleRegistrationFailed = false
    var localNoticePolicy = LocalNoticePolicy()
    var presentedNotices: [String] = []
    var appliedNotificationBadge: Int?
    var offlineNoticeTasks: [String: Task<Void, Never>] = [:]
    var notificationPermission = String(localized: "Needs verification", bundle: relayLocalizationBundle)
    var pushRegistered = false
    var pushRegistrationVerifiedAt: Date?
    var pairingError: String?
    var pairCode: PairCode?
    var busy = false
    var nativePushAvailable = false
    var notificationStatus = String(localized: "Notifications not enabled", bundle: relayLocalizationBundle)
    var apnsToken: String?
    private var socket: URLSessionWebSocketTask?
    private var socketHealth: SocketHealth?
    private var transport: URLSession?
    private var loop: Task<Void, Never>?
    private var generation = UUID()
    private var seen: [String] = []
    private var eventFreshness = EventFreshness()
    private var attentionFreshness = EventFreshness()
    var receiptTiming = ReceiptTiming()
    var liveQuestions = LiveQuestions()
    private var paused = false
    private var commands: Set<String> = []
    private var lastBackground: Date?
    let previewOnly: Bool

    init(preview: Bool = false) {
        previewOnly = preview || ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        if !previewOnly { credential = CredentialVault.load(); if credential != nil { connect() } }
    }
    var api: HubAPI? { previewOnly ? nil : credential.flatMap { try? HubAPI(url: $0.hubUrl, token: $0.token) } }
    var current: RelaySession? { sessions[selected] ?? catalogue.sessions[selected] }
    func pair(url: String, code: String) async {
        guard !previewOnly else { return }
        guard !busy else { return }; busy = true; pairingError = nil; defer { busy = false }
        do {
            let api = try HubAPI(url: url)
            let credential: Credential = try await api.fetch("api/pairing/exchange", body: ["kind": "operator", "code": code])
            guard credential.kind == "operator", credential.token.count >= 32 else { throw HubFailure.message(String(localized: "Invalid pairing response.", bundle: relayLocalizationBundle)) }
            try CredentialVault.save(credential); self.credential = credential; pairingError = nil; connect()
        } catch { self.pairingError = error.localizedDescription }
    }
    func connect() {
        guard !previewOnly else { return }
        stop(); guard let api, !paused else { return }; generation = UUID(); let generation = generation
        connectionIssue = nil; connectionAttempts = 0
        let fingerprint = api.origin.absoluteString.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        traceConnection("origin_fingerprint=\(String(fingerprint, radix: 16)) tailnet=\(api.origin.host?.hasSuffix(".ts.net") == true)")
        loop = Task { [weak self] in
            var attempt = 0
            while !Task.isCancelled {
                guard let self, self.generation == generation else { return }
                do {
                    self.connection = self.connectionIssue?.title ?? String(localized: "Connecting to Hub…", bundle: relayLocalizationBundle)
                    self.connectionAttempts += 1
                    self.traceConnection("connecting attempt=\(self.connectionAttempts)")
                    let config = URLSessionConfiguration.ephemeral; config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
                    let delegate = NoRedirect { [weak self] metrics in
                        let stages = metrics.transactionMetrics.map { "dns=\($0.domainLookupEndDate != nil) tcp=\($0.connectEndDate != nil) tls=\($0.secureConnectionEndDate != nil) proxy=\($0.isProxyConnection) reused=\($0.isReusedConnection)" }.joined(separator: ";")
                        Task { @MainActor in self?.traceConnection("transport \(stages)") }
                    }
                    let transport = URLSession(configuration: config, delegate: delegate, delegateQueue: nil); self.transport = transport
                    let socket = transport.webSocketTask(with: api.socketRequest()); socket.maximumMessageSize = 1_048_576
                    self.socket = socket; self.socketHealth = SocketHealth(now: ProcessInfo.processInfo.systemUptime); socket.resume()
                    if ProcessInfo.processInfo.arguments.contains("--connection-diagnostics") {
                        Task { [weak self] in
                            let started = ProcessInfo.processInfo.systemUptime
                            do {
                                let (_, response) = try await transport.data(for: api.request(path: "healthz"))
                                self?.traceConnection("https probe status=\((response as? HTTPURLResponse)?.statusCode ?? 0) elapsed_ms=\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000))")
                            } catch { self?.traceConnection("https probe reason=\(ConnectionIssue(error: error).diagnostic)") }
                        }
                    }
                    // The live stream comes first. Optional bootstrap/account
                    // reads must never delay admission or foreground recovery.
                    let watchdog = Task { [weak self] in
                        while !Task.isCancelled {
                            do { try await Task.sleep(for: .seconds(1)) } catch { return }
                            guard let self, self.generation == generation, self.socket === socket else { return }
                            switch self.socketHealth?.action(now: ProcessInfo.processInfo.systemUptime) {
                            case .reconnect:
                                self.connectionIssue = ConnectionIssue(kind: self.online ? .pongTimeout : .snapshotTimeout)
                                socket.cancel(with: .goingAway, reason: nil); return
                            case .ping:
                                socket.sendPing { [weak self] error in
                                    Task { @MainActor in
                                        guard let self, self.generation == generation, self.socket === socket else { return }
                                        if let error { self.connectionIssue = ConnectionIssue(error: error); socket.cancel(with: .goingAway, reason: nil) }
                                        else { self.socketHealth?.pongReceived(now: ProcessInfo.processInfo.systemUptime) }
                                    }
                                }
                            default: break
                            }
                        }
                    }
                    defer { watchdog.cancel() }
                    var bootstrapped = false
                    while !Task.isCancelled {
                        let message = try await socket.receive(); guard self.generation == generation else { return }
                        let data: Data
                        switch message { case .data(let d): data = d; case .string(let s): data = Data(s.utf8); @unknown default: continue }
                        let decoded = try RelayJSON.decoder().decode(WireMessage.self, from: data)
                        if decoded.type == "snapshot", decoded.snapshot != nil {
                            self.socketHealth?.snapshotReceived(); attempt = 0; self.connectionIssue = nil
                            if !bootstrapped { self.traceConnection("snapshot admitted") }
                            if !bootstrapped {
                                bootstrapped = true
                                Task { [weak self] in
                                    let bootstrap: AckBootstrap? = try? await api.fetch("api/bootstrap")
                                    guard let self, self.generation == generation, self.socket === socket, let bootstrap else { return }
                                    self.nativePushAvailable = bootstrap.nativePush ?? false
                                    await self.refreshNativePush()
                                }
                            }
                        }
                        await self.apply(decoded)
                    }
                } catch {
                    guard self.generation == generation, !Task.isCancelled else { return }
                    let status = (self.socket?.response as? HTTPURLResponse)?.statusCode
                    let path = String(describing: (error as NSError).userInfo["_NSURLErrorNWPathKey"] ?? "")
                    self.traceConnection("path local_denied=\(path.contains("Local network prohibited")) vpn=\(path.contains("utun")) satisfied=\(path.contains("satisfied"))")
                    // Preserve a watchdog/ping cause instead of replacing it
                    // with the cancellation that wakes socket.receive().
                    if self.connectionIssue == nil || (error as NSError).code != NSURLErrorCancelled {
                        self.connectionIssue = ConnectionIssue(error: error, httpStatus: status)
                    }
                    self.traceConnection("disconnected reason=\(self.connectionIssue?.diagnostic ?? "unknown") http=\(status ?? 0)")
                    let hubError = (error as? HubFailure) ?? status.flatMap { code in
                        code == 101 ? nil : HubFailure.http(code, code == 401 || code == 403 ? String(localized: "Code expired or access revoked or invalid.", bundle: relayLocalizationBundle) : String(localized: "Hub unavailable (\(code)).", bundle: relayLocalizationBundle))
                    }
                    self.liveQuestions.reset(); self.online = false; self.restoredWatch = false; self.historyLoading = false; self.historyRequestID = nil; self.outbox.disconnected(); for id in Array(self.queueWaiters.keys) { self.finishQueueEditUnknown(id) }; self.commands.removeAll(); self.catalogueCommands.removeAll(); self.catalogueLoading.removeAll(); self.socket?.cancel(with: .goingAway, reason: nil); self.transport?.invalidateAndCancel()
                    self.socket = nil; self.socketHealth = nil; self.transport = nil
                    self.updateNotificationBadge(); self.cancelOfflineNotices()
                    self.connection = self.connectionIssue?.title ?? String(localized: "Offline · reconnecting", bundle: relayLocalizationBundle)
                    if let hubError {
                        if hubError.authenticationRequired { self.forget(preserveNavigation: true); self.error = hubError.localizedDescription; return }
                        if !hubError.retryable { self.error = hubError.localizedDescription; self.connection = String(localized: "Hub error", bundle: relayLocalizationBundle); return }
                    }
                    let delay = SocketHealth.retryDelay(attempt: attempt, jitter: Double.random(in: 0.5...1.0)); attempt += 1
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
        }
    }
    private func traceConnection(_ message: String) {
        if ProcessInfo.processInfo.arguments.contains("--connection-diagnostics") {
            print("RELAY_CONNECTION t=\(Int(ProcessInfo.processInfo.systemUptime)) \(message)")
            fflush(stdout)
        }
    }
    private func apply(_ message: WireMessage) async {
        switch message.type {
        case "snapshot":
            guard let snapshot = message.snapshot else { return }
            let reconnecting = !online
            eventFreshness.snapshot(snapshot.machines)
            attentionFreshness.snapshot(snapshot.machines)
            let previousMachines = machines
            liveActivities = snapshot.liveActivities ?? [:]
            machines = Dictionary(uniqueKeysWithValues: snapshot.machines.map { ($0.id, $0) }); sessions = Dictionary(uniqueKeysWithValues: snapshot.sessions.map { ($0.id, $0) })
            requests = Dictionary(uniqueKeysWithValues: snapshot.requests.map { ($0.id, $0.retainingContext(from: requests[$0.id])) }); online = true; connection = String(localized: "Live · \(machines.values.filter { $0.status == "ONLINE" }.count) machines", bundle: relayLocalizationBundle)
            reconcileLiveQuestions()
            observeOfflineMachines(previous: previousMachines)
            let activeRequests = Set(requests.values.map(\.presentationID))
            requestProgress = requestProgress.filter { activeRequests.contains($0.key) }
            requestErrors = requestErrors.filter { activeRequests.contains($0.key) }
            if !selected.isEmpty && !restoredWatch { await watchSelected() }
            updateNotificationBadge()
            resolveNavigation()
            Task { await loadDevices(); if reconnecting { await refreshNativePush() } }
        case "attention":
            guard let event = message.event, attentionFreshness.accept(event) else { return }
            observeLiveQuestion(event)
            if let notice = SemanticNotice.event(event), liveQuestions.records.contains(where: { $0.id == notice.key }) { deliverLocalNotice(notice) }
            updateNotificationBadge()
        case "devices_changed": Task { await loadDevices() }
        case "event", "pending":
            guard let event = message.event else { return }
            let received = Date()
            defer { receiptTiming.observe(hub: event.hubObservedAt, received: received, reduced: Date()) }
            if event.kind == "live_activity" { liveActivities[event.sessionId] = event.liveActivity; return }
            if let id = event.eventId, !id.isEmpty {
                if seen.contains(id) {
                    // The Hub sends a stripped fleet event, then the same event
                    // ID with private form context to this session's watcher.
                    if message.type == "pending", let incoming = event.request,
                       let prior = requests[incoming.id], incoming.presentationID == prior.presentationID {
                        requests[incoming.id] = incoming.retainingContext(from: prior)
                    }
					if message.type == "pending", event.kind == "failed", event.sessionId == selected, event.activity?.kind == "turnError" {
						chat.apply(event)
					}
                    return
                }
                seen.append(id); if seen.count > 1024 { seen.removeFirst(seen.count - 1024) }
            }
            guard eventFreshness.accept(event) else { return }
            if let session = event.session { sessions[session.id] = session }
            if let request = event.request { requests[request.id] = request.retainingContext(from: requests[request.id]) }
            if event.kind == "request_resolved", let id = event.requestId { requests.removeValue(forKey: id) }
            if event.request != nil || event.kind == "request_resolved" { updateNotificationBadge() }
            reconcileLiveQuestions()
            observeLiveQuestion(event)
            if let notice = SemanticNotice.event(event) { deliverLocalNotice(notice) }
            updateNotificationBadge()
            if event.sessionId == selected {
                if event.kind == "follow_up_queue" { outbox.queue(session: selected, entries: event.followUps ?? []) }
                if ["turn_started", "message_dispatched"].contains(event.kind), let id = event.clientId { outbox.dispatched(session: selected, clientId: id) }
                if let activity = event.activity { outbox.materialize(session: selected, activity: activity) }
                chat.apply(event)
            }
        case "result":
            guard let result = message.result else { return }; commands.remove(result.id)
            if let clientID = queueSteerCommands.removeValue(forKey: result.id) { outbox.queueSteerResult(clientID, result: result) }
            outbox.result(result)
            if let page = catalogueCommands.removeValue(forKey: result.id) {
                catalogueLoading.remove(page.machine)
                guard machines[page.machine]?.freshness?.epoch == page.epoch else { return }
                if result.ok, result.machineId == page.machine {
                    catalogue.apply(machine: page.machine, page: result.sessions ?? [], cursor: result.catalogueCursor)
                    catalogueErrors[page.machine] = nil
                } else { catalogueErrors[page.machine] = result.error ?? String(localized: "History unavailable.", bundle: relayLocalizationBundle) }
                resolveNavigation()
                return
            }
            if let identity = requestCommands.removeValue(forKey: result.id) {
                if result.ok { requestProgress[identity] = String(localized: "Response sent · waiting for Codex", bundle: relayLocalizationBundle) }
                else {
                    requestProgress[identity] = result.errorCode == "UNKNOWN_OUTCOME" ? String(localized: "Check outcome in Codex", bundle: relayLocalizationBundle) : nil
                    requestErrors[identity] = result.error ?? String(localized: "Response failed.", bundle: relayLocalizationBundle)
                }
            }
            var handledHistory = false
            if result.sessionId == selected {
                // New Hubs echo the watch's history ID. Legacy Hubs return an
                // uncorrelated first page, accepted only during watch hydration.
                let historyReply = result.id == historyRequestID || (!historyCorrelated && restoredWatch && historyLoading && result.history != nil && !issuedHistoryIDs.contains(result.id))
                if historyReply {
                    handledHistory = true
                    if result.id == historyRequestID { historyCorrelated = true }
                    historyLoading = false; historyRequestID = nil
                    if result.ok {
                        for activity in result.history ?? [] { outbox.materialize(session: selected, activity: activity) }
                        chat.mergeHistory(result.history ?? [])
                        historyCursor = result.historyCursor
                        historyError = nil
                    } else {
                        chat.endHistory()
                        historyError = result.errorCode == "MACHINE_OFFLINE" ? String(localized: "History is available when Relay reconnects to the machine.", bundle: relayLocalizationBundle) : result.error ?? String(localized: "History unavailable.", bundle: relayLocalizationBundle)
                        if result.errorCode == "MACHINE_OFFLINE" { restoredWatch = false }
                    }
                }
                if let entries = result.followUps { outbox.queue(session: selected, entries: entries) }
            }
            if let waiter = queueWaiters.removeValue(forKey: result.id) {
                queueEditError = result.ok ? nil : result.error ?? String(localized: "Edit failed. Your text is retained.", bundle: relayLocalizationBundle)
                waiter.resume(returning: result.ok)
            } else if !result.ok && !handledHistory { error = result.error ?? String(localized: "Command rejected.", bundle: relayLocalizationBundle) }
        default: break
        }
    }
    func loadCatalogue(machine: String) async {
        guard online, machines[machine]?.status == "ONLINE", !catalogueLoading.contains(machine), !catalogue.completed.contains(machine) else { return }
        let id = UUID().uuidString
        catalogueLoading.insert(machine); catalogueErrors[machine] = nil
        catalogueCommands[id] = (machine, machines[machine]?.freshness?.epoch)
        let sent = await sendCommand(["id": id, "kind": "catalogue", "machine_id": machine, "session_id": "", "catalogue_cursor": catalogue.cursors[machine] ?? ""])
        if !sent {
            catalogueCommands.removeValue(forKey: id); catalogueLoading.remove(machine)
            catalogueErrors[machine] = String(localized: "Hub not connected. Try again when it is online.", bundle: relayLocalizationBundle)
        }
    }
    private func watchSelected() async {
        guard !selected.isEmpty, online else { return }
        guard let current, machines[current.machineId]?.status == "ONLINE" else {
            historyLoading = false; restoredWatch = false
            historyError = String(localized: "History will load when Relay connects to the machine.", bundle: relayLocalizationBundle)
            return
        }
        let id = UUID().uuidString
        issuedHistoryIDs.append(id); if issuedHistoryIDs.count > 128 { issuedHistoryIDs.removeFirst() }
        historyRequestID = id; historyLoading = true; historyError = nil; chat.beginHistory()
        restoredWatch = await send(["type": "watch", "session_id": selected, "history_request_id": id])
        if !restoredWatch { historyLoading = false; historyRequestID = nil }
    }
    func loadOlderHistory() async {
        guard !previewOnly, !historyLoading, !chat.atCapacity, let cursor = historyCursor, !cursor.isEmpty,
              let current, online, machines[current.machineId]?.status == "ONLINE" else { return }
        let id = UUID().uuidString
        issuedHistoryIDs.append(id); if issuedHistoryIDs.count > 128 { issuedHistoryIDs.removeFirst() }
        historyRequestID = id; historyLoading = true; historyError = nil; chat.beginHistory()
        if !(await sendCommand(["id": id, "kind": "history", "session_id": selected, "history_cursor": cursor])) {
            historyLoading = false; historyRequestID = nil; historyError = String(localized: "Connection lost. Try again.", bundle: relayLocalizationBundle)
        }
    }
    func machineConnectionLabel(_ id: String) -> String {
        guard let machine = machines[id] else { return String(localized: "Machine state unavailable", bundle: relayLocalizationBundle) }
        let access = registry?.machines.first(where: { $0.id == id })?.access
        return machine.connectionLabel(hubConnected: online, access: access)
    }
    func navigate(_ destination: RelayDestination) {
        pendingNavigation.receive(destination)
        resolveNavigation()
    }
    private func resolveNavigation() {
        guard credential != nil, online, let target = pendingNavigation.target else { return }
        switch target {
        case .fleet:
            _ = pendingNavigation.take(authenticated: true, snapshotReady: true)
            closeDetail(); returnToFleet += 1; routedMachine = nil; navigationStatus = nil
        case .machine(let id):
            _ = pendingNavigation.take(authenticated: true, snapshotReady: true)
            closeDetail(); routedMachine = machines[id] == nil ? nil : id
            navigationStatus = machines[id] == nil ? String(localized: "This machine is no longer enrolled in this Relay.", bundle: relayLocalizationBundle) : nil
        case .session(let id):
            if fleetSessions[id] != nil {
                _ = pendingNavigation.take(authenticated: true, snapshotReady: true)
                navigationStatus = nil; routedMachine = nil; open(id)
            } else if let machine = RelayDestination.machineID(in: id), machines[machine] != nil {
                guard machines[machine]?.status == "ONLINE" else {
                    routedMachine = machine
                    navigationStatus = String(localized: "The session will open when its machine reconnects. Its notification contains no actionable request.", bundle: relayLocalizationBundle)
                    return
                }
                if catalogue.completed.contains(machine) {
                    _ = pendingNavigation.take(authenticated: true, snapshotReady: true)
                    navigationStatus = String(localized: "This session is no longer available in the machine’s history.", bundle: relayLocalizationBundle)
                } else if let error = catalogueErrors[machine] { navigationStatus = error }
                else {
                    navigationStatus = String(localized: "Finding this session in Codex history…", bundle: relayLocalizationBundle)
                    navigationTask?.cancel()
                    navigationTask = Task { await loadCatalogue(machine: machine) }
                }
            } else {
                _ = pendingNavigation.take(authenticated: true, snapshotReady: true)
                navigationStatus = String(localized: "This notification’s machine is no longer enrolled in this Relay.", bundle: relayLocalizationBundle)
            }
        }
    }
    func open(_ id: String) {
        guard id != selected else { return }
        selected = id; chat = RecentChat(); historyCursor = nil; historyError = nil; historyLoading = false
        restoredWatch = false; outbox.prune(active: id); Task { await watchSelected() }
    }
    func closeDetail() {
        selected = ""; chat = RecentChat(); historyCursor = nil; historyRequestID = nil; historyLoading = false; restoredWatch = false
        Task { await send(["type": "watch", "session_id": ""]) }
    }
    @discardableResult func submit(_ text: String, images: [ImageInput] = [], kind: String? = nil, expectedTurn: String? = nil) async -> Bool {
        guard let session = current, online, machines[session.machineId]?.status == "ONLINE", session.allows(kind ?? session.defaultCommand), (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty), images.isEmpty || session.capabilities.canSendImages == true else { error = String(localized: "Control unavailable for this session.", bundle: relayLocalizationBundle); return false }
        let kind = kind ?? session.defaultCommand
        let targetTurn = kind == "steer" ? (expectedTurn ?? session.turnId) : nil
        if kind == "steer", targetTurn != session.turnId {
            error = String(localized: "The turn changed. Your text is retained: choose Steer again or send it as a follow-up.", bundle: relayLocalizationBundle)
            return false
        }
        do {
            let id = try outbox.add(session: selected, kind: kind, text: text, images: images, expectedTurn: targetTurn); outbox.sending(id)
            var command: [String: Any] = ["id": id, "kind": kind, "session_id": selected, "text": text]
            if !images.isEmpty { command["images"] = images.map { ["media_type": $0.mediaType, "data": $0.data.base64EncodedString()] } }
            if kind == "steer" { command["turn_id"] = targetTurn }
            if !(await sendCommand(command)) { outbox.fail(id, code: "UNKNOWN_OUTCOME", message: String(localized: "Unknown outcome. Check Codex before resending.", bundle: relayLocalizationBundle)) }
            liveQuestions.clear(session: session.id); updateNotificationBadge()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func editQueued(_ item: Outgoing, text: String) async -> Bool {
        guard queueEditingID == nil, queueSteeringID == nil, let current, current.id == item.sessionId, online,
              machines[current.machineId]?.status == "ONLINE", current.allows("queue_update"),
              let present = outbox.items.first(where: { $0.id == item.id }), present.phase == .queued,
              present.queueId == item.queueId, present.queueRevision == item.queueRevision,
              item.queueEditable, let queueID = item.queueId, let revision = item.queueRevision,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 16384 else {
            queueEditError = String(localized: "This message is no longer editable in the queue. Your text stays in the composer.", bundle: relayLocalizationBundle)
            return false
        }
        guard outbox.items.filter({ $0.phase != .materialized && $0.id != item.id }).reduce(text.utf8.count, { $0 + $1.text.utf8.count }) <= 131072 else {
            queueEditError = String(localized: "The local queue is full. Shorten your text before saving.", bundle: relayLocalizationBundle)
            return false
        }
        queueEditingID = item.id; queueEditError = nil
        defer { queueEditingID = nil }
        let id = UUID().uuidString
        return await withCheckedContinuation { continuation in
            queueWaiters[id] = continuation
            Task {
                let sent = await sendCommand(["id": id, "kind": "queue_update", "session_id": item.sessionId, "queue_id": queueID, "queue_client_id": item.id, "queue_revision": revision, "text": text])
                if !sent { finishQueueEditUnknown(id) }
                else {
                    try? await Task.sleep(for: .seconds(35))
                    finishQueueEditUnknown(id)
                }
            }
        }
    }
    func steerQueued(_ item: Outgoing, expectedTurn: String) async -> Bool {
        guard queueSteeringID == nil, queueEditingID == nil, let current, current.id == item.sessionId,
              online, machines[current.machineId]?.status == "ONLINE", current.fresh != false,
              current.allows("queue_steer"), current.turnId == expectedTurn,
              let present = outbox.items.first(where: { $0.id == item.id }), present.phase == .queued,
              present.queueId == item.queueId, present.queueRevision == item.queueRevision,
              let queueID = item.queueId, let revision = item.queueRevision else { return false }
        queueSteeringID = item.id; queueEditError = nil
        defer { queueSteeringID = nil }
        let id = UUID().uuidString
        queueSteerCommands[id] = item.id; outbox.beginQueueSteer(item.id, turn: expectedTurn)
        return await withCheckedContinuation { continuation in
            queueWaiters[id] = continuation
            Task {
                let sent = await sendCommand(["id": id, "kind": "queue_steer", "session_id": item.sessionId,
                    "queue_id": queueID, "queue_client_id": item.id, "queue_revision": revision, "turn_id": expectedTurn])
                if !sent { finishQueueEditUnknown(id) }
                else { try? await Task.sleep(for: .seconds(35)); finishQueueEditUnknown(id) }
            }
        }
    }
    private func finishQueueEditUnknown(_ id: String) {
        guard let waiter = queueWaiters.removeValue(forKey: id) else { return }
        if let clientID = queueSteerCommands.removeValue(forKey: id) { outbox.queueSteerUnknown(clientID) }
        queueEditError = String(localized: "Unknown outcome. Check the Codex queue before retrying; your text is retained.", bundle: relayLocalizationBundle)
        waiter.resume(returning: false)
    }

    func retry(_ item: Outgoing, as kind: String? = nil) async {
        guard item.sessionId == selected else { return }
        let kind = kind ?? item.kind
        if await submit(item.text, images: item.images, kind: kind, expectedTurn: kind == "steer" ? item.expectedTurn : nil) { outbox.discard(item.id) }
    }
    func action(_ kind: String, expectedTurn: String? = nil) async {
        guard let current, online, machines[current.machineId]?.status == "ONLINE", kind == "attach" ? current.readOnly : current.allows(kind) else { error = String(localized: "Control unavailable for this session.", bundle: relayLocalizationBundle); return }
        _ = await sendCommand(["id": UUID().uuidString, "kind": kind, "session_id": current.id, "turn_id": expectedTurn ?? current.turnId ?? ""])
    }
    func answer(_ request: PendingRequest, decision: String? = nil, answers: [String: [String]]? = nil, content: JSONValue? = nil) async {
        guard requests[request.id]?.presentationID == request.presentationID, requestProgress[request.presentationID] == nil, request.sessionId == selected, online, machines[request.machineId]?.status == "ONLINE", current?.capabilities.canAnswer == true else { error = String(localized: "The request changed.", bundle: relayLocalizationBundle); return }
        let commandID = UUID().uuidString
        requestProgress[request.presentationID] = String(localized: "Sending response…", bundle: relayLocalizationBundle)
        requestErrors[request.presentationID] = nil
        requestCommands[commandID] = request.presentationID
        var command: [String: Any] = ["id": commandID, "kind": "answer", "session_id": request.sessionId, "request_id": request.id]
        if let decision { command["decision"] = decision }; if let answers { command["answers"] = answers }
        if let content { command["content"] = content.foundation }
        if !(await sendCommand(command)) {
            requestCommands.removeValue(forKey: commandID)
            requestProgress[request.presentationID] = String(localized: "Check outcome in Codex", bundle: relayLocalizationBundle)
            requestErrors[request.presentationID] = String(localized: "Connection lost while sending. Check the request before retrying.", bundle: relayLocalizationBundle)
        }
    }
    private func sendCommand(_ command: [String: Any]) async -> Bool {
        guard commands.count < 128, let id = command["id"] as? String else { error = String(localized: "Too many active requests.", bundle: relayLocalizationBundle); return false }
        commands.insert(id); let sent = await send(["type": "command", "command": command]); if !sent { commands.remove(id) }; return sent
    }
    private func send(_ message: [String: Any]) async -> Bool {
        guard let socket, online else { return false }
        do { let data = try JSONSerialization.data(withJSONObject: message); try await socket.send(.data(data)); return true } catch { self.error = String(localized: "Connection lost.", bundle: relayLocalizationBundle); return false }
    }
    func loadDevices() async {
        guard let api else { return }
        let identity = credential?.id
        do { let value: DeviceRegistry = try await api.fetch("api/devices"); guard credential?.id == identity else { return }; registry = value; settingsErrors["devices"] = nil }
        catch { if credential?.id == identity { settingsErrors["devices"] = error.localizedDescription } }
    }
    func loadDiagnostics() async {
        guard let api, settingsProgress["diagnostics"] == nil else { return }
        settingsProgress["diagnostics"] = String(localized: "Refreshing…", bundle: relayLocalizationBundle)
        defer { settingsProgress["diagnostics"] = nil }
        let identity = credential?.id
        do {
            let value: RelayDiagnostics = try await api.fetch("api/diagnostics")
            guard credential?.id == identity else { return }
            diagnostics = value; diagnosticsUpdatedAt = Date(); settingsErrors["diagnostics"] = nil
        } catch { if credential?.id == identity { settingsErrors["diagnostics"] = error.localizedDescription } }
    }
    func removeController(_ id: String) async {
        guard let api, settingsProgress[id] == nil else { return }
        settingsProgress[id] = String(localized: "Removing controller…", bundle: relayLocalizationBundle); settingsErrors[id] = nil
        defer { settingsProgress[id] = nil }
        do {
            let _: Ack = try await api.fetch("api/devices/\(id)/remove", body: [:])
            if id == credential?.id { forget() } else { await loadDevices() }
        } catch { settingsErrors[id] = error.localizedDescription }
    }
    func loadAccounts() async {
        guard let api else { return }
        let identity = credential?.id
        do { let registry: AccountRegistry = try await api.fetch("api/accounts"); guard credential?.id == identity else { return }; accounts = registry.accounts; settingsErrors["accounts"] = nil }
        catch { if credential?.id == identity { settingsErrors["accounts"] = error.localizedDescription } }
    }
    func createCode(kind: String, name: String, machine: String = "") async {
        guard let api, settingsProgress["pairing"] == nil else { return }
        settingsProgress["pairing"] = String(localized: "Creating code…", bundle: relayLocalizationBundle); settingsErrors["pairing"] = nil
        defer { settingsProgress["pairing"] = nil }
        let identity = credential?.id
        do { let value: PairCode = try await api.fetch("api/pairing/code", body: ["kind": kind, "name": name, "machine": machine]); guard credential?.id == identity else { return }; pairCode = value }
        catch { if credential?.id == identity { settingsErrors["pairing"] = error.localizedDescription } }
    }
    func manageMachine(_ id: String, action: String) async {
        guard let api, settingsProgress[id] == nil else { return }
        settingsProgress[id] = action == "resume" ? String(localized: "Resuming connection…", bundle: relayLocalizationBundle) : action == "pause" ? String(localized: "Pausing connection…", bundle: relayLocalizationBundle) : String(localized: "Removing…", bundle: relayLocalizationBundle)
        settingsErrors[id] = nil; defer { settingsProgress[id] = nil }
        do { let _: Ack = try await api.fetch("api/machines/\(id)/\(action)", body: [:]); await loadDevices() }
        catch { settingsErrors[id] = error.localizedDescription }
    }
    func revokeDevice(_ id: String) async {
        guard let api, settingsProgress[id] == nil else { return }
        settingsProgress[id] = String(localized: "Revoking…", bundle: relayLocalizationBundle); settingsErrors[id] = nil; defer { settingsProgress[id] = nil }
        do { let _: Ack = try await api.fetch("api/devices/\(id)/revoke", body: [:]); if id == credential?.id { forget() } else { await loadDevices() } }
        catch { settingsErrors[id] = error.localizedDescription }
    }
    func logout() async {
        guard let api, settingsProgress["logout"] == nil else { return }
        settingsProgress["logout"] = String(localized: "Revoking this access…", bundle: relayLocalizationBundle); settingsErrors["logout"] = nil
        defer { settingsProgress["logout"] = nil }
        do { let _: Ack = try await api.fetch("api/logout", body: [:]); forget() }
        catch { settingsErrors["logout"] = String(localized: "Access not revoked. ", bundle: relayLocalizationBundle) + error.localizedDescription }
    }
    func forget(preserveNavigation: Bool = false) { guard !previewOnly else { return }; stop(); if !preserveNavigation { pendingNavigation = PendingNavigation() }; navigationTask?.cancel(); routedMachine = nil; CredentialVault.clear(); credential = nil; pushRegistered = false; pushRegistrationVerifiedAt = nil; settingsErrors = [:]; machines = [:]; sessions = [:]; catalogue = SessionCatalogue(); catalogueErrors = [:]; liveActivities = [:]; requests = [:]; registry = nil; accounts = []; diagnostics = nil; diagnosticsUpdatedAt = nil; pairCode = nil; selected = ""; chat = RecentChat(); outbox = Outbox(); connection = String(localized: "Sign-in required", bundle: relayLocalizationBundle); updateNotificationBadge() }
    func background() { guard !previewOnly else { return }; traceConnection("background"); paused = true; lastBackground = Date(); stop() }
    func foreground() { guard !previewOnly else { return }; traceConnection("foreground paused=\(paused)"); guard paused || loop == nil else { return }; paused = false; outbox.prune(active: ""); if let lastBackground, Date().timeIntervalSince(lastBackground) > 300 { outbox = Outbox(); chat = RecentChat(); historyCursor = nil }; connect() }
    var attentionCount: Int { requests.count + liveQuestions.records.count }
    private func observeLiveQuestion(_ event: RelayEvent) {
        let session = sessions[event.sessionId]
        liveQuestions.observe(event, activeTurn: session?.turnId, current: online && session?.fresh != false && session?.status == "WORKING" && machines[session?.machineId ?? ""]?.status == "ONLINE")
    }
    private func reconcileLiveQuestions() {
        liveQuestions.reconcile(sessions: sessions, machines: machines, connected: online)
    }
    private func stop() { liveQuestions.reset(); cancelOfflineNotices(); updateNotificationBadge(); for id in Array(queueWaiters.keys) { finishQueueEditUnknown(id) }; chat.endHistory(); restoredWatch = false; historyLoading = false; historyRequestID = nil; generation = UUID(); loop?.cancel(); loop = nil; socket?.cancel(with: .goingAway, reason: nil); socket = nil; socketHealth = nil; transport?.invalidateAndCancel(); transport = nil; online = false; commands.removeAll(); catalogueCommands.removeAll(); catalogueLoading.removeAll(); outbox.disconnected() }
}
private struct AckBootstrap: Decodable, Sendable { let version: Int; let secure: Bool; let nativePush: Bool? }
