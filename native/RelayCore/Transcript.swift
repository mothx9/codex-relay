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
