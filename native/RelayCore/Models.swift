import Foundation

public struct Account: Codable, Sendable {
    public let kind: String; public let email: String?; public let plan: String?
    public let id: String?; public let source: String?; public let observedAt: String?; public let hubObservedAt: String?
    public let limits: AccountLimits?; public let buckets: [String: AccountLimits]?
    public let ordinaryUsageAllowed: Bool?; public let resetCredits: ResetCredits?
    public var usageBuckets: [(String, AccountLimits)] {
        if let buckets, !buckets.isEmpty { return buckets.keys.sorted().map { ($0, buckets[$0]!) } }
        return limits.map { [($0.limitId ?? "usage", $0)] } ?? []
    }
}
public struct RateWindow: Codable, Sendable {
    public let usedPercent: Int
    public let windowDurationMins: Int?; public let resetsAt: Int64?
    public var label: String {
        guard let minutes = windowDurationMins, minutes > 0 else { return String(localized: "Usage window", bundle: relayLocalizationBundle) }
        if minutes % 1440 == 0 { return String(localized: "\(minutes / 1440)-day window", bundle: relayLocalizationBundle) }
        if minutes % 60 == 0 { return String(localized: "\(minutes / 60)-hour window", bundle: relayLocalizationBundle) }
        return String(localized: "\(minutes)-minute window", bundle: relayLocalizationBundle)
    }
    public var remainingPercent: Int { 100 - min(100, max(0, usedPercent)) }
    public var remainingFraction: Double { Double(remainingPercent) / 100 }
    public var fraction: Double { min(1, max(0, Double(usedPercent) / 100)) }
}
public struct AccountLimits: Codable, Sendable {
    public let limitId: String?; public let limitName: String?; public let normalModelSlug: String?; public let planType: String?
    public let primary: RateWindow?; public let secondary: RateWindow?; public let credits: AccountCredits?
    public let individualLimit: SpendControl?; public let spendControlReached: Bool?; public let rateLimitReachedType: String?
}
public struct AccountCredits: Codable, Sendable {
    public let hasCredits: Bool; public let unlimited: Bool; public let balance: String?
    public var displayBalance: String? {
        guard let balance else { return nil }
        let scanner = Scanner(string: balance); scanner.locale = Locale(identifier: "en_US_POSIX")
        var decimal = Decimal()
        guard scanner.scanDecimal(&decimal), scanner.isAtEnd else { return balance }
        return NSDecimalString(&decimal, Locale.current)
    }
}
public struct SpendControl: Codable, Sendable { public let limit: String; public let used: String; public let remainingPercent: Int; public let resetsAt: Int64 }
public struct ResetCredits: Codable, Sendable { public let availableCount: Int; public let credits: [ResetCredit]? }
public struct ResetCredit: Codable, Identifiable, Sendable { public let id: String; public let title: String?; public let description: String?; public let status: String; public let resetType: String; public let grantedAt: Int64; public let expiresAt: Int64? }
public struct AccountRegistry: Decodable, Sendable { public let accounts: [AccountEntry] }
public struct AccountEntry: Decodable, Identifiable, Sendable {
    public let id: String; public let identityBasis: String; public let account: Account; public let machines: [String]
    public let sourceMachine: String; public let fresh: Bool; public let updatedAt: String
}
public struct TokenBreakdown: Codable, Sendable {
    public let inputTokens: Int64; public let cachedInputTokens: Int64; public let cacheWriteInputTokens: Int64?
    public let outputTokens: Int64; public let reasoningOutputTokens: Int64?; public let totalTokens: Int64
}
public struct TokenUsage: Codable, Sendable { public let last: TokenBreakdown; public let total: TokenBreakdown; public let modelContextWindow: Int64?; public let observedAt: String?; public let source: String? }

