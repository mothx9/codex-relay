import Foundation

/// Notifications carry navigation, never approval content or executable actions.
public enum RelayDestination: Equatable, Sendable {
    case fleet
    case machine(String)
    case session(String)

    public static func machineID(in session: String) -> String? {
        let parts = session.split(separator: "~", omittingEmptySubsequences: false)
        guard parts.count == 2, validMachine(String(parts[0])), !parts[1].isEmpty,
              parts[1].utf8.count <= 256,
              !parts[1].unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0 == "/" || $0 == "\\" }) else { return nil }
        return String(parts[0])
    }
    private static func validMachine(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 64 && id.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }
    }
    public static func notification(session: String?, machine: String?) -> Self? {
        if let session, !session.isEmpty {
            guard machineID(in: session) != nil else { return nil }
            return .session(session)
        }
        if let machine, !machine.isEmpty {
            guard validMachine(machine) else { return nil }
            return .machine(machine)
        }
        return .fleet
    }
    public static func link(_ url: URL) -> Self? {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.scheme == "codex-relay",
              c.user == nil, c.password == nil, c.port == nil, c.query == nil, c.fragment == nil else { return nil }
        let path = c.path
        guard path.hasPrefix("/"), path.count > 1 else { return nil }
        let id = String(path.dropFirst())
        switch c.host {
        case "session": return notification(session: id, machine: nil)
        case "machine": return notification(session: nil, machine: id)
        default: return nil
        }
    }
}

/// One latest user navigation intent, retained through cold start/authentication.
/// It is consumed only after a canonical snapshot, never by socket connection alone.
public struct PendingNavigation: Sendable {
    public private(set) var target: RelayDestination?
    public init() {}
    public mutating func receive(_ target: RelayDestination) { self.target = target }
    public mutating func take(authenticated: Bool, snapshotReady: Bool) -> RelayDestination? {
        guard authenticated, snapshotReady else { return nil }
        defer { target = nil }
        return target
    }
}

public struct NativePushState: Decodable, Sendable {
    public let configured: Bool
    public let registered: Bool
    public let environment: String?
    public let privacy: Bool?
}

/// Delivery capability is independent from OS authorization and observed delivery.
public struct NotificationReadiness: Equatable, Sendable {
    public var enabled = false
    public var permission = false
    public var connected = false
    public var appleRegistered = false
    public var hubConfigured = false
    public var relayRegistered = false
    public var registrationVerified = false
    public init() {}
    public var localReady: Bool { enabled && permission && connected }
    public var remoteReady: Bool { enabled && permission && appleRegistered && hubConfigured && relayRegistered && registrationVerified }
    // A prior confirmed subscription can receive push even before a new token callback.
    public var remoteOwnsDelivery: Bool { hubConfigured && relayRegistered && registrationVerified }
}

public struct SemanticNotice: Equatable, Sendable {
    public enum Kind: String, Sendable { case request, liveQuestion = "live_question", completed = "turn_completed", failed, offline = "machine_offline", test }
    public let key: String
    public let kind: Kind
    public let sessionID: String
    public let machineID: String
    public let requestID: String?
    public let turnID: String?
    public init(key: String, kind: Kind, sessionID: String = "", machineID: String = "", requestID: String? = nil, turnID: String? = nil) {
        self.key = key; self.kind = kind; self.sessionID = sessionID; self.machineID = machineID; self.requestID = requestID; self.turnID = turnID
    }
    public static func event(_ event: RelayEvent) -> Self? {
        if let request = event.request {
            return Self(key: request.notifyKey ?? request.sessionId + "/request/" + (request.turnId ?? "") + "/" + request.kind + "/" + request.id, kind: .request, sessionID: request.sessionId, machineID: request.machineId, requestID: request.id, turnID: request.turnId)
        }
        if ["activity", "live_question"].contains(event.kind), let activity = event.activity, !(activity.questions ?? []).isEmpty, let turn = event.turnId, !turn.isEmpty {
            return Self(key: event.sessionId + "/live_question/" + turn + "/" + activity.id, kind: .liveQuestion, sessionID: event.sessionId, machineID: event.machineId ?? "", turnID: turn)
        }
        if ["turn_completed", "failed"].contains(event.kind), let turn = event.turnId, !turn.isEmpty {
            return Self(key: event.notifyKey ?? event.sessionId + "/turn/" + turn, kind: event.kind == "failed" ? .failed : .completed, sessionID: event.sessionId, machineID: event.machineId ?? "", turnID: turn)
        }
        return nil
    }
    /// Routing identity is captured from the event, never borrowed from a newer turn.
    public func presentation(machine: String?, session: RelaySession?, hideDetails: Bool) -> NoticePresentation {
        guard !hideDetails else { return NoticePresentation(title: title, subtitle: "", body: body) }
        func clean(_ text: String?, limit: Int) -> String {
            String((text ?? "").components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ").prefix(limit))
        }
        let machineName = clean(machine?.isEmpty == false ? machine : machineID, limit: 48)
        let matching = session?.id == sessionID ? session : nil
        let project = clean(matching?.project, limit: 48)
        let subtitle = [machineName, project].filter { !$0.isEmpty }.joined(separator: " · ")
        let name = clean(matching?.title, limit: 120)
        var details = name.isEmpty && !sessionID.isEmpty ? clean(sessionID, limit: 100) : name
        if let turnID, !turnID.isEmpty {
            let turn = String(localized: "Turn", bundle: relayLocalizationBundle) + " " + clean(String(turnID.suffix(8)), limit: 8)
            details = [details, turn].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return NoticePresentation(title: title, subtitle: subtitle, body: details.isEmpty ? body : details)
    }

    public var title: String {
        switch kind {
        case .request: String(localized: "Codex needs your input", bundle: relayLocalizationBundle)
        case .liveQuestion: String(localized: "Codex asked a live question", bundle: relayLocalizationBundle)
        case .completed: String(localized: "Codex finished", bundle: relayLocalizationBundle)
        case .failed: String(localized: "Codex needs attention", bundle: relayLocalizationBundle)
        case .offline: String(localized: "A machine went offline", bundle: relayLocalizationBundle)
        case .test: String(localized: "Local alert test", bundle: relayLocalizationBundle)
        }
    }
    public var body: String {
        String(localized: "Open Relay to see the current state.", bundle: relayLocalizationBundle)
    }
}

public struct NoticePresentation: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let body: String
}

/// Bounded semantic dedupe, independent from transport event IDs. No transcript.
public struct LocalNoticePolicy: Sendable {
    public private(set) var seen: [String] = []
    public init() {}
    public mutating func admit(_ notice: SemanticNotice, readiness: NotificationReadiness, selectedSession: String) -> Bool {
        guard !seen.contains(notice.key) else { return false }
        seen.append(notice.key); if seen.count > 512 { seen.removeFirst(seen.count - 512) }
        guard readiness.localReady, !readiness.remoteOwnsDelivery else { return false }
        // Attention still interrupts; completion already visible in the open chat is quiet.
        return notice.kind != .completed || selectedSession != notice.sessionID
    }
}
