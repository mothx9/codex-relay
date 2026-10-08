import XCTest
@testable import RelayCore

final class ConnectionTests: XCTestCase {
    func testOpenSocketWithoutSnapshotCannotStayConnectingForever() {
        var health = SocketHealth(now: 100)
        // TCP/WebSocket admission alone is insufficient; only canonical state
        // permits Live, even if the peer has sent other messages.
        XCTAssertEqual(health.action(now: 109.9), .idle)
        XCTAssertEqual(health.action(now: 110), .reconnect)
    }
    func testSilentAdmittedSocketReconnectsAfterMissingPong() {
        var health = SocketHealth(now: 100)
        health.snapshotReceived()
        XCTAssertEqual(health.action(now: 110), .ping)
        XCTAssertEqual(health.action(now: 114.9), .idle)
        XCTAssertEqual(health.action(now: 115), .reconnect)
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
        XCTAssertEqual(request.timeoutInterval, 10)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://relay.example")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer request-token")
        XCTAssertNil(try HubAPI(url: "https://relay.example").socketRequest().value(forHTTPHeaderField: "Authorization"))
    }
}
