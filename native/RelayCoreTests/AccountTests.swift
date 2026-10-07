import XCTest
@testable import RelayCore
final class AccountTests: XCTestCase {
    func testWindowsUseMetadataAndUnknownIsNotZero() throws {
        let account = try RelayJSON.decoder().decode(Account.self, from: Data(#"{"kind":"chatgpt","limits":{"primary":{"usedPercent":61,"windowDurationMins":300},"secondary":{"usedPercent":31,"windowDurationMins":10080}},"ordinary_usage_allowed":false}"#.utf8))
        XCTAssertEqual(account.limits?.primary?.label, "5-hour window")
        XCTAssertEqual(account.limits?.secondary?.label, "7-day window")
        XCTAssertNil(account.limits?.credits)
        XCTAssertEqual(account.ordinaryUsageAllowed, false)
        let missing = try RelayJSON.decoder().decode(Account.self, from: Data(#"{"kind":"apiKey"}"#.utf8))
        XCTAssertTrue(missing.usageBuckets.isEmpty)
        let unknown = try RelayJSON.decoder().decode(RateWindow.self, from: Data(#"{"usedPercent":120}"#.utf8))
        XCTAssertEqual(unknown.label, "Usage window")
        XCTAssertEqual(unknown.usedPercent, 120)
        XCTAssertEqual(unknown.fraction, 1)
    }
    func testBucketsDoNotDuplicateLegacyWindow() throws {
        let account = try RelayJSON.decoder().decode(Account.self, from: Data(#"{"kind":"chatgpt","limits":{"primary":{"usedPercent":10}},"buckets":{"codex":{"primary":{"usedPercent":10}},"fast":{"primary":{"usedPercent":20}}}}"#.utf8))
        XCTAssertEqual(account.usageBuckets.count, 2)
    }
}