public struct MachineFreshness: Codable, Sendable {
    public let connectionId: String?; public let epoch: String?; public let protocolVersion: Int?
    public let connectedAt: String?; public let lastDisconnectReason: String?; public let agentToHub: TransportTiming?
    public let lastHeartbeat: String?; public let lastEvent: String?; public let lastSnapshot: String?
    public let sequence: UInt64?; public let snapshotSequence: UInt64?
    public let reconnectCount: UInt64?; public let snapshotMs: Double?; public let syncMs: Double?
}
public struct Machine: Codable, Identifiable, Sendable {
    public var agentVersion: String? = nil
    public var freshness: MachineFreshness? = nil
    public let id: String; public let name: String; public let status: String
    public let codexVersion: String?; public let adapter: String?; public let lastSeen: String
    public let account: Account?
    public func connectionLabel(hubConnected: Bool, access: String? = nil) -> String {
        if !hubConnected { return String(localized: "Hub not connected", bundle: relayLocalizationBundle) }
        if access == "PAUSED" { return String(localized: "Relay paused", bundle: relayLocalizationBundle) }
        if access == "REVOKED" { return String(localized: "Relay access revoked", bundle: relayLocalizationBundle) }
        switch status {
        case "ONLINE": return String(localized: "Relay connected", bundle: relayLocalizationBundle)
        case "SYNCING": return String(localized: "Syncing with Codex…", bundle: relayLocalizationBundle)
        case "RECONNECTING": return String(localized: "Reconnecting Relay…", bundle: relayLocalizationBundle)
        case "DEGRADED": return String(localized: "Codex not connected", bundle: relayLocalizationBundle)
        default: return String(localized: "Relay not connected", bundle: relayLocalizationBundle)
        }
    }
}
public struct Capabilities: Codable, Sendable {
	public var canSteerQueue: Bool?
    public var canSendImages: Bool?
    public var canEditQueue: Bool?
    public var canSend: Bool; public var canFollowUp: Bool; public var canSteer: Bool; public var canInterrupt: Bool; public var canAnswer: Bool
    public init(canSend: Bool = false, canFollowUp: Bool = false, canSteer: Bool = false, canInterrupt: Bool = false, canAnswer: Bool = false) {
        self.canSend = canSend; self.canFollowUp = canFollowUp; self.canSteer = canSteer; self.canInterrupt = canInterrupt; self.canAnswer = canAnswer
    }
}
public struct RelaySession: Codable, Identifiable, Sendable {
    public var tokenUsage: TokenUsage? = nil
	public var failureReason: String? = nil
    public var fresh: Bool? = nil
    public var observedAt: String? = nil
    public var agentEpoch: String? = nil
    public let id: String; public let machineId: String; public let threadId: String
    public let parentThreadId: String?
    public let agentNickname: String?
    public let agentRole: String?
    public let title: String; public let project: String; public let cwd: String; public let branch: String?
    public var status: String; public let updatedAt: String; public var turnId: String?; public let turnStarted: String?
    public var readOnly: Bool; public var capabilities: Capabilities
	public var parentSessionId: String? {
		guard let parentThreadId, !parentThreadId.isEmpty else { return nil }
		return machineId + "~" + parentThreadId
	}
	public var isSubagent: Bool { parentSessionId != nil }
	public var displayTitle: String {
		guard isSubagent else { return title }
		let fallback = "Thread " + String(threadId.prefix(8))
		let role = agentRole?.trimmingCharacters(in: .whitespacesAndNewlines)
		let nickname = agentNickname?.trimmingCharacters(in: .whitespacesAndNewlines)
		let detail: String
		if title != fallback && !title.isEmpty { detail = title }
		else if let role, !role.isEmpty, role != "default", role != "worker" { detail = role }
		else if let nickname, !nickname.isEmpty { detail = nickname }
		else { detail = String(threadId.prefix(8)) }
		return String(localized: "Subagent", bundle: relayLocalizationBundle) + " · " + detail
	}
	public var defaultCommand: String { ["READY", "FAILED"].contains(status) ? "new_turn" : status == "WORKING" ? "follow_up" : status == "NEEDS_YOU" ? "answer" : "" }
	public var failureSummary: String {
		switch failureReason {
		case "capacity": String(localized: "Model at capacity", bundle: relayLocalizationBundle)
		case "usage_limit": String(localized: "Usage limit reached", bundle: relayLocalizationBundle)
		case "rate_limit": String(localized: "Too many requests", bundle: relayLocalizationBundle)
		case "authentication": String(localized: "Codex sign-in required", bundle: relayLocalizationBundle)
		case "context_limit": String(localized: "Context limit reached", bundle: relayLocalizationBundle)
		case "connection": String(localized: "Model connection lost", bundle: relayLocalizationBundle)
		case "service": String(localized: "Codex service unavailable", bundle: relayLocalizationBundle)
		default: String(localized: "Codex turn failed", bundle: relayLocalizationBundle)
		}
	}
    public func displayStatus(machine: Machine?, connected: Bool) -> String {
        guard connected, let machine else { return "OFFLINE" }
        guard machine.status == "ONLINE" else { return machine.status }
        return fresh == false ? "SYNCING" : status
    }
    public var canEditQueueAvailable: Bool { !readOnly && capabilities.canEditQueue == true }
    public func allows(_ kind: String) -> Bool {
        if kind == "answer" { return capabilities.canAnswer }
        if readOnly { return false }
        switch kind {
        case "queue_update": return canEditQueueAvailable
        case "queue_steer": return status == "WORKING" && !(turnId ?? "").isEmpty && capabilities.canSteer && capabilities.canSteerQueue == true
		case "new_turn": return ["READY", "FAILED"].contains(status) && capabilities.canSend
        case "follow_up": return status == "WORKING" && capabilities.canFollowUp
        case "steer": return status == "WORKING" && !(turnId ?? "").isEmpty && capabilities.canSteer
        case "interrupt": return !(turnId ?? "").isEmpty && capabilities.canInterrupt
        default: return false
        }
    }
}
public struct ChangedFile: Codable, Sendable, Equatable {
    public let path: String; public let kind: String; public let previousPath: String?; public let patch: String?
}
public struct LiveActivity: Codable, Sendable, Equatable {
    public let itemId: String; public let kind: String; public let label: String; public let state: String; public let timestamp: String
    public var title: String {
        switch kind { case "context_compaction": state == "running" ? String(localized: "Compacting context", bundle: relayLocalizationBundle) : String(localized: "Context compacted", bundle: relayLocalizationBundle); case "terminal": String(localized: "Terminal", bundle: relayLocalizationBundle); case "tool": "MCP"; case "file": "File"; case "diff": "Diff"; case "assistant": state == "running" ? String(localized: "Generating response…", bundle: relayLocalizationBundle) : String(localized: "Response completed", bundle: relayLocalizationBundle); default: String(localized: "Activity", bundle: relayLocalizationBundle) }
    }
    public var detail: String { label.isEmpty ? title : title + " · " + label }
    /// Fleet shows the current operation category, never a shell body or stale completion.
    public var fleetSummary: String {
        guard state == "running" else { return String(localized: "Working", bundle: relayLocalizationBundle) }
        switch kind {
        case "terminal": return String(localized: "Terminal", bundle: relayLocalizationBundle)
        case "tool": return String(localized: "Tools", bundle: relayLocalizationBundle)
        case "file", "diff": return String(localized: "Changes", bundle: relayLocalizationBundle)
        case "assistant": return String(localized: "Generating response…", bundle: relayLocalizationBundle)
        case "context_compaction": return String(localized: "Compacting context", bundle: relayLocalizationBundle)
        default: return String(localized: "Working", bundle: relayLocalizationBundle)
        }
    }
}
public struct QuestionReply: Codable, Sendable, Equatable {
    public let question: String
    public let answer: String
}
public struct Activity: Codable, Identifiable, Sendable, Equatable {
    public var replies: [QuestionReply]?
    public var imageCount: Int?
    public var id: String; public var kind: String; public var text: String; public var timestamp: String?; public var clientId: String?
    public var turnId: String?
    public var questions: [AsyncQuestion]?; public var truncated: Bool?
    public var state: String?; public var command: String?; public var exitCode: Int?; public var durationMs: Int?
    public var progress: String?; public var resultSummary: String?
    public var toolName: String?; public var toolServer: String?; public var files: [ChangedFile]?
    public var commandOutput: String {
        guard let command, !command.isEmpty else { return text }
        if text == command { return "" }
        if text.hasPrefix(command + "\n") { return String(text.dropFirst(command.count + 1)) }
        return text
    }
    public init(id: String, kind: String, text: String, timestamp: String? = nil, clientId: String? = nil, questions: [AsyncQuestion]? = nil, truncated: Bool? = nil) { self.id = id; self.kind = kind; self.text = text; self.timestamp = timestamp; self.clientId = clientId; self.questions = questions; self.truncated = truncated }
    public var contextBytes: Int { (replies ?? []).reduce(0) { $0 + $1.question.utf8.count + $1.answer.utf8.count } + (progress?.utf8.count ?? 0) + (resultSummary?.utf8.count ?? 0) + text.utf8.count + (questions ?? []).reduce(0) { $0 + $1.title.utf8.count + ($1.options ?? []).reduce(0) { $0 + $1.utf8.count } } + (command?.utf8.count ?? 0) + (toolName?.utf8.count ?? 0) + (toolServer?.utf8.count ?? 0) + (files ?? []).reduce(0) { $0 + $1.path.utf8.count + $1.kind.utf8.count + ($1.previousPath?.utf8.count ?? 0) + ($1.patch?.utf8.count ?? 0) } }
}
public struct AsyncQuestion: Codable, Sendable, Equatable {
    public let title: String; public let options: [String]?
    public init(title: String, options: [String]? = nil) { self.title = title; self.options = options }
}
public struct FollowUp: Codable, Sendable {
    public let imageCount: Int?
    public let id: String; public let clientId: String; public let text: String?
    public let editable: Bool?; public let revision: String?
}
public struct QuestionOption: Codable, Sendable { public let label: String; public let description: String }
public struct Question: Codable, Identifiable, Sendable { public let id: String; public let header: String; public let question: String; public let options: [QuestionOption]?; public let secret: Bool? }
public struct PendingRequest: Codable, Identifiable, Sendable {
    public var id: String { requestId }; public let requestId: String; public let sessionId: String; public let machineId: String
    public let kind: String; public let description: String; public let operation: String?; public let cwd: String?
    public let questions: [Question]?; public let expiresAt: String; public let canApprove: Bool
    public var notifyKey: String? = nil
    public var payload: RequestPayload?
    public let turnId: String?; public let createdAt: String?
    /// A request RPC ID can be reused after a daemon restart. Form state belongs
    /// to one incarnation, while wire commands continue to use requestId.
    public var presentationID: String { [machineId, sessionId, requestId, kind, turnId ?? "", createdAt ?? expiresAt].joined(separator: "|") }
    public func retainingContext(from prior: PendingRequest?) -> PendingRequest {
        var value = self
        if let prior, presentationID == prior.presentationID, value.payload == nil { value.payload = prior.payload }
        return value
    }
}
public struct Snapshot: Decodable, Sendable { public let machines: [Machine]; public let sessions: [RelaySession]; public let requests: [PendingRequest]; public let liveActivities: [String: LiveActivity]? }
public struct RelayEvent: Decodable, Sendable {
    public var machineId: String? = nil; public var epoch: String? = nil; public var sequence: UInt64? = nil
    public var hubObservedAt: String? = nil
    public var notifyKey: String? = nil
    public let liveActivity: LiveActivity?
    public let eventId: String?; public let kind: String; public let sessionId: String; public let session: RelaySession?
    public let request: PendingRequest?; public let requestId: String?; public let activity: Activity?
    public let text: String?; public let itemId: String?; public let turnId: String?; public let clientId: String?
    public let timestamp: String?; public let followUps: [FollowUp]?
}
public struct CommandResult: Decodable, Sendable {
    public let queueRemoved: Bool?
    public let queueId: String?
    public let machineId: String?; public let catalogueCursor: String?; public let sessions: [RelaySession]?
    public let id: String; public let ok: Bool; public let error: String?; public let errorCode: String?; public let sessionId: String?
    public let history: [Activity]?; public let historyCursor: String?; public let followUps: [FollowUp]?
}
public struct WireMessage: Decodable, Sendable { public let type: String; public let historyRequestId: String?; public let snapshot: Snapshot?; public let event: RelayEvent?; public let result: CommandResult? }
public struct OperatorDevice: Decodable, Identifiable, Sendable { public let id: String; public let name: String; public let createdAt: String; public let expiresAt: String; public let lastSeen: String; public let revoked: Bool }
public struct MachineDevice: Decodable, Identifiable, Sendable { public var id: String { machine.id }; public let machine: Machine; public let access: String }
public struct DeviceRegistry: Decodable, Sendable { public let operators: [OperatorDevice]; public let machines: [MachineDevice]; public let currentDeviceId: String; public let hubUrl: String; public let chatgptDeviceManagement: Bool }
public struct PairCode: Decodable, Sendable { public let code: String; public let expiresAt: String; public let hubUrl: String; public let kind: String; public let machine: String }
public struct Credential: Codable, Sendable { public let id: String; public let token: String; public let kind: String; public let expiresAt: String; public let hubUrl: String }
public struct Ack: Decodable, Sendable { public let ok: Bool }
public enum RelayJSON {
    public static func decoder() -> JSONDecoder { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }
    public static func encoder() -> JSONEncoder { let e = JSONEncoder(); e.keyEncodingStrategy = .convertToSnakeCase; return e }
}

