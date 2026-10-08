import XCTest
@testable import RelayCore
final class DiagnosticsTests: XCTestCase {
    func testExportRedactsIdentitiesAndUnavailableMeasurements() throws {
        let raw = #"{"hub_version":"0.1.0","protocol_version":1,"transport":"unspecified","machines":[{"id":"PRIVATE_MACHINE","state":"OFFLINE","agent_version":"0.1.0","codex_version":"codex-cli 0.160.1","adapter":"PRIVATE_ADAPTER","last_seen":"2026-10-07T00:00:00Z","sessions":403,"hot":2,"pending":1,"freshness":{"epoch":"PRIVATE_EPOCH","connection_id":"PRIVATE_CONNECTION","last_disconnect_reason":"PRIVATE_REASON","sequence":10,"snapshot_sequence":9}}],"token":"SECRET_TOKEN","account":"PRIVATE_ACCOUNT"}"#
        let diagnostics = try RelayJSON.decoder().decode(RelayDiagnostics.self, from: Data(raw.utf8))
        let report = diagnostics.redactedReport(appVersion: "0.1.0", hubConnected: false)
        XCTAssertFalse(report.contains("PRIVATE")); XCTAssertFalse(report.contains("SECRET"))
        XCTAssertTrue(report.contains("OFFLINE")); XCTAssertTrue(report.contains("pending: 1"))
        XCTAssertTrue(report.contains("Snapshot ms: unavailable"))
        XCTAssertTrue(report.contains("watermark: 9"))
    }
}
