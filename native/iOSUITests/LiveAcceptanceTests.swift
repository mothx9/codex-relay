import XCTest

// Supply AcceptanceConfig.json only in the built test bundle. Never add a real
// origin, OTP, credential or thread identity to the repository.
@MainActor final class LiveAcceptanceTests: XCTestCase {
    private struct Config: Decodable {
        let origin: String
        let code: String
        let machineIDs: [String]
        let sessionID: String
        let sessionTitle: String
        let sendTurn: Bool
    }
    private func wait(_ seconds: TimeInterval = 30, _ condition: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: seconds), .completed)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<25 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
    func testIsolatedChatComposerAndToolDetails() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--preview-chat", "--long-transcript"]
        app.launch()
        let composer = app.descendants(matching: .any).matching(identifier: "composer.text").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        XCTAssertTrue(composer.isHittable)
        XCTAssertTrue(app.staticTexts["question.preview-question.0"].exists)
        wait(10) { app.staticTexts["FOLLOW-UP · IN CODA"].isHittable }
        let send = app.buttons["composer.send"]
        XCTAssertEqual(send.label, "Invia follow-up")
        XCTAssertFalse(send.isEnabled)
        composer.tap(); composer.typeText("Mantieni il testo corrente.")
        XCTAssertTrue(send.isEnabled); XCTAssertTrue(send.isHittable)
        let done = app.buttons["composer.dismissKeyboard"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        let terminal = app.buttons["tool.terminal.preview-command-0"]
        for _ in 0..<25 {
            if terminal.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(terminal.isHittable)
        XCTAssertTrue(composer.isHittable)
        terminal.tap()
        XCTAssertTrue(app.staticTexts["activity.commandExecution.preview-command-0"].waitForExistence(timeout: 5))
        app.buttons["Chiudi"].tap()
        XCTAssertTrue(composer.isHittable)
        XCTAssertEqual(composer.value as? String, "Mantieni il testo corrente.")
    }
    func testLivePairingKeychainFleetAndCanonicalTurn() throws {
        guard let url = Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") else {
            throw XCTSkip("Requires an owner-supplied live acceptance configuration and isolated thread.")
        }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        XCTAssertEqual(URL(string: config.origin)?.scheme, "https")
        XCTAssertFalse(config.sessionID.isEmpty)
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let pairing = app.textFields["pairing.url"]
        if pairing.waitForExistence(timeout: 3) {
            pairing.tap(); pairing.typeText(config.origin)
            let code = app.textFields["pairing.code"]
            code.tap(); code.typeText(config.code)
            app.buttons["pairing.submit"].tap()
        }
        wait { app.staticTexts["fleet.connection"].exists && app.staticTexts["fleet.connection"].label.hasPrefix("Live") }
        for machine in config.machineIDs {
            XCTAssertGreaterThan(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "session." + machine + "~")).count, 0)
        }
        // A process restart must recover the paired credential from Keychain.
        app.terminate(); app.launch()
        wait { app.staticTexts["fleet.connection"].exists && app.staticTexts["fleet.connection"].label.hasPrefix("Live") }
        XCTAssertFalse(app.textFields["pairing.url"].exists)
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText(config.sessionTitle)
        let session = app.buttons["session." + config.sessionID]
        XCTAssertTrue(session.waitForExistence(timeout: 15)); session.tap()
        if app.buttons["Collega thread"].exists { app.buttons["Collega thread"].tap() }
        guard config.sendTurn else { return }
        let composer = app.descendants(matching: .any).matching(identifier: "composer.text").firstMatch
        reveal(composer, in: app)
        let send = app.buttons["composer.send"]
        wait { send.exists && send.label == "Invia" }
        let marker = "native-acceptance-" + UUID().uuidString
        let text = "Reply with exactly " + marker + ". Do not use tools or modify files."
        composer.tap(); composer.typeText(text)
        wait { send.isEnabled }
        reveal(send, in: app); send.tap()
        let canonical = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'activity.userMessage.' AND label == %@", text))
        wait(90) { canonical.count == 1 }
        let optimistic = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'outbox.' AND label == %@", text))
        XCTAssertEqual(optimistic.count, 0)
        let reply = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'activity.agentMessage.' AND label CONTAINS %@", marker))
        wait(120) { reply.count > 0 }
        XCTAssertEqual(canonical.count, 1)
        // Background and foreground reconstruct the current Codex state.
        XCUIDevice.shared.press(.home); app.activate()
        wait { app.staticTexts["session.connection"].exists && app.staticTexts["session.connection"].label.contains("Live") }
        // Hub connectivity precedes the asynchronous Codex history response.
        wait { canonical.count == 1 }
        XCTAssertEqual(canonical.count, 1)
    }
}
