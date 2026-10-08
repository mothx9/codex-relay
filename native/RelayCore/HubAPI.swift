import Foundation
public enum HubFailure: LocalizedError, Sendable {
    case message(String)
    case http(Int, String)
    public var errorDescription: String? { switch self { case .message(let text), .http(_, let text): return text } }
    public var authenticationRequired: Bool { if case .http(let code, _) = self { return code == 401 || code == 403 }; return false }
    public var retryable: Bool { if case .http(let code, _) = self { return [408, 425, 429].contains(code) || (500...599).contains(code) }; return false }
}

// URLSession error descriptions/userInfo can contain the Hub URL and request
// headers. Keep only a fixed category and numeric code for UI and diagnostics.
public struct ConnectionIssue: Sendable, Equatable {
    public enum Kind: String, Sendable { case network, dns, unreachable, timeout, tls, authentication, hub, protocolData, snapshotTimeout, pongTimeout }
    public let kind: Kind
    public let code: Int?
    public init(kind: Kind, code: Int? = nil) { self.kind = kind; self.code = code }
    public init(error: any Error, httpStatus: Int? = nil) {
        if let httpStatus, httpStatus != 101 {
            self.init(kind: [401, 403].contains(httpStatus) ? .authentication : .hub, code: httpStatus); return
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            let kind: Kind
            switch ns.code {
            case NSURLErrorNotConnectedToInternet: kind = .network
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: kind = .dns
            case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost: kind = .unreachable
            case NSURLErrorTimedOut: kind = .timeout
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid, NSURLErrorAppTransportSecurityRequiresSecureConnection: kind = .tls
            default: kind = .network
            }
            self.init(kind: kind, code: ns.code)
        } else { self.init(kind: .protocolData) }
    }
    public var diagnostic: String { kind.rawValue + (code.map { " (\($0))" } ?? "") }
    public var title: String {
        switch kind {
        case .network: String(localized: "Network unavailable", bundle: relayLocalizationBundle)
        case .dns: String(localized: "Hub address unavailable", bundle: relayLocalizationBundle)
        case .unreachable: String(localized: "Hub unreachable", bundle: relayLocalizationBundle)
        case .timeout, .snapshotTimeout, .pongTimeout: String(localized: "Hub connection timed out", bundle: relayLocalizationBundle)
        case .tls: String(localized: "Secure connection failed", bundle: relayLocalizationBundle)
        case .authentication: String(localized: "Hub access expired", bundle: relayLocalizationBundle)
        case .hub: String(localized: "Hub unavailable", bundle: relayLocalizationBundle)
        case .protocolData: String(localized: "Invalid Hub response", bundle: relayLocalizationBundle)
        }
    }
    public var guidance: String {
        switch kind {
        case .network, .dns, .unreachable, .timeout, .snapshotTimeout, .pongTimeout: String(localized: "Check the iPhone’s network and VPN if your Hub uses a private network. Relay retries automatically.", bundle: relayLocalizationBundle)
        case .tls: String(localized: "Check the Hub’s HTTPS certificate and the iPhone’s date. Certificate validation remains enabled.", bundle: relayLocalizationBundle)
        case .authentication: String(localized: "Pair this iPhone again with a new controller code.", bundle: relayLocalizationBundle)
        case .hub, .protocolData: String(localized: "Check the Hub service and version. Relay retries automatically.", bundle: relayLocalizationBundle)
        }
    }
}
public struct HubAPI: Sendable {
    // Reuse HTTPS connections instead of creating a separate TLS session for
    // every diagnostic/account request. Authentication stays request-scoped.
    private static let transport: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        return URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }()
    public let origin: URL; public let token: String?
    public init(url: String, token: String? = nil) throws {
        guard let components = URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines)), components.scheme == "https", let host = components.host, !host.isEmpty, components.user == nil, components.password == nil, components.query == nil, components.fragment == nil, ["", "/"].contains(components.path), let origin = components.url else { throw HubFailure.message(String(localized: "Enter the Hub’s HTTPS origin.", bundle: relayLocalizationBundle)) }
        self.origin = origin; self.token = token
    }
    public func request(path: String, body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: origin.appendingPathComponent(path)); request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(origin.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")), forHTTPHeaderField: "Origin")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpMethod = "POST"; request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.setValue("1", forHTTPHeaderField: "X-Relay-CSRF") }
        return request
    }
    public func socketRequest() -> URLRequest {
        var request = request(path: "api/ui"); var c = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!; c.scheme = "wss"; request.url = c.url; request.timeoutInterval = 30; return request
    }
    public func fetch<T: Decodable & Sendable>(_ path: String, body: [String: String]? = nil, as: T.Type = T.self) async throws -> T {
        let data = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        return try await perform(request(path: path, body: data), as: T.self)
    }
    public func post<T: Decodable & Sendable, Body: Encodable & Sendable>(_ path: String, body: Body, as: T.Type = T.self) async throws -> T {
        try await perform(request(path: path, body: RelayJSON.encoder().encode(body)), as: T.self)
    }
    private func perform<T: Decodable & Sendable>(_ request: URLRequest, as: T.Type) async throws -> T {
        let (result,response) = try await Self.transport.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let message = code == 401 ? String(localized: "Code expired or access revoked or invalid.", bundle: relayLocalizationBundle) : code == 429 ? String(localized: "Too many attempts. Wait a minute.", bundle: relayLocalizationBundle) : code == 409 ? String(localized: "Device already paired: revoke access before adding it again.", bundle: relayLocalizationBundle) : String(localized: "Hub unavailable (\(code)).", bundle: relayLocalizationBundle)
            throw HubFailure.http(code, message)
        }
        guard result.count <= 1_048_576 else { throw HubFailure.message(String(localized: "Hub response too large.", bundle: relayLocalizationBundle)) }
        return try RelayJSON.decoder().decode(T.self, from: result)
    }
}

// Monotonic timing: wall-clock changes cannot stall synchronization or keep a
// half-open socket falsely Live. Only a snapshot admits the controller stream.
public struct SocketHealth: Sendable {
    public enum Action: Sendable, Equatable { case idle, ping, reconnect }
    private let started: TimeInterval
    private var waitingForSnapshot = true
    private var pingSent: TimeInterval?
    private var nextPing: TimeInterval
    public init(now: TimeInterval) { started = now; nextPing = now + 10 }
    public mutating func snapshotReceived() { waitingForSnapshot = false }
    public mutating func pongReceived(now: TimeInterval) { pingSent = nil; nextPing = now + 10 }
    public mutating func action(now: TimeInterval) -> Action {
        // Cold mobile/VPN routing and TLS establishment need more headroom
        // than a warm simulator. Do not ping until the handshake is admitted.
        if waitingForSnapshot { return now - started >= 30 ? .reconnect : .idle }
        if let pingSent, now - pingSent >= 10 { return .reconnect }
        if pingSent == nil && now >= nextPing { pingSent = now; return .ping }
        return .idle
    }
    public static func retryDelay(attempt: Int, jitter: Double) -> TimeInterval {
        min(8, pow(2, Double(max(0, min(attempt, 3))))) * min(1, max(0.5, jitter))
    }
}
final class NoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    let onMetrics: (@Sendable (URLSessionTaskMetrics) -> Void)?
    init(onMetrics: (@Sendable (URLSessionTaskMetrics) -> Void)? = nil) { self.onMetrics = onMetrics }
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) { onMetrics?(metrics) }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
