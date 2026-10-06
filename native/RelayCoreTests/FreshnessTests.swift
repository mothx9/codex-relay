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
}
