import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

@MainActor @Observable final class RelayController {
    var credential: Credential?
    var machines: [String: Machine] = [:]
    var sessions: [String: RelaySession] = [:]
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
    var outbox = Outbox()
    var selected: String = ""
    var online = false
    var connection = "Accesso richiesto"
    var error: String?
    var registry: DeviceRegistry?
    var pairCode: PairCode?
    var busy = false
    var nativePushAvailable = false
    var notificationStatus = "Notifiche non abilitate"
    var apnsToken: String?
    private var socket: URLSessionWebSocketTask?
    private var transport: URLSession?
    private var loop: Task<Void, Never>?
    private var generation = UUID()
    private var seen: [String] = []
    private var paused = false
    private var commands: Set<String> = []
    private var lastBackground: Date?
    let previewOnly: Bool

    init(preview: Bool = false) {
        previewOnly = preview || ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        if !previewOnly { credential = CredentialVault.load(); if credential != nil { connect() } }
    }
    var api: HubAPI? { previewOnly ? nil : credential.flatMap { try? HubAPI(url: $0.hubUrl, token: $0.token) } }
    var current: RelaySession? { sessions[selected] }
    func pair(url: String, code: String) async {
        guard !previewOnly else { return }
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let api = try HubAPI(url: url)
            let credential: Credential = try await api.fetch("api/pairing/exchange", body: ["kind": "operator", "code": code])
            guard credential.kind == "operator", credential.token.count >= 32 else { throw HubFailure.message("Abbinamento non valido.") }
            try CredentialVault.save(credential); self.credential = credential; error = nil; connect()
        } catch { self.error = error.localizedDescription }
    }
    func connect() {
        guard !previewOnly else { return }
        stop(); guard let api, !paused else { return }; generation = UUID(); let generation = generation
        loop = Task { [weak self] in
            var attempt = 0
            while !Task.isCancelled {
                guard let self, self.generation == generation else { return }
                do {
                    let bootstrap: AckBootstrap = try await api.fetch("api/bootstrap")
                    self.nativePushAvailable = bootstrap.nativePush ?? false
                    let config = URLSessionConfiguration.ephemeral; config.httpCookieStorage = nil; config.urlCache = nil
                    let transport = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil); self.transport = transport
                    let socket = transport.webSocketTask(with: api.socketRequest()); socket.maximumMessageSize = 1_048_576
                    self.socket = socket; self.connection = "Connessione…"; socket.resume()
                    while !Task.isCancelled {
                        let message = try await socket.receive(); guard self.generation == generation else { return }
                        let data: Data
                        switch message { case .data(let d): data = d; case .string(let s): data = Data(s.utf8); @unknown default: continue }
                        let decoded = try RelayJSON.decoder().decode(WireMessage.self, from: data)
                        await self.apply(decoded); attempt = 0
                    }
                } catch {
                    guard self.generation == generation, !Task.isCancelled else { return }
                    self.online = false; self.restoredWatch = false; self.historyLoading = false; self.historyRequestID = nil; self.outbox.disconnected(); self.commands.removeAll(); self.socket?.cancel(with: .goingAway, reason: nil); self.transport?.invalidateAndCancel()
                    self.connection = "Offline · riconnessione"
                    if let hubError = error as? HubFailure {
                        if hubError.authenticationRequired { self.forget(); self.error = hubError.localizedDescription; return }
                        if !hubError.retryable { self.error = hubError.localizedDescription; self.connection = "Errore del Hub"; return }
                    }
                    let delay = min(60.0, pow(2.0, Double(min(attempt, 6)))) * Double.random(in: 0.5...1.0); attempt += 1
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
        }
    }
    private func apply(_ message: WireMessage) async {
        switch message.type {
        case "snapshot":
            guard let snapshot = message.snapshot else { return }
            liveActivities = snapshot.liveActivities ?? [:]
            machines = Dictionary(uniqueKeysWithValues: snapshot.machines.map { ($0.id, $0) }); sessions = Dictionary(uniqueKeysWithValues: snapshot.sessions.map { ($0.id, $0) })
            requests = Dictionary(uniqueKeysWithValues: snapshot.requests.map { ($0.id, $0.retainingContext(from: requests[$0.id])) }); online = true; connection = "Live · \(machines.values.filter { $0.status == "ONLINE" }.count) macchine"
            let activeRequests = Set(requests.values.map(\.presentationID))
            requestProgress = requestProgress.filter { activeRequests.contains($0.key) }
            requestErrors = requestErrors.filter { activeRequests.contains($0.key) }
            if !selected.isEmpty && !restoredWatch { await watchSelected() }
            Task { await loadDevices() }
        case "devices_changed": Task { await loadDevices() }
        case "event", "pending":
            guard let event = message.event else { return }
            if event.kind == "live_activity" { liveActivities[event.sessionId] = event.liveActivity; return }
            if let id = event.eventId, !id.isEmpty {
                if seen.contains(id) {
                    // The Hub sends a stripped fleet event, then the same event
                    // ID with private form context to this session's watcher.
                    if message.type == "pending", let incoming = event.request,
                       let prior = requests[incoming.id], incoming.presentationID == prior.presentationID {
                        requests[incoming.id] = incoming.retainingContext(from: prior)
                    }
                    return
                }
                seen.append(id); if seen.count > 1024 { seen.removeFirst(seen.count - 1024) }
            }
            if let session = event.session { sessions[session.id] = session }
            if let request = event.request { requests[request.id] = request.retainingContext(from: requests[request.id]) }
            if event.kind == "request_resolved", let id = event.requestId { requests.removeValue(forKey: id) }
            if event.sessionId == selected {
                if event.kind == "follow_up_queue" { outbox.queue(session: selected, entries: event.followUps ?? []) }
                if ["turn_started", "message_dispatched"].contains(event.kind), let id = event.clientId { outbox.dispatched(session: selected, clientId: id) }
                if let activity = event.activity { outbox.materialize(session: selected, activity: activity) }
                chat.apply(event)
            }
        case "result":
            guard let result = message.result else { return }; commands.remove(result.id); outbox.result(result)
            if let identity = requestCommands.removeValue(forKey: result.id) {
                if result.ok { requestProgress[identity] = "Risposta inviata · attendo Codex" }
                else {
                    requestProgress[identity] = result.errorCode == "UNKNOWN_OUTCOME" ? "Esito da verificare in Codex" : nil
                    requestErrors[identity] = result.error ?? "Risposta non riuscita."
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
                        historyError = result.errorCode == "MACHINE_OFFLINE" ? "Cronologia disponibile quando Relay si ricollega alla macchina." : result.error ?? "Cronologia non disponibile."
                        if result.errorCode == "MACHINE_OFFLINE" { restoredWatch = false }
                    }
                }
                outbox.queue(session: selected, entries: result.followUps ?? [])
            }
            if !result.ok && !handledHistory { error = result.error ?? "Comando rifiutato." }
        default: break
        }
    }
    private func watchSelected() async {
        guard !selected.isEmpty, online else { return }
        guard let current, machines[current.machineId]?.status == "ONLINE" else {
            historyLoading = false; restoredWatch = false
            historyError = "La cronologia si caricherà quando Relay sarà collegato alla macchina."
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
            historyLoading = false; historyRequestID = nil; historyError = "Connessione interrotta. Riprova."
        }
    }
    func machineConnectionLabel(_ id: String) -> String {
        guard let machine = machines[id] else { return "Stato macchina non disponibile" }
        let access = registry?.machines.first(where: { $0.id == id })?.access
        return machine.connectionLabel(hubConnected: online, access: access)
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
    @discardableResult func submit(_ text: String, kind: String? = nil, expectedTurn: String? = nil) async -> Bool {
        guard let session = current, online, machines[session.machineId]?.status == "ONLINE", session.allows(kind ?? session.defaultCommand), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Controllo non disponibile per questa sessione."; return false }
        let kind = kind ?? session.defaultCommand
        let targetTurn = kind == "steer" ? (expectedTurn ?? session.turnId) : nil
        if kind == "steer", targetTurn != session.turnId {
            error = "Il turno è cambiato. Il testo è conservato: scegli di nuovo Steer o invialo come follow-up."
            return false
        }
        do {
            let id = try outbox.add(session: selected, kind: kind, text: text, expectedTurn: targetTurn); outbox.sending(id)
            var command: [String: Any] = ["id": id, "kind": kind, "session_id": selected, "text": text]
            if kind == "steer" { command["turn_id"] = targetTurn }
            if !(await sendCommand(command)) { outbox.fail(id, code: "UNKNOWN_OUTCOME", message: "Esito sconosciuto. Verifica Codex prima di reinviare.") }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func retry(_ item: Outgoing, as kind: String? = nil) async {
        guard item.sessionId == selected else { return }
        let kind = kind ?? item.kind
        if await submit(item.text, kind: kind, expectedTurn: kind == "steer" ? item.expectedTurn : nil) { outbox.discard(item.id) }
    }
    func action(_ kind: String, expectedTurn: String? = nil) async {
        guard let current, online, machines[current.machineId]?.status == "ONLINE", kind == "attach" ? current.readOnly : current.allows(kind) else { error = "Controllo non disponibile per questa sessione."; return }
        _ = await sendCommand(["id": UUID().uuidString, "kind": kind, "session_id": current.id, "turn_id": expectedTurn ?? current.turnId ?? ""])
    }
    func answer(_ request: PendingRequest, decision: String? = nil, answers: [String: [String]]? = nil, content: JSONValue? = nil) async {
        guard requests[request.id]?.presentationID == request.presentationID, requestProgress[request.presentationID] == nil, request.sessionId == selected, online, machines[request.machineId]?.status == "ONLINE", current?.capabilities.canAnswer == true else { error = "La richiesta è cambiata."; return }
        let commandID = UUID().uuidString
        requestProgress[request.presentationID] = "Invio della risposta…"
        requestErrors[request.presentationID] = nil
        requestCommands[commandID] = request.presentationID
        var command: [String: Any] = ["id": commandID, "kind": "answer", "session_id": request.sessionId, "request_id": request.id]
        if let decision { command["decision"] = decision }; if let answers { command["answers"] = answers }
        if let content { command["content"] = content.foundation }
        if !(await sendCommand(command)) {
            requestCommands.removeValue(forKey: commandID)
            requestProgress[request.presentationID] = "Esito da verificare in Codex"
            requestErrors[request.presentationID] = "Connessione interrotta durante l’invio. Verifica la richiesta prima di riprovare."
        }
    }
    private func sendCommand(_ command: [String: Any]) async -> Bool {
        guard commands.count < 128, let id = command["id"] as? String else { error = "Troppe richieste in corso."; return false }
        commands.insert(id); let sent = await send(["type": "command", "command": command]); if !sent { commands.remove(id) }; return sent
    }
    private func send(_ message: [String: Any]) async -> Bool {
        guard let socket, online else { return false }
        do { let data = try JSONSerialization.data(withJSONObject: message); try await socket.send(.data(data)); return true } catch { self.error = "Connessione interrotta."; return false }
    }
    func loadDevices() async { guard let api else { return }; do { registry = try await api.fetch("api/devices") } catch { self.error = error.localizedDescription } }
    func createCode(kind: String, name: String, machine: String = "") async {
        guard let api else { return }; do { pairCode = try await api.fetch("api/pairing/code", body: ["kind": kind, "name": name, "machine": machine]) } catch { self.error = error.localizedDescription }
    }
    func manageMachine(_ id: String, action: String) async { guard let api else { return }; do { let _: Ack = try await api.fetch("api/machines/\(id)/\(action)", body: [:]); await loadDevices() } catch { self.error = error.localizedDescription } }
    func revokeDevice(_ id: String) async {
        guard let api else { return }; do { let _: Ack = try await api.fetch("api/devices/\(id)/revoke", body: [:]); if id == credential?.id { forget() } else { await loadDevices() } } catch { self.error = error.localizedDescription }
    }
    func logout() async { if let api { _ = try? await api.fetch("api/logout", body: [:], as: Ack.self) }; forget() }
    func forget() { guard !previewOnly else { return }; stop(); CredentialVault.clear(); credential = nil; machines = [:]; sessions = [:]; liveActivities = [:]; requests = [:]; registry = nil; pairCode = nil; selected = ""; chat = RecentChat(); outbox = Outbox(); connection = "Accesso richiesto" }
    func background() { guard !previewOnly else { return }; paused = true; lastBackground = Date(); stop() }
    func foreground() { guard !previewOnly else { return }; paused = false; outbox.prune(active: ""); if let lastBackground, Date().timeIntervalSince(lastBackground) > 300 { outbox = Outbox(); chat = RecentChat(); historyCursor = nil }; connect() }
    private func stop() { chat.endHistory(); restoredWatch = false; historyLoading = false; historyRequestID = nil; generation = UUID(); loop?.cancel(); loop = nil; socket?.cancel(with: .goingAway, reason: nil); socket = nil; transport?.invalidateAndCancel(); transport = nil; online = false; commands.removeAll(); outbox.disconnected() }
}
private struct AckBootstrap: Decodable, Sendable { let version: Int; let secure: Bool; let nativePush: Bool? }
