import Foundation

public struct Account: Codable, Sendable { public let kind: String; public let email: String?; public let plan: String? }
public struct MachineFreshness: Codable, Sendable {
    public let connectionId: String?; public let epoch: String?; public let protocolVersion: Int?
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
        if !hubConnected { return "Hub non connesso" }
        if access == "PAUSED" { return "Relay in pausa" }
        if access == "REVOKED" { return "Accesso Relay revocato" }
        switch status {
        case "ONLINE": return "Relay collegato"
        case "SYNCING": return "Sincronizzazione Codex…"
        case "RECONNECTING": return "Riconnessione Relay…"
        case "DEGRADED": return "Codex non connesso"
        default: return "Relay non connesso"
        }
    }
}
public struct Capabilities: Codable, Sendable {
    public var canEditQueue: Bool?
    public var canSend: Bool; public var canFollowUp: Bool; public var canSteer: Bool; public var canInterrupt: Bool; public var canAnswer: Bool
    public init(canSend: Bool = false, canFollowUp: Bool = false, canSteer: Bool = false, canInterrupt: Bool = false, canAnswer: Bool = false) {
        self.canSend = canSend; self.canFollowUp = canFollowUp; self.canSteer = canSteer; self.canInterrupt = canInterrupt; self.canAnswer = canAnswer
    }
}
public struct RelaySession: Codable, Identifiable, Sendable {
    public var fresh: Bool? = nil
    public var observedAt: String? = nil
    public var agentEpoch: String? = nil
    public let id: String; public let machineId: String; public let threadId: String
    public let title: String; public let project: String; public let cwd: String; public let branch: String?
    public var status: String; public let updatedAt: String; public var turnId: String?; public let turnStarted: String?
    public var readOnly: Bool; public var capabilities: Capabilities
    public var defaultCommand: String { status == "READY" ? "new_turn" : status == "WORKING" ? "follow_up" : status == "NEEDS_YOU" ? "answer" : "" }
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
        case "new_turn": return status == "READY" && capabilities.canSend
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
        switch kind { case "terminal": "Terminale"; case "tool": "MCP"; case "file": "File"; case "diff": "Diff"; case "assistant": state == "running" ? "Codex sta scrivendo" : "Risposta completata"; default: "Attività" }
    }
    public var detail: String { label.isEmpty ? title : title + " · " + label }
}
public struct Activity: Codable, Identifiable, Sendable, Equatable {
    public var id: String; public var kind: String; public var text: String; public var timestamp: String?; public var clientId: String?
    public var questions: [AsyncQuestion]?; public var truncated: Bool?
    public var state: String?; public var command: String?; public var exitCode: Int?; public var durationMs: Int?
    public var toolName: String?; public var toolServer: String?; public var files: [ChangedFile]?
    public var commandOutput: String {
        guard let command, !command.isEmpty else { return text }
        if text == command { return "" }
        if text.hasPrefix(command + "\n") { return String(text.dropFirst(command.count + 1)) }
        return text
    }
    public init(id: String, kind: String, text: String, timestamp: String? = nil, clientId: String? = nil, questions: [AsyncQuestion]? = nil, truncated: Bool? = nil) { self.id = id; self.kind = kind; self.text = text; self.timestamp = timestamp; self.clientId = clientId; self.questions = questions; self.truncated = truncated }
    public var contextBytes: Int { text.utf8.count + (questions ?? []).reduce(0) { $0 + $1.title.utf8.count + ($1.options ?? []).reduce(0) { $0 + $1.utf8.count } } + (command?.utf8.count ?? 0) + (toolName?.utf8.count ?? 0) + (toolServer?.utf8.count ?? 0) + (files ?? []).reduce(0) { $0 + $1.path.utf8.count + $1.kind.utf8.count + ($1.previousPath?.utf8.count ?? 0) + ($1.patch?.utf8.count ?? 0) } }
}
public struct AsyncQuestion: Codable, Sendable, Equatable {
    public let title: String; public let options: [String]?
    public init(title: String, options: [String]? = nil) { self.title = title; self.options = options }
}
public struct FollowUp: Codable, Sendable {
    public let id: String; public let clientId: String; public let text: String?
    public let editable: Bool?; public let revision: String?
}
public struct QuestionOption: Codable, Sendable { public let label: String; public let description: String }
public struct Question: Codable, Identifiable, Sendable { public let id: String; public let header: String; public let question: String; public let options: [QuestionOption]?; public let secret: Bool? }
public struct PendingRequest: Codable, Identifiable, Sendable {
    public var id: String { requestId }; public let requestId: String; public let sessionId: String; public let machineId: String
    public let kind: String; public let description: String; public let operation: String?; public let cwd: String?
    public let questions: [Question]?; public let expiresAt: String; public let canApprove: Bool
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
    public let liveActivity: LiveActivity?
    public let eventId: String?; public let kind: String; public let sessionId: String; public let session: RelaySession?
    public let request: PendingRequest?; public let requestId: String?; public let activity: Activity?
    public let text: String?; public let itemId: String?; public let turnId: String?; public let clientId: String?
    public let timestamp: String?; public let followUps: [FollowUp]?
}
public struct CommandResult: Decodable, Sendable {
    public let id: String; public let ok: Bool; public let error: String?; public let errorCode: String?; public let sessionId: String?
    public let history: [Activity]?; public let historyCursor: String?; public let followUps: [FollowUp]?
}
public struct WireMessage: Decodable, Sendable { public let type: String; public let snapshot: Snapshot?; public let event: RelayEvent?; public let result: CommandResult? }
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
        guard text.utf8.count <= 65_536 else { throw HubFailure.message("Risposta troppo grande (massimo 64 KiB).") }
        let value: JSONValue
        do { value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }
        catch { throw HubFailure.message("Inserisci una risposta JSON valida.") }
        guard value.object != nil else { throw HubFailure.message("La risposta MCP deve essere un oggetto JSON.") }
        try validate(value, schema: schema, path: "Risposta", depth: 0)
        return value
    }
    public static func fields(_ values: [String: String], schema: JSONValue) throws -> JSONValue {
        guard let properties = schema.object?["properties"]?.object else { return try parse("{}", schema: schema) }
        var content: [String: JSONValue] = [:]
        for (key, property) in properties {
            guard let text = values[key], !text.isEmpty else { continue }
            if let choices = property.object?["enum"]?.array {
                guard let choice = choices.first(where: { ($0.string ?? $0.pretty) == text }) else { throw HubFailure.message("\(key): scegli un valore previsto.") }
                content[key] = choice
            } else if property.object?["type"]?.string == "string" { content[key] = .string(text) }
            else {
                do { content[key] = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }
                catch { throw HubFailure.message("\(key): inserisci un valore valido per il tipo richiesto.") }
            }
        }
        return try parse(JSONValue.object(content).pretty, schema: schema)
    }
    private static func validate(_ value: JSONValue, schema: JSONValue, path: String, depth: Int) throws {
        func fail(_ reason: String) throws { throw HubFailure.message("\(path): \(reason)") }
        guard depth < 20 else { try fail("schema troppo annidato; usa Codex locale."); return }
        if schema == .bool(true) { return }
        if schema == .bool(false) { try fail("valore non consentito."); return }
        guard let s = schema.object else { try fail("schema non valido."); return }
        let unsupported = ["$ref", "$dynamicRef", "patternProperties", "dependentSchemas", "dependentRequired", "if", "then", "else", "prefixItems", "contains", "unevaluatedProperties", "unevaluatedItems"]
        if unsupported.contains(where: { s[$0] != nil }) { try fail("schema avanzato: risolvi questa richiesta da Codex locale.") }
        if let choices = s["enum"]?.array, !choices.contains(value) { try fail("valore non previsto dallo schema.") }
        if let constant = s["const"], constant != value { try fail("valore diverso da quello richiesto.") }
        if let types = s["type"] {
            let allowed = types.array?.compactMap(\.string) ?? types.string.map { [$0] } ?? []
            let type: String
            switch value { case .object: type = "object"; case .array: type = "array"; case .string: type = "string"; case .number: type = "number"; case .bool: type = "boolean"; case .null: type = "null" }
            let integer = value.number.map { $0.isFinite && $0.rounded() == $0 } ?? false
            if !allowed.contains(type) && !(integer && allowed.contains("integer")) { try fail("tipo richiesto: \(allowed.joined(separator: ", ")).") }
        }
        for sub in s["allOf"]?.array ?? [] { try validate(value, schema: sub, path: path, depth: depth+1) }
        for key in ["anyOf", "oneOf"] {
            if let alternatives = s[key]?.array {
                let matches = alternatives.filter { (try? validate(value, schema: $0, path: path, depth: depth+1)) != nil }.count
                if matches == 0 || (key == "oneOf" && matches != 1) { try fail("risposta non conforme alle alternative dello schema.") }
            }
        }
        if let negation = s["not"], (try? validate(value, schema: negation, path: path, depth: depth+1)) != nil { try fail("valore escluso dallo schema.") }
        if let object = value.object {
            for key in s["required"]?.array?.compactMap(\.string) ?? [] where object[key] == nil { try fail("manca il campo \(key).") }
            let properties = s["properties"]?.object ?? [:]
            for (key, field) in object {
                if let property = properties[key] { try validate(field, schema: property, path: path+"."+key, depth: depth+1) }
                else if s["additionalProperties"] == .bool(false) { try fail("campo non previsto: \(key).") }
                else if let extra = s["additionalProperties"], extra.object != nil { try validate(field, schema: extra, path: path+"."+key, depth: depth+1) }
            }
            if let min = s["minProperties"]?.number, Double(object.count) < min { try fail("troppi pochi campi.") }
            if let max = s["maxProperties"]?.number, Double(object.count) > max { try fail("troppi campi.") }
        }
        if let text = value.string {
            if let min = s["minLength"]?.number, Double(text.unicodeScalars.count) < min { try fail("testo troppo corto.") }
            if let max = s["maxLength"]?.number, Double(text.unicodeScalars.count) > max { try fail("testo troppo lungo.") }
            if let pattern = s["pattern"]?.string {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { try fail("pattern non compatibile; usa Codex locale."); return }
                if regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil { try fail("testo non conforme al pattern.") }
            }
        }
        if let number = value.number {
            if let min = s["minimum"]?.number, number < min { try fail("valore inferiore al minimo.") }
            if let max = s["maximum"]?.number, number > max { try fail("valore superiore al massimo.") }
            if let min = s["exclusiveMinimum"]?.number, number <= min { try fail("valore inferiore o uguale al limite.") }
            if let max = s["exclusiveMaximum"]?.number, number >= max { try fail("valore superiore o uguale al limite.") }
            if let step = s["multipleOf"]?.number {
                if step <= 0 || abs(number/step - (number/step).rounded()) > 1e-9 { try fail("valore non multiplo del passo richiesto.") }
            }
        }
        if let array = value.array {
            if let min = s["minItems"]?.number, Double(array.count) < min { try fail("troppi pochi elementi.") }
            if let max = s["maxItems"]?.number, Double(array.count) > max { try fail("troppi elementi.") }
            if s["uniqueItems"] == .bool(true), Set(array.map(\.pretty)).count != array.count { try fail("elementi duplicati.") }
            if let items = s["items"] {
                guard items.object != nil || items == .bool(true) || items == .bool(false) else { try fail("schema degli elementi non compatibile."); return }
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
        guard let date = formatter.date(from: hub) ?? ISO8601DateFormatter().date(from: hub) else { return }
        let ms = received.timeIntervalSince(date) * 1000
        guard ms >= 0, ms < 300_000 else { clockSkew = true; return }
        samples = min(samples + 1, 1024); hubToNativeMs = ms
    }
}
