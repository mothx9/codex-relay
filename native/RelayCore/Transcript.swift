import Foundation

/// A presentation of the bounded transcript. Group adjacent tool items without
/// reordering messages or inferring tool success from a turn/command ACK.
public struct TranscriptGroup: Identifiable, Sendable {
    public enum Kind: String, Sendable { case message, terminal, mcp, changes, activity }
    public let kind: Kind
    public var items: [Activity]
    public var id: String { kind.rawValue + "." + (items.first?.id ?? "") }

    public static func make(_ activities: [Activity]) -> [TranscriptGroup] {
        var groups: [TranscriptGroup] = []
        for activity in activities {
            let kind: Kind
            switch activity.kind {
            case "userMessage", "agentMessage", "delta": kind = .message
            case "commandExecution", "command_output": kind = .terminal
            case "mcpToolCall": kind = .mcp
            case "fileChange", "diff": kind = .changes
            default: kind = .activity
            }
            if kind != .message, groups.last?.kind == kind {
                groups[groups.count - 1].items.append(activity)
            } else {
                groups.append(TranscriptGroup(kind: kind, items: [activity]))
            }
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
public struct LiveQuestions: Equatable, Sendable {
    public private(set) var itemIDs: [String] = []
    private var turn: String?
    public init() {}
    public mutating func reset() { itemIDs.removeAll(); turn = nil }
    public mutating func reconcile(activeTurn: String?, current: Bool) {
        if !current || activeTurn != turn { reset() }
    }
    public mutating func observe(_ event: RelayEvent, activeTurn: String?, current: Bool) {
        reconcile(activeTurn: activeTurn, current: current)
        guard current, let activeTurn, !activeTurn.isEmpty else { return }
        if ["turn_completed", "failed"].contains(event.kind) || event.activity?.kind == "userMessage" { reset(); return }
        guard event.kind == "activity", event.turnId == activeTurn,
              let item = event.activity, item.kind == "agentMessage", !(item.questions ?? []).isEmpty else { return }
        turn = activeTurn
        if !itemIDs.contains(item.id) { itemIDs.append(item.id) }
        if itemIDs.count > 64 { itemIDs.removeFirst(itemIDs.count - 64) }
    }
}