// Arbitrary MCP keys must never pass through snake-case conversion.
public indirect enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public var object: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
    public var array: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var number: Double? { if case .number(let v) = self { return v }; return nil }
    public var pretty: String {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? e.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }
    public var foundation: Any {
        switch self {
        case .object(let v): return v.mapValues { $0.foundation }
        case .array(let v): return v.map { $0.foundation }
        case .string(let v): return v
        case .number(let v): return v
        case .bool(let v): return v
        case .null: return NSNull()
        }
    }
}
public struct RequestPayload: Codable, Sendable {
    public let permissions: JSONValue?
    public let inputSchema: JSONValue?
}
public enum MCPResponse {
    public static func parse(_ text: String, schema: JSONValue) throws -> JSONValue {
        guard text.utf8.count <= 65_536 else { throw HubFailure.message(String(localized: "Response too large (64 KiB maximum).", bundle: relayLocalizationBundle)) }
        let value: JSONValue
        do { value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }
        catch { throw HubFailure.message(String(localized: "Enter a valid JSON response.", bundle: relayLocalizationBundle)) }
        guard value.object != nil else { throw HubFailure.message(String(localized: "The MCP response must be a JSON object.", bundle: relayLocalizationBundle)) }
        try validate(value, schema: schema, path: String(localized: "Answer", bundle: relayLocalizationBundle), depth: 0)
        return value
    }
    public static func fields(_ values: [String: String], schema: JSONValue) throws -> JSONValue {
        guard let properties = schema.object?["properties"]?.object else { return try parse("{}", schema: schema) }
        var content: [String: JSONValue] = [:]
        for (key, property) in properties {
            guard let text = values[key], !text.isEmpty else { continue }
            if let choices = property.object?["enum"]?.array {
                guard let choice = choices.first(where: { ($0.string ?? $0.pretty) == text }) else { throw HubFailure.message(String(localized: "\(key): choose an allowed value.", bundle: relayLocalizationBundle)) }
                content[key] = choice
            } else if property.object?["type"]?.string == "string" { content[key] = .string(text) }
            else {
                do { content[key] = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }
                catch { throw HubFailure.message(String(localized: "\(key): enter a valid value of the required type.", bundle: relayLocalizationBundle)) }
            }
        }
        return try parse(JSONValue.object(content).pretty, schema: schema)
    }
    private static func validate(_ value: JSONValue, schema: JSONValue, path: String, depth: Int) throws {
        func fail(_ reason: String) throws { throw HubFailure.message("\(path): \(reason)") }
        guard depth < 20 else { try fail(String(localized: "schema nested too deeply; use local Codex.", bundle: relayLocalizationBundle)); return }
        if schema == .bool(true) { return }
        if schema == .bool(false) { try fail(String(localized: "value not allowed.", bundle: relayLocalizationBundle)); return }
        guard let s = schema.object else { try fail(String(localized: "invalid schema.", bundle: relayLocalizationBundle)); return }
        let unsupported = ["$ref", "$dynamicRef", "patternProperties", "dependentSchemas", "dependentRequired", "if", "then", "else", "prefixItems", "contains", "unevaluatedProperties", "unevaluatedItems"]
        if unsupported.contains(where: { s[$0] != nil }) { try fail(String(localized: "advanced schema: resolve this request in local Codex.", bundle: relayLocalizationBundle)) }
        if let choices = s["enum"]?.array, !choices.contains(value) { try fail(String(localized: "unexpected value for this schema.", bundle: relayLocalizationBundle)) }
        if let constant = s["const"], constant != value { try fail(String(localized: "value does not match the required constant.", bundle: relayLocalizationBundle)) }
        if let types = s["type"] {
            let allowed = types.array?.compactMap(\.string) ?? types.string.map { [$0] } ?? []
            let type: String
            switch value { case .object: type = "object"; case .array: type = "array"; case .string: type = "string"; case .number: type = "number"; case .bool: type = "boolean"; case .null: type = "null" }
            let integer = value.number.map { $0.isFinite && $0.rounded() == $0 } ?? false
            if !allowed.contains(type) && !(integer && allowed.contains("integer")) { try fail(String(localized: "required type: \(allowed.joined(separator: ", ")).", bundle: relayLocalizationBundle)) }
        }
        for sub in s["allOf"]?.array ?? [] { try validate(value, schema: sub, path: path, depth: depth+1) }
        for key in ["anyOf", "oneOf"] {
            if let alternatives = s[key]?.array {
                let matches = alternatives.filter { (try? validate(value, schema: $0, path: path, depth: depth+1)) != nil }.count
                if matches == 0 || (key == "oneOf" && matches != 1) { try fail(String(localized: "response does not match any schema alternative.", bundle: relayLocalizationBundle)) }
            }
        }
        if let negation = s["not"], (try? validate(value, schema: negation, path: path, depth: depth+1)) != nil { try fail(String(localized: "value excluded by the schema.", bundle: relayLocalizationBundle)) }
        if let object = value.object {
            for key in s["required"]?.array?.compactMap(\.string) ?? [] where object[key] == nil { try fail(String(localized: "missing field: \(key).", bundle: relayLocalizationBundle)) }
            let properties = s["properties"]?.object ?? [:]
            for (key, field) in object {
                if let property = properties[key] { try validate(field, schema: property, path: path+"."+key, depth: depth+1) }
                else if s["additionalProperties"] == .bool(false) { try fail(String(localized: "unexpected field: \(key).", bundle: relayLocalizationBundle)) }
                else if let extra = s["additionalProperties"], extra.object != nil { try validate(field, schema: extra, path: path+"."+key, depth: depth+1) }
            }
            if let min = s["minProperties"]?.number, Double(object.count) < min { try fail(String(localized: "too few fields.", bundle: relayLocalizationBundle)) }
            if let max = s["maxProperties"]?.number, Double(object.count) > max { try fail(String(localized: "too many fields.", bundle: relayLocalizationBundle)) }
        }
        if let text = value.string {
            if let min = s["minLength"]?.number, Double(text.unicodeScalars.count) < min { try fail(String(localized: "text too short.", bundle: relayLocalizationBundle)) }
            if let max = s["maxLength"]?.number, Double(text.unicodeScalars.count) > max { try fail(String(localized: "text too long.", bundle: relayLocalizationBundle)) }
            if let pattern = s["pattern"]?.string {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { try fail(String(localized: "unsupported pattern; use local Codex.", bundle: relayLocalizationBundle)); return }
                if regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil { try fail(String(localized: "text does not match the pattern.", bundle: relayLocalizationBundle)) }
            }
        }
        if let number = value.number {
            if let min = s["minimum"]?.number, number < min { try fail(String(localized: "value below minimum.", bundle: relayLocalizationBundle)) }
            if let max = s["maximum"]?.number, number > max { try fail(String(localized: "value above maximum.", bundle: relayLocalizationBundle)) }
            if let min = s["exclusiveMinimum"]?.number, number <= min { try fail(String(localized: "value at or below the exclusive limit.", bundle: relayLocalizationBundle)) }
            if let max = s["exclusiveMaximum"]?.number, number >= max { try fail(String(localized: "value at or above the exclusive limit.", bundle: relayLocalizationBundle)) }
            if let step = s["multipleOf"]?.number {
                if step <= 0 || abs(number/step - (number/step).rounded()) > 1e-9 { try fail(String(localized: "value is not a multiple of the required step.", bundle: relayLocalizationBundle)) }
            }
        }
        if let array = value.array {
            if let min = s["minItems"]?.number, Double(array.count) < min { try fail(String(localized: "too few items.", bundle: relayLocalizationBundle)) }
            if let max = s["maxItems"]?.number, Double(array.count) > max { try fail(String(localized: "too many items.", bundle: relayLocalizationBundle)) }
            if s["uniqueItems"] == .bool(true), Set(array.map(\.pretty)).count != array.count { try fail(String(localized: "duplicate items.", bundle: relayLocalizationBundle)) }
            if let items = s["items"] {
                guard items.object != nil || items == .bool(true) || items == .bool(false) else { try fail(String(localized: "unsupported item schema.", bundle: relayLocalizationBundle)); return }
                for (i,item) in array.enumerated() { try validate(item, schema: items, path: path+"[\(i)]", depth: depth+1) }
            }
        }
    }
}

