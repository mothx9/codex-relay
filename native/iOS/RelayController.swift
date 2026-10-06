import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor final class RelayController: ObservableObject {
    @Published var credential: Credential?
    @Published var machines: [String: Machine] = [:]
    @Published var sessions: [String: RelaySession] = [:]
    @Published var requests: [String: PendingRequest] = [:]
    @Published var chat = RecentChat()
    @Published var outbox = Outbox()
    @Published var selected: String = ""
    @Published var online = false
    @Published var connection = "Accesso richiesto"
    @Published var error: String?
    @Published var registry: DeviceRegistry?
    @Published var pairCode: PairCode?
    @Published var busy = false
    @Published var nativePushAvailable = false
    @Published var notificationStatus = "Notifiche non abilitate"
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
                    self.online = false; self.outbox.disconnected(); self.commands.removeAll(); self.socket?.cancel(with: .goingAway, reason: nil); self.transport?.invalidateAndCancel()
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
            machines = Dictionary(uniqueKeysWithValues: snapshot.machines.map { ($0.id, $0) }); sessions = Dictionary(uniqueKeysWithValues: snapshot.sessions.map { ($0.id, $0) })
            requests = Dictionary(uniqueKeysWithValues: snapshot.requests.map { ($0.id, $0) }); online = true; connection = "Live · \(machines.values.filter { $0.status == "ONLINE" }.count) macchine"
            if !selected.isEmpty { _ = await send(["type": "watch", "session_id": selected]) }
            await loadDevices()
        case "devices_changed": await loadDevices()
        case "event", "pending":
            guard let event = message.event else { return }
            if let id = event.eventId, !id.isEmpty { if seen.contains(id) { return }; seen.append(id); if seen.count > 1024 { seen.removeFirst(seen.count - 1024) } }
            if let session = event.session { sessions[session.id] = session }
            if let request = event.request { requests[request.id] = request }
            if event.kind == "request_resolved", let id = event.requestId { requests.removeValue(forKey: id) }
            if event.sessionId == selected {
                if event.kind == "follow_up_queue" { outbox.queue(session: selected, entries: event.followUps ?? []) }
                if ["turn_started", "message_dispatched"].contains(event.kind), let id = event.clientId { outbox.dispatched(session: selected, clientId: id) }
                if let activity = event.activity { outbox.materialize(session: selected, activity: activity) }
                chat.apply(event)
            }
        case "result":
            guard let result = message.result else { return }; commands.remove(result.id); outbox.result(result)
            if result.sessionId == selected {
                for activity in result.history ?? [] { outbox.materialize(session: selected, activity: activity); chat.put(activity) }
                outbox.queue(session: selected, entries: result.followUps ?? [])
            }
            if !result.ok { error = result.error ?? "Comando rifiutato." }
        default: break
        }
    }
    func open(_ id: String) { selected = id; chat = RecentChat(); outbox.prune(active: id); Task { await send(["type": "watch", "session_id": id]) } }
    func closeDetail() { selected = ""; chat = RecentChat(); Task { await send(["type": "watch", "session_id": ""]) } }
    @discardableResult func submit(_ text: String, kind: String? = nil, expectedTurn: String? = nil) async -> Bool {
        guard let session = current, online, machines[session.machineId]?.status == "ONLINE", session.allows(kind ?? session.defaultCommand), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Controllo non disponibile per questa sessione."; return false }
        let kind = kind ?? session.defaultCommand
        let targetTurn = kind == "steer" ? (expectedTurn ?? session.turnId) : nil
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
        guard requests[request.id] != nil, request.sessionId == selected, online, machines[request.machineId]?.status == "ONLINE", current?.capabilities.canAnswer == true else { error = "La richiesta è cambiata."; return }
        var command: [String: Any] = ["id": UUID().uuidString, "kind": "answer", "session_id": request.sessionId, "request_id": request.id]
        if let decision { command["decision"] = decision }; if let answers { command["answers"] = answers }
        if let content { command["content"] = content.foundation }
        _ = await sendCommand(command)
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
    func forget() { guard !previewOnly else { return }; stop(); CredentialVault.clear(); credential = nil; machines = [:]; sessions = [:]; requests = [:]; registry = nil; pairCode = nil; selected = ""; chat = RecentChat(); outbox = Outbox(); connection = "Accesso richiesto" }
    func background() { paused = true; lastBackground = Date(); stop(); chat = RecentChat() }
    func foreground() { paused = false; outbox.prune(active: ""); if let lastBackground, Date().timeIntervalSince(lastBackground) > 300 { outbox = Outbox() }; connect() }
    private func stop() { generation = UUID(); loop?.cancel(); loop = nil; socket?.cancel(with: .goingAway, reason: nil); socket = nil; transport?.invalidateAndCancel(); transport = nil; online = false; commands.removeAll(); outbox.disconnected() }
}
private struct AckBootstrap: Decodable, Sendable { let version: Int; let secure: Bool; let nativePush: Bool? }
