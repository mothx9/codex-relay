import XCTest
@testable import RelayCore

final class RequestFormTests: XCTestCase {
    func json(_ text: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }
    func testCanonicalContextPreservesArbitraryMCPKeys() throws {
        let request = try RelayJSON.decoder().decode(PendingRequest.self, from: Data(#"{"request_id":"r","session_id":"m~t","machine_id":"m","kind":"mcp_elicitation","description":"Form","expires_at":"2027-01-01T00:00:00Z","can_approve":true,"payload":{"input_schema":{"type":"object","properties":{"snake_key":{"type":"string"},"camelKey":{"type":"boolean"}}}}}"#.utf8))
        let properties = request.payload?.inputSchema?.object?["properties"]?.object
        XCTAssertNotNil(properties?["snake_key"]); XCTAssertNotNil(properties?["camelKey"])
        let content = try MCPResponse.fields(["snake_key":"text", "camelKey":"false"], schema: request.payload!.inputSchema!)
        XCTAssertEqual(content.object?["snake_key"], .string("text")); XCTAssertEqual(content.object?["camelKey"], .bool(false))
        let wire = try JSONSerialization.data(withJSONObject: ["content":content.foundation])
        XCTAssertEqual(try json(String(decoding: wire, as: UTF8.self)).object?["content"], content)
    }
    func testRequiredTypedEnumBoundsAndAdditionalProperties() throws {
        let schema = try json(#"{"type":"object","required":["choice","count"],"additionalProperties":false,"properties":{"choice":{"type":"string","enum":["alpha","beta"]},"count":{"type":"integer","minimum":1,"maximum":3}}}"#)
        XCTAssertThrowsError(try MCPResponse.parse("{}",schema:schema))
        XCTAssertThrowsError(try MCPResponse.fields(["choice":"gamma","count":"2"],schema:schema))
        XCTAssertThrowsError(try MCPResponse.fields(["choice":"alpha","count":"2.5"],schema:schema))
        XCTAssertThrowsError(try MCPResponse.fields(["choice":"alpha","count":"4"],schema:schema))
        XCTAssertThrowsError(try MCPResponse.parse(#"{"choice":"alpha","count":1,"unexpected":true}"#,schema:schema))
        XCTAssertEqual(try MCPResponse.fields(["choice":"beta","count":"2"],schema:schema).object?["count"], .number(2))
    }
    func testNestedArraysPatternsAndUnsupportedSchemaFailClosed() throws {
        let schema = try json(#"{"type":"object","required":["paths"],"properties":{"paths":{"type":"array","minItems":1,"uniqueItems":true,"items":{"type":"string","pattern":"^/tmp/"}}}}"#)
        XCTAssertNoThrow(try MCPResponse.parse(#"{"paths":["/tmp/demo"]}"#,schema:schema))
        XCTAssertThrowsError(try MCPResponse.parse(#"{"paths":["/tmp/demo","/tmp/demo"]}"#,schema:schema))
        XCTAssertThrowsError(try MCPResponse.parse(#"{"paths":["/other"]}"#,schema:schema))
        XCTAssertThrowsError(try MCPResponse.parse("{}",schema:json(#"{"$ref":"external.json"}"#)))
        XCTAssertThrowsError(try MCPResponse.parse("[]",schema:.bool(true)))
        XCTAssertThrowsError(try MCPResponse.parse(String(repeating:" ",count:65_537),schema:.bool(true)))
    }
    func testPermissionPayloadCanBeReviewedWithoutLosingPaths() throws {
        let request = try RelayJSON.decoder().decode(PendingRequest.self, from: Data(#"{"request_id":"r","session_id":"m~t","machine_id":"m","kind":"permissions_approval","description":"Permission","expires_at":"2027-01-01T00:00:00Z","can_approve":true,"payload":{"permissions":{"network":{"enabled":true},"file_system":{"write":["/tmp/demo"]}}}}"#.utf8))
        XCTAssertEqual(request.payload?.permissions?.object?["file_system"]?.object?["write"], .array([.string("/tmp/demo")]))
    }
}
