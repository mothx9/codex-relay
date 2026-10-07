import Foundation
public enum HubFailure: LocalizedError, Sendable {
    case message(String)
    case http(Int, String)
    public var errorDescription: String? { switch self { case .message(let text), .http(_, let text): return text } }
    public var authenticationRequired: Bool { if case .http(let code, _) = self { return code == 401 || code == 403 }; return false }
    public var retryable: Bool { if case .http(let code, _) = self { return [408, 425, 429].contains(code) || (500...599).contains(code) }; return false }
}
public struct HubAPI: Sendable {
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
        var request = request(path: "api/ui"); var c = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!; c.scheme = "wss"; request.url = c.url; return request
    }
    public func fetch<T: Decodable & Sendable>(_ path: String, body: [String: String]? = nil, as: T.Type = T.self) async throws -> T {
        let data = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        return try await perform(request(path: path, body: data), as: T.self)
    }
    public func post<T: Decodable & Sendable, Body: Encodable & Sendable>(_ path: String, body: Body, as: T.Type = T.self) async throws -> T {
        try await perform(request(path: path, body: RelayJSON.encoder().encode(body)), as: T.self)
    }
    private func perform<T: Decodable & Sendable>(_ request: URLRequest, as: T.Type) async throws -> T {
        let delegate = NoRedirect()
        let config = URLSessionConfiguration.ephemeral; config.httpCookieStorage = nil; config.urlCache = nil
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil); defer { session.finishTasksAndInvalidate() }
        let (result,response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let message = code == 401 ? String(localized: "Code expired or access revoked or invalid.", bundle: relayLocalizationBundle) : code == 429 ? String(localized: "Too many attempts. Wait a minute.", bundle: relayLocalizationBundle) : code == 409 ? String(localized: "Device already paired: revoke access before adding it again.", bundle: relayLocalizationBundle) : String(localized: "Hub unavailable (\(code)).", bundle: relayLocalizationBundle)
            throw HubFailure.http(code, message)
        }
        guard result.count <= 1_048_576 else { throw HubFailure.message(String(localized: "Hub response too large.", bundle: relayLocalizationBundle)) }
        return try RelayJSON.decoder().decode(T.self, from: result)
    }
}
final class NoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
