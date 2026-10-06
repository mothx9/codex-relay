import XCTest
@testable import RelayCore
final class FreshnessTests: XCTestCase {
    func decode<T: Decodable>(_ text: String, as: T.Type = T.self) throws -> T { try RelayJSON.decoder().decode(T.self, from: Data(text.utf8)) }
    func testConnectionStatesPreserveLastKnownWork() throws {
        let session: RelaySession = try decode(#"{"id":"m~t","machine_id":"m","thread_id":"t","title":"test","project":"test","cwd":"/tmp","status":"WORKING","updated_at":"2026-10-07T00:00:00Z","read_only":false,"capabilities":{"can_send":false,"can_follow_up":true,"can_steer":true,"can_interrupt":true,"can_answer":false}}"#)
        for state in ["OFFLINE", "SYNCING", "DEGRADED", "RECONNECTING"] {
            let machine: Machine = try decode("{\"id\":\"m\",\"name\":\"Machine\",\"status\":\"\(state)\",\"last_seen\":\"2026-10-07T00:00:00Z\"}")
            XCTAssertEqual(session.displayStatus(machine: machine, connected: true), state)
            XCTAssertEqual(session.status, "WORKING")
            XCTAssertNotEqual(machine.connectionLabel(hubConnected: true), "Relay collegato")
        }
    }
    func testEpochSequenceAndSnapshotWatermark() throws {
        let machine: Machine = try decode(#"{"id":"m","name":"Machine","status":"ONLINE","last_seen":"2026-10-07T00:00:00Z","freshness":{"epoch":"new","sequence":4}}"#)
        var gate = EventFreshness(); gate.snapshot([machine])
        func event(_ epoch: String, _ sequence: Int) throws -> RelayEvent {
            try decode("{\"machine_id\":\"m\",\"session_id\":\"m~t\",\"kind\":\"session\",\"epoch\":\"\(epoch)\",\"sequence\":\(sequence)}")
        }
        XCTAssertFalse(gate.accept(try event("old", 100)))
        XCTAssertFalse(gate.accept(try event("new", 4)))
        XCTAssertTrue(gate.accept(try event("new", 6)))
        XCTAssertFalse(gate.accept(try event("new", 5)))
        XCTAssertFalse(gate.accept(try event("new", 6)))
    }
    func testCatalogueIsBoundedAndCannotReplaceCanonicalPending() throws {
        func session(_ i: Int, status: String = "INACTIVE") throws -> RelaySession {
            try decode("{\"id\":\"m~\(i)\",\"machine_id\":\"m\",\"thread_id\":\"\(i)\",\"title\":\"test\",\"project\":\"test\",\"cwd\":\"/tmp\",\"status\":\"\(status)\",\"updated_at\":\"2026-10-07T00:00:00Z\",\"read_only\":true,\"capabilities\":{\"can_send\":false,\"can_follow_up\":false,\"can_steer\":false,\"can_interrupt\":false,\"can_answer\":false}}")
        }
        var catalogue = SessionCatalogue()
        for page in 0..<12 {
            catalogue.apply(machine: "m", page: try (page*100..<(page+1)*100).map { try session($0) }, cursor: page == 11 ? nil : "next")
        }
        XCTAssertEqual(catalogue.sessions.count, 1024)
        XCTAssertTrue(catalogue.completed.contains("m"))
        let live = try session(1199, status: "NEEDS_YOU")
        XCTAssertEqual(catalogue.merged(canonical: [live.id: live])[live.id]?.status, "NEEDS_YOU")
        catalogue.restart(machine: "m")
        XCTAssertFalse(catalogue.completed.contains("m"))
        XCTAssertNil(catalogue.cursors["m"])
    }
    func testReceiptTimingIgnoresAbsentTimestampAndFlagsRealClockSkew() throws {
        let formatter = ISO8601DateFormatter()
        let received = try XCTUnwrap(formatter.date(from: "2026-10-07T00:00:01Z"))
        var timing = ReceiptTiming()
        timing.observe(hub: "0001-01-01T00:00:00Z", received: received, reduced: received)
        XCTAssertFalse(timing.clockSkew); XCTAssertEqual(timing.samples, 0)
        let event: RelayEvent = try decode(#"{"kind":"session","session_id":"m~t","hub_observed_at":"2026-10-07T00:00:00.750000000Z"}"#)
        timing.observe(hub: event.hubObservedAt, received: received, reduced: received.addingTimeInterval(0.002))
        XCTAssertEqual(timing.samples, 1); XCTAssertEqual(timing.hubToNativeMs, 250, accuracy: 0.1)
        XCTAssertEqual(timing.reducerMs, 2, accuracy: 0.1)
        timing.observe(hub: "2026-10-07T00:00:02Z", received: received, reduced: received)
        XCTAssertTrue(timing.clockSkew); XCTAssertEqual(timing.samples, 1)
    }
}
