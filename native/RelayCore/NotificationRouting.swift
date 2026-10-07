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
