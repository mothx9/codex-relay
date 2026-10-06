import XCTest
@testable import RelayCore

final class PendingIdentityTests: XCTestCase {
    private func request(created: String = "2026-10-06T10:00:00Z", payload: Bool = false) throws -> PendingRequest {
        var value: [String: Any] = ["request_id": "m~rpc-1", "session_id": "m~thread", "machine_id": "m", "kind": "mcp_elicitation", "description": "Choose a path", "expires_at": "2026-10-06T11:00:00Z", "can_approve": true, "created_at": created, "turn_id": "turn"]
        if payload { value["payload"] = ["input_schema": ["type": "object", "properties": ["path": ["type": "string"]]]] }
        return try RelayJSON.decoder().decode(PendingRequest.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func testStrippedFleetSnapshotKeepsWatchedFormAndIdentity() throws {
        let full = try request(payload: true)
        let snapshot = try request()
        let merged = snapshot.retainingContext(from: full)
        XCTAssertNotNil(merged.payload?.inputSchema)
        XCTAssertEqual(merged.presentationID, full.presentationID)
        XCTAssertEqual(merged.requestId, full.requestId)
        XCTAssertNotNil(snapshot.retainingContext(from: merged).payload?.inputSchema)
    }
    func testReusedRPCIdentityDoesNotInheritOldSchemaOrDraftIdentity() throws {
        let old = try request(payload: true)
        let new = try request(created: "2026-10-06T10:30:00Z")
        XCTAssertNotEqual(new.presentationID, old.presentationID)
        XCTAssertNil(new.retainingContext(from: old).payload)
    }
    func testResolutionSnapshotDoesNotResurrectCachedRequest() throws {
        let full = try request(payload: true)
        let previous = [full.id: full]
        let canonical: [PendingRequest] = []
        let merged = Dictionary(uniqueKeysWithValues: canonical.map { ($0.id, $0.retainingContext(from: previous[$0.id])) })
        XCTAssertTrue(merged.isEmpty)
    }
}
