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

extension AccountTests {
    func testCreditBalancePresentationDoesNotInventUnitsOrRoundPrecision() throws {
        func credits(_ value: String) throws -> AccountCredits {
            try RelayJSON.decoder().decode(AccountCredits.self, from: JSONSerialization.data(withJSONObject: ["has_credits": true, "unlimited": false, "balance": value]))
        }
        let expected = NSDecimalNumber(string: "12.123456789").description(withLocale: Locale.current)
        XCTAssertEqual(try credits("12.12345678900000").displayBalance, expected)
        XCTAssertEqual(try credits("unknown").displayBalance, "unknown")
        XCTAssertEqual(try credits("12 credits").displayBalance, "12 credits")
    }
}
