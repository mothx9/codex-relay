import Foundation
public enum DeliveryPhase: String, Sendable { case local = "LOCAL", sending = "SENDING", queued = "QUEUED", dispatched = "DISPATCHED", materialized = "MATERIALIZED", accepted = "ACCEPTED", steering = "STEERING", applied = "APPLIED", failed = "FAILED" }
public struct Outgoing: Identifiable, Sendable {
    public let id: String; public let sessionId: String; public let kind: String; public var text: String; public var phase: DeliveryPhase = .local
    public var error: String?; public var errorCode: String?; public let expectedTurn: String?; public let created: Date
}
public struct Outbox: Sendable {
    public private(set) var items: [Outgoing] = []
    public init() {}
    public mutating func add(id: String = UUID().uuidString, session: String, kind: String, text: String, expectedTurn: String? = nil, now: Date = Date()) throws -> String {
        if items.contains(where: { $0.id == id }) { return id }
        let pending = items.filter { $0.phase != .materialized }
        guard text.utf8.count <= 16384, pending.count < 32, pending.reduce(text.utf8.count, { $0 + $1.text.utf8.count }) <= 131072 else { throw HubFailure.message("Outbox pieno o messaggio troppo lungo.") }
        items.append(Outgoing(id: id, sessionId: session, kind: kind, text: text, expectedTurn: expectedTurn, created: now))
        while items.count > 128, let i = items.firstIndex(where: { $0.phase == .materialized }) { items.remove(at: i) }
        return id
    }
    public mutating func sending(_ id: String) { update(id) { $0.phase = $0.kind == "steer" ? .steering : .sending } }
    public mutating func result(_ result: CommandResult) {
        update(result.id) {
            if [.materialized, .dispatched].contains($0.phase) || ($0.phase == .queued && !result.ok) { return }
            $0.phase = result.ok ? ($0.kind == "follow_up" ? .queued : $0.kind == "steer" ? .applied : .accepted) : .failed
            $0.error = result.error; $0.errorCode = result.errorCode
        }
    }
    public mutating func fail(_ id: String, code: String, message: String) { update(id) { $0.phase = .failed; $0.errorCode = code; $0.error = message } }
    public mutating func disconnected() {
        for index in items.indices where [.sending, .steering].contains(items[index].phase) {
            items[index].phase = .failed; items[index].errorCode = "UNKNOWN_OUTCOME"; items[index].error = "Esito sconosciuto. Verifica Codex prima di reinviare."
        }
    }
    public mutating func dispatched(session: String, clientId: String) { update(clientId) { if $0.sessionId == session && $0.phase != .materialized { $0.phase = .dispatched } } }
    public mutating func materialize(session: String, activity: Activity) {
        guard activity.kind == "userMessage", let id = activity.clientId else { return }
        update(id) { if $0.sessionId == session { $0.phase = .materialized; $0.text = ""; $0.error = nil; $0.errorCode = nil } }
    }
    public mutating func queue(session: String, entries: [FollowUp]) {
        for entry in entries {
            guard let text = entry.text, !text.isEmpty else { continue }
            if !items.contains(where: { $0.id == entry.clientId }) { _ = try? add(id: entry.clientId, session: session, kind: "follow_up", text: text) }
            update(entry.clientId) { if $0.sessionId == session && ![.materialized, .dispatched].contains($0.phase) { $0.phase = .queued; $0.error = nil; $0.errorCode = nil } }
        }
    }
    public func visible(session: String) -> [Outgoing] { items.filter { $0.sessionId == session && $0.phase != .materialized } }
    public mutating func discard(_ id: String) { items.removeAll { $0.id == id } }
    public mutating func prune(active: String, now: Date = Date()) { items.removeAll { $0.sessionId != active && now.timeIntervalSince($0.created) > 300 } }
    private mutating func update(_ id: String, _ action: (inout Outgoing) -> Void) { if let index = items.firstIndex(where: { $0.id == id }) { action(&items[index]) } }
}
/// Ephemeral, selected-session memory. Canonical history is paged from Codex;
/// Relay never writes this window to disk. The Hub retains its smaller buffer.
public struct RecentChat: Sendable {
    public static let maxItems = 2048
    public static let maxBytes = 8 * 1024 * 1024
    public private(set) var items: [Activity] = []
    public private(set) var trimmed = false
    private var changedDuringHistory: Set<String> = []
    private var readingHistory = false
    public init() {}
    public var atCapacity: Bool { items.count >= Self.maxItems - 40 || items.reduce(0) { $0 + $1.contextBytes } >= Self.maxBytes - 40 * 16384 }
    public mutating func beginHistory() { changedDuringHistory.removeAll(keepingCapacity: true); readingHistory = true }
    public mutating func endHistory() { readingHistory = false; changedDuringHistory.removeAll(keepingCapacity: true) }
    public mutating func put(_ activity: Activity) {
        var a = activity; a.text = String(a.text.prefix(16384))
        if let i = items.firstIndex(where: { $0.id == a.id || (a.clientId != nil && $0.clientId == a.clientId) }) { items[i] = a } else { items.append(a) }
        trim()
    }
    /// Prepend missing canonical items while preserving any newer live version.
    /// Exact IDs, never text matching, reconcile history, deltas and the outbox.
    public mutating func mergeHistory(_ history: [Activity]) {
        func same(_ a: Activity, _ b: Activity) -> Bool { a.id == b.id || (a.clientId != nil && a.clientId == b.clientId) }
        for (position, item) in history.enumerated() {
            if let i = items.firstIndex(where: { same($0, item) }) {
                if !changedDuringHistory.contains(items[i].id) { items[i] = item }
            } else if let next = history.dropFirst(position + 1).first(where: { entry in items.contains { same($0, entry) } }),
                      let index = items.firstIndex(where: { same($0, next) }) {
                items.insert(item, at: index)
            } else if position > 0, let previous = items.firstIndex(where: { same($0, history[position - 1]) }) {
                items.insert(item, at: previous + 1)
            } else {
                items.insert(item, at: 0)
            }
        }
        endHistory()
        trim()
    }
    private mutating func trim() {
        var bytes = items.reduce(0) { $0 + $1.contextBytes }
        while items.count > Self.maxItems || bytes > Self.maxBytes {
            bytes -= items.removeFirst().contextBytes; trimmed = true
        }
    }
    public mutating func apply(_ event: RelayEvent) {
        if let activity = event.activity { if readingHistory { changedDuringHistory.insert(activity.id) }; put(activity); return }
        guard ["delta", "command_output", "diff"].contains(event.kind) else { return }
        let id = event.itemId ?? "\(event.turnId ?? "")/\(event.kind)"
        if readingHistory { changedDuringHistory.insert(id) }
        var item = items.first { $0.id == id } ?? Activity(id: id, kind: event.kind == "delta" ? "agentMessage" : event.kind, text: "", timestamp: event.timestamp)
        item.text = (event.kind == "diff" ? "" : item.text) + (event.text ?? "")
        put(item)
    }
}
