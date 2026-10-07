import Foundation

public struct TransportTiming: Codable, Sendable {
    public let samples: UInt64
    public let lastMs: Double; public let meanMs: Double; public let maxMs: Double
    public let clockSkew: Bool
}
public struct RelayDiagnostics: Decodable, Sendable {
    public let hubVersion: String
    public let protocolVersion: Int
    public let transport: String
    public let database: String?
    public let machines: [DiagnosticMachine]

    /// Shareable allowlist: no hostnames, origins, account/controller IDs, epochs,
    /// disconnect strings, credentials or request/transcript content.
    public func redactedReport(appVersion: String, hubConnected: Bool) -> String {
        func version(_ raw: String) -> String {
            raw.count <= 80 && raw.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".+-_ ")).contains($0) } ? raw : "unavailable"
        }
        func number(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "unavailable" }
        var lines = ["Codex Relay diagnostics (identities redacted)", "App: \(version(appVersion))", "Hub: \(version(hubVersion))", "Protocol: \(protocolVersion)", "Hub connected: \(hubConnected)", "Database: \(database == nil ? "not reported" : database == "reachable" ? "reachable" : "unavailable")", "Machines: \(machines.count)"]
        for (index, machine) in machines.enumerated() {
            let state = ["ONLINE", "SYNCING", "RECONNECTING", "DEGRADED", "OFFLINE"].contains(machine.state) ? machine.state : "UNKNOWN"
            lines += ["", "Machine \(index + 1): \(state)", "Agent: \(version(machine.agentVersion))", "Codex: \(version(machine.codexVersion))", "Sessions: \(machine.sessions); hot: \(machine.hot); pending: \(machine.pending)", "Snapshot ms: \(number(machine.freshness.snapshotMs))", "Connection to Online ms: \(number(machine.freshness.syncMs))", "Reconnects: \(machine.freshness.reconnectCount ?? 0)", "Sequence: \(machine.freshness.sequence ?? 0); snapshot watermark: \(machine.freshness.snapshotSequence ?? 0)"]
            if let timing = machine.freshness.agentToHub {
                lines += ["Agent to Hub samples: \(timing.samples)", "Agent to Hub mean ms: \(timing.clockSkew ? "clocks not comparable" : number(timing.meanMs))"]
            }
        }
        lines.append("Cross-host timing includes clock offset. No model execution or rendering time is inferred.")
        return lines.joined(separator: "\n")
    }
}
public struct DiagnosticMachine: Decodable, Identifiable, Sendable {
    public let id: String; public let state: String; public let agentVersion: String
    public let codexVersion: String; public let adapter: String; public let lastSeen: String
    public let snapshotAgeMs: Int64?; public let freshness: MachineFreshness
    public let sessions: Int; public let hot: Int; public let pending: Int
}
