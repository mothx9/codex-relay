import Foundation

public struct Account: Codable, Sendable { public let kind: String; public let email: String?; public let plan: String? }
public struct Machine: Codable, Identifiable, Sendable {
    public let id: String; public let name: String; public let status: String
    public let codexVersion: String?; public let adapter: String?; public let lastSeen: String
    public let account: Account?
}
public struct Capabilities: Codable, Sendable {
    public var canSend: Bool; public var canFollowUp: Bool; public var canSteer: Bool; public var canInterrupt: Bool; public var canAnswer: Bool
    public init(canSend: Bool = false, canFollowUp: Bool = false, canSteer: Bool = false, canInterrupt: Bool = false, canAnswer: Bool = false) {
        self.canSend = canSend; self.canFollowUp = canFollowUp; self.canSteer = canSteer; self.canInterrupt = canInterrupt; self.canAnswer = canAnswer
    }
}
public struct RelaySession: Codable, Identifiable, Sendable {
    public let id: String; public let machineId: String; public let threadId: String
    public let title: String; public let project: String; public let cwd: String; public let branch: String?
    public var status: String; public let updatedAt: String; public var turnId: String?; public let turnStarted: String?
    public var readOnly: Bool; public var capabilities: Capabilities
    public var defaultCommand: String { status == "READY" ? "new_turn" : status == "WORKING" ? "follow_up" : status == "NEEDS_YOU" ? "answer" : "" }
    public func allows(_ kind: String) -> Bool {
        if kind == "answer" { return capabilities.canAnswer }
        if readOnly { return false }
        switch kind {
        case "new_turn": return status == "READY" && capabilities.canSend
        case "follow_up": return status == "WORKING" && capabilities.canFollowUp
        case "steer": return status == "WORKING" && !(turnId ?? "").isEmpty && capabilities.canSteer
        case "interrupt": return !(turnId ?? "").isEmpty && capabilities.canInterrupt
        default: return false
        }
    }
}
public struct Activity: Codable, Identifiable, Sendable {
    public var id: String; public var kind: String; public var text: String; public var timestamp: String?; public var clientId: String?
    public init(id: String, kind: String, text: String, timestamp: String? = nil, clientId: String? = nil) { self.id = id; self.kind = kind; self.text = text; self.timestamp = timestamp; self.clientId = clientId }
}
public struct FollowUp: Codable, Sendable { public let id: String; public let clientId: String; public let text: String? }
public struct QuestionOption: Codable, Sendable { public let label: String; public let description: String }
public struct Question: Codable, Identifiable, Sendable { public let id: String; public let header: String; public let question: String; public let options: [QuestionOption]?; public let secret: Bool? }
public struct PendingRequest: Codable, Identifiable, Sendable {
    public var id: String { requestId }; public let requestId: String; public let sessionId: String; public let machineId: String
    public let kind: String; public let description: String; public let operation: String?; public let cwd: String?
    public let questions: [Question]?; public let expiresAt: String; public let canApprove: Bool
}
public struct Snapshot: Decodable, Sendable { public let machines: [Machine]; public let sessions: [RelaySession]; public let requests: [PendingRequest] }
public struct RelayEvent: Decodable, Sendable {
    public let eventId: String?; public let kind: String; public let sessionId: String; public let session: RelaySession?
    public let request: PendingRequest?; public let requestId: String?; public let activity: Activity?
    public let text: String?; public let itemId: String?; public let turnId: String?; public let clientId: String?
    public let timestamp: String?; public let followUps: [FollowUp]?
}
public struct CommandResult: Decodable, Sendable {
    public let id: String; public let ok: Bool; public let error: String?; public let errorCode: String?; public let sessionId: String?
    public let history: [Activity]?; public let followUps: [FollowUp]?
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
