import XCTest
@testable import RelayCore

final class LocalizationTests: XCTestCase {
    func testItalianResourcesAndInterpolatedOperationalLabels() throws {
        let path = try XCTUnwrap(relayLocalizationBundle.path(forResource: "it", ofType: "lproj"))
        let italian = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(String(localized: "Working", bundle: italian), "In corso")
        XCTAssertEqual(String(localized: "Syncing with Codex…", bundle: italian), "Sincronizzazione Codex…")
        let count = 3
        XCTAssertEqual(String(localized: "\(count) running", bundle: italian), "3 in corso")
        XCTAssertEqual(String(localized: "\(count) files changed", bundle: italian), "3 file modificati")
        let percent = 61
        XCTAssertEqual(String(localized: "\(percent)% used", bundle: italian), "61% utilizzato")
        XCTAssertEqual(String(localized: "Copy Full Message", bundle: italian), "Copia messaggio completo")
    }
}