/// Additional client-side guard; transport generation and Hub admission remain authoritative.
public struct EventFreshness: Sendable {
    private var epochs: [String: String] = [:]
    private var sequences: [String: UInt64] = [:]
    public init() {}
    public mutating func snapshot(_ machines: [Machine]) {
        epochs = [:]; sequences = [:]
        for machine in machines {
            epochs[machine.id] = machine.freshness?.epoch
            sequences[machine.id] = machine.freshness?.sequence
        }
    }
    public mutating func accept(_ event: RelayEvent) -> Bool {
        guard let machine = event.machineId, let epoch = event.epoch, !epoch.isEmpty,
              let sequence = event.sequence, sequence > 0 else { return true }
        if let current = epochs[machine], current != epoch { return false }
        if let prior = sequences[machine], sequence <= prior { return false }
        epochs[machine] = epoch; sequences[machine] = sequence
        return true
    }
}

/// Bounded in-memory diagnostics. Rendering duration is deliberately not inferred.
public struct ReceiptTiming: Sendable {
    public private(set) var samples = 0
    public private(set) var hubToNativeMs: Double = 0
    public private(set) var reducerMs: Double = 0
    public private(set) var clockSkew = false
    public init() {}
    public mutating func observe(hub: String?, received: Date, reduced: Date) {
        reducerMs = max(0, reduced.timeIntervalSince(received) * 1000)
        guard let hub else { return }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: hub) ?? ISO8601DateFormatter().date(from: hub), date.timeIntervalSince1970 > 0 else { return }
        let ms = received.timeIntervalSince(date) * 1000
        guard ms >= 0, ms < 300_000 else { clockSkew = true; return }
        samples = min(samples + 1, 1024); hubToNativeMs = ms
    }
}

