import XCTest
@testable import RelayCore

final class NotificationRoutingTests: XCTestCase {
    func testColdStartAndExpiredAuthenticationWaitForSnapshot() {
        var pending = PendingNavigation()
        pending.receive(.session("laptop~thread"))
        XCTAssertNil(pending.take(authenticated: false, snapshotReady: false))
        XCTAssertNil(pending.take(authenticated: true, snapshotReady: false))
        XCTAssertEqual(pending.take(authenticated: true, snapshotReady: true), .session("laptop~thread"))
        XCTAssertNil(pending.take(authenticated: true, snapshotReady: true))
    }
    func testLatestTapWinsAndContainsNoApprovalAction() {
        var pending = PendingNavigation()
        pending.receive(.session("old~thread"))
        pending.receive(.machine("workstation"))
        XCTAssertEqual(pending.take(authenticated: true, snapshotReady: true), .machine("workstation"))
        XCTAssertEqual(RelayDestination.notification(session: nil, machine: nil), .fleet)
    }
    func testLinksRejectCredentialsQueriesPathsAndMalformedIdentity() throws {
        for raw in ["https://session/m~t", "codex-relay://user@session/m~t", "codex-relay://session/m~t?approve=true", "codex-relay://session/m~t#approve", "codex-relay://session/m~../file", "codex-relay://session/m~t%0A", "codex-relay://session/m~t~x", "codex-relay://session/m~", "codex-relay://machine/../x"] {
            XCTAssertNil(RelayDestination.link(try XCTUnwrap(URL(string: raw))), raw)
        }
        XCTAssertEqual(RelayDestination.link(URL(string: "codex-relay://session/laptop~thread")!), .session("laptop~thread"))
        XCTAssertEqual(RelayDestination.link(URL(string: "codex-relay://machine/laptop")!), .machine("laptop"))
    }
}
