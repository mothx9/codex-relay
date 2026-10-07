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

extension NotificationRoutingTests {
    func testPermissionIsNotRemoteReadinessAndRegisteredRemoteSuppressesLocal() {
        var state = NotificationReadiness(); state.enabled = true; state.permission = true; state.connected = true
        XCTAssertTrue(state.localReady); XCTAssertFalse(state.remoteReady)
        state.hubConfigured = true; state.relayRegistered = true; state.registrationVerified = true
        XCTAssertTrue(state.remoteOwnsDelivery); XCTAssertFalse(state.remoteReady)
        state.appleRegistered = true; XCTAssertTrue(state.remoteReady)
        var policy = LocalNoticePolicy()
        XCTAssertFalse(policy.admit(SemanticNotice(key: "rpc", kind: .request), readiness: state, selectedSession: ""))
    }
    func testLocalSemanticDedupeCompletionSuppressionDisabledAndBounded() {
        var state = NotificationReadiness(); state.enabled = true; state.permission = true; state.connected = true
        var policy = LocalNoticePolicy()
        let done = SemanticNotice(key: "turn", kind: .completed, sessionID: "m~t")
        XCTAssertFalse(policy.admit(done, readiness: state, selectedSession: "m~t"))
        XCTAssertFalse(policy.admit(done, readiness: state, selectedSession: "other"))
        XCTAssertTrue(policy.admit(SemanticNotice(key: "rpc", kind: .request), readiness: state, selectedSession: "m~t"))
        XCTAssertFalse(policy.admit(SemanticNotice(key: "rpc", kind: .request), readiness: state, selectedSession: "m~t"))
        state.enabled = false
        XCTAssertFalse(policy.admit(SemanticNotice(key: "disabled", kind: .failed), readiness: state, selectedSession: ""))
        for n in 0..<1000 { _ = policy.admit(SemanticNotice(key: "\(n)", kind: .test), readiness: state, selectedSession: "") }
        XCTAssertEqual(policy.seen.count, 512)
    }
    func testOnlySemanticTurnCompletionNotItemCompletionProducesNotice() throws {
        func event(_ kind: String) throws -> RelayEvent {
            try RelayJSON.decoder().decode(RelayEvent.self, from: Data("{\"kind\":\"\(kind)\",\"session_id\":\"m~t\",\"turn_id\":\"turn\",\"notify_key\":\"canonical\"}".utf8))
        }
        XCTAssertNil(SemanticNotice.event(try event("activity")))
        XCTAssertEqual(SemanticNotice.event(try event("turn_completed"))?.key, "canonical")
        XCTAssertEqual(SemanticNotice.event(try event("failed"))?.kind, .failed)
    }
}

extension NotificationRoutingTests {
    func testNotificationContextUsesEventTurnAndCanBeHidden() throws {
        let session = try RelayJSON.decoder().decode(RelaySession.self, from: Data(#"{"id":"node~thread","machine_id":"node","thread_id":"thread","title":"Check empty input","project":"Validator","cwd":"/workspace","status":"WORKING","updated_at":"2026-10-07T12:00:00Z","turn_id":"newer-turn","read_only":false,"capabilities":{"can_send":false,"can_follow_up":true,"can_steer":true,"can_interrupt":true,"can_answer":false}}"#.utf8))
        let notice = SemanticNotice(key: "key", kind: .completed, sessionID: session.id, machineID: "node", turnID: "turn-12345678")
        let view = notice.presentation(machine: "GPU node", session: session, hideDetails: false)
        XCTAssertEqual(view.subtitle, "GPU node · Validator")
        XCTAssertEqual(view.body, "Check empty input · Turn 12345678")
        XCTAssertFalse(view.body.contains("newer-turn"))
        let hidden = notice.presentation(machine: "GPU node", session: session, hideDetails: true)
        XCTAssertEqual(hidden.subtitle, ""); XCTAssertFalse(hidden.body.contains(session.title))
        XCTAssertEqual(notice.presentation(machine: nil, session: nil, hideDetails: false).body, "node~thread · Turn 12345678")
    }
}