/// Bounded discovery cache. Canonical live sessions always win over catalogue pages.
public struct SessionCatalogue: Sendable {
    public private(set) var sessions: [String: RelaySession] = [:]
    public private(set) var cursors: [String: String] = [:]
    public private(set) var completed: Set<String> = []
    public init() {}
    public mutating func apply(machine: String, page: [RelaySession], cursor: String?) {
        for session in page where session.machineId == machine { sessions[session.id] = session }
        cursors[machine] = cursor
        if cursor == nil || cursor == "" { completed.insert(machine) }
        if sessions.count > 1024 {
            let incoming = Set(page.map(\.id))
            let oldest = sessions.values.filter { !incoming.contains($0.id) }.sorted { $0.updatedAt < $1.updatedAt }
            for session in oldest.prefix(sessions.count - 1024) { sessions.removeValue(forKey: session.id) }
        }
    }
    public mutating func restart(machine: String) { cursors[machine] = nil; completed.remove(machine) }
    public func merged(canonical: [String: RelaySession]) -> [String: RelaySession] {
        sessions.merging(canonical) { _, current in current }
    }
}

/// Ephemeral inline image; the wire encoder emits base64, never a local path.
public struct ImageInput: Sendable, Equatable, Identifiable {
    public let id = UUID().uuidString
    public let mediaType: String
    public let data: Data
    public init(mediaType: String = "image/jpeg", data: Data) { self.mediaType = mediaType; self.data = data }
    public static let maxCount = 2
    public static let maxBytes = 256 * 1024
}
