import Foundation

/// A presentation of the bounded transcript. Group adjacent tool items without
/// reordering messages or inferring tool success from a turn/command ACK.
public struct TranscriptGroup: Identifiable, Sendable {
    public enum Kind: String, Sendable { case message, terminal, mcp, changes, activity }
    public var items: [Activity]
    public var kind: Kind {
        let kinds = Set(items.map { Self.kind($0).rawValue })
        return kinds.count == 1 ? Self.kind(items[0]) : .activity
    }
    // The first operation anchors identity even when subsequent kinds differ.
    public var id: String { (items.first.map { Self.kind($0).rawValue } ?? "activity") + "." + (items.first?.id ?? "") }
    private static func kind(_ activity: Activity) -> Kind {
        switch activity.kind {
        case "userMessage", "agentMessage", "delta": .message
        case "commandExecution", "command_output": .terminal
        case "mcpToolCall": .mcp
        case "fileChange", "diff": .changes
        default: .activity
        }
    }
    public var commandCount: Int { items.filter { Self.kind($0) == .terminal }.count }
    public var toolCount: Int { items.filter { Self.kind($0) == .mcp }.count }
    public var changedPaths: [String] { ChangeOverview.paths(items) }
    public static func make(_ activities: [Activity]) -> [TranscriptGroup] {
        var groups: [TranscriptGroup] = []
        for activity in activities {
            if kind(activity) != .message, let prior = groups.last, prior.kind != .message,
               prior.items.last?.turnId == activity.turnId {
                groups[groups.count - 1].items.append(activity)
            } else { groups.append(TranscriptGroup(items: [activity])) }
        }
        return groups
    }
}

/// Reader intent is independent of content growth and scroll geometry.
/// Only a completed user scroll at the bottom or an explicit jump resumes follow.
public struct TranscriptScrollPolicy: Equatable, Sendable {
    public private(set) var followsLatest = true
    public private(set) var isInteracting = false
    public var shouldFollow: Bool { followsLatest && !isInteracting }
    public init() {}
    public mutating func beginInteraction() { isInteracting = true; followsLatest = false }
    public mutating func endInteraction(distanceFromBottom: Double?) {
        isInteracting = false
        followsLatest = distanceFromBottom.map { $0 <= 12 } ?? false
    }
    public mutating func readHistory() { followsLatest = false }
    public mutating func jumpToLatest() { followsLatest = true }
}

/// A live-stream presentation hint, never a pending request or persisted state.
/// History results do not enter this reducer. Losing the stream loses the hint.
public struct LiveQuestion: Identifiable, Equatable, Sendable {
    public let sessionID: String
    public let machineID: String
    public let turnID: String
    public let epoch: String?
    public let activity: Activity
    public let observedAt: Date
    public var id: String { sessionID + "/live_question/" + turnID + "/" + activity.id }
}
public struct LiveQuestions: Equatable, Sendable {
    public private(set) var records: [LiveQuestion] = []
    private var retired: [String] = []
    public var itemIDs: [String] { records.map { $0.activity.id } }
    public init() {}
    private mutating func retire(_ removed: [LiveQuestion]) {
        retired.append(contentsOf: removed.map(\.id)); if retired.count > 256 { retired.removeFirst(retired.count - 256) }
    }
    public mutating func reset() { retire(records); records.removeAll() }
    public mutating func clear(session: String) {
        retire(records.filter { $0.sessionID == session }); records.removeAll { $0.sessionID == session }
    }
    public mutating func reconcile(activeTurn: String?, current: Bool) {
        if !current || records.contains(where: { $0.turnID != activeTurn }) { reset() }
    }
    public mutating func reconcile(sessions: [String: RelaySession], machines: [String: Machine], connected: Bool) {
        let obsolete = records.filter { question in
            guard connected, let session = sessions[question.sessionID], let machine = machines[question.machineID] else { return true }
            return machine.status != "ONLINE" || session.fresh == false || !["WORKING", "NEEDS_YOU"].contains(session.status) || session.turnId != question.turnID || (question.epoch != nil && machine.freshness?.epoch != question.epoch)
        }
        retire(obsolete); let ids = Set(obsolete.map(\.id)); records.removeAll { ids.contains($0.id) }
    }
    public mutating func observe(_ event: RelayEvent, activeTurn: String?, current: Bool) {
        if ["turn_started", "turn_completed", "failed", "live_question_cleared"].contains(event.kind) || event.activity?.kind == "userMessage" { clear(session: event.sessionId); return }
        guard current, let activeTurn, !activeTurn.isEmpty, event.turnId == activeTurn,
              ["activity", "live_question"].contains(event.kind), let item = event.activity,
              !item.id.isEmpty, item.kind == "agentMessage", !(item.questions ?? []).isEmpty else { return }
        let value = LiveQuestion(sessionID: event.sessionId, machineID: event.machineId ?? String(event.sessionId.split(separator: "~").first ?? ""), turnID: activeTurn, epoch: event.epoch, activity: item, observedAt: Date())
        guard !retired.contains(value.id) else { return }
        if let index = records.firstIndex(where: { $0.id == value.id }) { records[index] = value }
        else { records.append(value) }
        while records.count > 64 || records.reduce(0, { $0 + $1.activity.contextBytes }) > 256 * 1024 {
            retire([records.removeFirst()])
        }
    }
}
