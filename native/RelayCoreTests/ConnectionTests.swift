import XCTest
@testable import RelayCore

final class ConnectionTests: XCTestCase {
    func testConnectionFailuresExposeOnlySafeCategoryAndCode() {
        let privateURL = "https://private-host.example/api/ui?token=private-token"
        for (code, kind) in [(NSURLErrorCannotFindHost, ConnectionIssue.Kind.dns), (NSURLErrorCannotConnectToHost, .unreachable), (NSURLErrorTimedOut, .timeout), (NSURLErrorNotConnectedToInternet, .network), (NSURLErrorServerCertificateUntrusted, .tls)] {
            let error = NSError(domain: NSURLErrorDomain, code: code, userInfo: [NSLocalizedDescriptionKey: privateURL, NSURLErrorFailingURLStringErrorKey: privateURL])
            let issue = ConnectionIssue(error: error)
            XCTAssertEqual(issue.kind, kind)
            XCTAssertEqual(issue.code, code)
            XCTAssertFalse(issue.diagnostic.contains("private"))
            XCTAssertFalse(issue.title.contains("private"))
            XCTAssertFalse(issue.guidance.contains("private-host"))
        }
        XCTAssertEqual(ConnectionIssue(error: URLError(.badServerResponse), httpStatus: 401).kind, .authentication)
        XCTAssertEqual(ConnectionIssue(error: URLError(.badServerResponse), httpStatus: 503).kind, .hub)
        XCTAssertEqual(ConnectionIssue(kind: .snapshotTimeout).diagnostic, "snapshotTimeout")
    }
    func testOpenSocketWithoutSnapshotCannotStayConnectingForever() {
        var health = SocketHealth(now: 100)
        // TCP/WebSocket admission alone is insufficient; only canonical state
        // permits Live, even if the peer has sent other messages.
        XCTAssertEqual(health.action(now: 110), .idle)
        XCTAssertEqual(health.action(now: 129.9), .idle)
        XCTAssertEqual(health.action(now: 130), .reconnect)
    }
    func testSilentAdmittedSocketReconnectsAfterMissingPong() {
        var health = SocketHealth(now: 100)
        health.snapshotReceived()
        XCTAssertEqual(health.action(now: 110), .ping)
        XCTAssertEqual(health.action(now: 119.9), .idle)
        XCTAssertEqual(health.action(now: 120), .reconnect)
    }
    func testQuietHealthyFleetDoesNotRequireApplicationEventsToStayLive() {
        var health = SocketHealth(now: 100)
        health.snapshotReceived()
        for cycle in 0..<100 {
            let now = 110.0 + Double(cycle) * 11
            XCTAssertEqual(health.action(now: now), .ping)
            health.pongReceived(now: now + 1)
            XCTAssertEqual(health.action(now: now + 10), .idle)
        }
    }
    func testReconnectBackoffRemainsBoundedAfterLongOutage() {
        XCTAssertEqual(SocketHealth.retryDelay(attempt: 0, jitter: 0.5), 0.5)
        XCTAssertEqual(SocketHealth.retryDelay(attempt: 2, jitter: 1), 4)
        XCTAssertEqual(SocketHealth.retryDelay(attempt: 100, jitter: 1), 8)
        XCTAssertEqual(SocketHealth.retryDelay(attempt: 100, jitter: 0.5), 4)
    }
    func testLiveHandshakeRetainsOriginAndRequestScopedAuthentication() throws {
        let api = try HubAPI(url: "https://relay.example", token: "request-token")
        let request = api.socketRequest()
        XCTAssertEqual(request.url?.absoluteString, "wss://relay.example/api/ui")
        XCTAssertEqual(request.timeoutInterval, 30)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://relay.example")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer request-token")
        XCTAssertNil(try HubAPI(url: "https://relay.example").socketRequest().value(forHTTPHeaderField: "Authorization"))
    }
}
