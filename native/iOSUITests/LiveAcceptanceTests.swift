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
        let copyItemID: String?
        let copyText: String?
        let expectEmptyInbox: Bool?
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
    func testLiveHistoryCannotCreateNeedsYou() throws {
        guard let url = Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") else { throw XCTSkip("Requires a paired live Hub.") }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        guard config.expectEmptyInbox == true else { throw XCTSkip("Requires independently confirmed empty canonical pending state.") }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let search = app.textFields["fleet.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 20)); search.tap(); search.typeText(config.sessionTitle)
        let session = app.buttons["session." + config.sessionID]
        XCTAssertTrue(session.waitForExistence(timeout: 15)); session.tap()
        XCTAssertTrue(app.scrollViews["session.transcript"].waitForExistence(timeout: 20))
        // Read real transcript pages; never answer, steer or interrupt this work.
        app.scrollViews["session.transcript"].swipeDown()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Needs You"].tap()
        XCTAssertTrue(app.staticTexts["No pending requests"].waitForExistence(timeout: 15))
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Live Inbox after historical question rollback"; capture.lifetime = .keepAlways; add(capture)
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Needs You"].waitForExistence(timeout: 15)); app.tabBars.buttons["Needs You"].tap()
        XCTAssertTrue(app.staticTexts["No pending requests"].waitForExistence(timeout: 15))
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
        let queued = app.staticTexts["FOLLOW-UP · QUEUED"]
        wait(10) { queued.isHittable }
        XCTAssertLessThanOrEqual(queued.frame.maxY, composer.frame.minY, "queued=\(queued.frame) composer=\(composer.frame) type=\(composer.elementType.rawValue)")
        let send = app.buttons["composer.send"]
        XCTAssertEqual(send.label, "Send follow-up")
        XCTAssertFalse(send.isEnabled)
        composer.tap(); composer.typeText("Mantieni il testo corrente.")
        XCTAssertTrue(send.isEnabled); XCTAssertTrue(send.isHittable)
        XCTAssertFalse(app.buttons["composer.dismissKeyboard"].exists)
        app.scrollViews.firstMatch.swipeDown()
        let terminal = app.buttons["tool.terminal.preview-command-0"]
        for _ in 0..<25 {
            if terminal.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(terminal.isHittable)
        XCTAssertTrue(composer.isHittable)
        terminal.tap()
        app.buttons["tool.details.terminal.preview-command-0"].tap()
        let output = app.buttons["activity.output.preview-command-0"]
        reveal(output, in: app)
        if output.value as? String == "Collapsed" { output.tap() }
        XCTAssertTrue(app.staticTexts["activity.commandExecution.preview-command-0"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(composer.isHittable)
        XCTAssertEqual(composer.value as? String, "Mantieni il testo corrente.")
    }
    func testLiveProductNavigationAndHeartbeat() throws {
        guard let url = Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") else { throw XCTSkip("Requires a paired live Hub.") }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let machines = app.buttons["fleet.connection"]
        XCTAssertTrue(machines.waitForExistence(timeout: 20)); machines.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "machine.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "M2 Machines live"; capture.lifetime = .keepAlways; add(capture)
        app.buttons["machines.close"].tap()
        let search = app.textFields["fleet.search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText(config.sessionTitle)
        let session = app.buttons["session." + config.sessionID]
        XCTAssertTrue(session.waitForExistence(timeout: 15)); session.tap()
        let composer = app.descendants(matching: .any).matching(identifier: "composer.text").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 15))
        let heartbeat = app.staticTexts["session.connection"]
        XCTAssertTrue(heartbeat.isHittable)
        XCTAssertLessThan(heartbeat.frame.maxY, composer.frame.minY)
        XCTAssertFalse(app.tabBars.firstMatch.isHittable)
        app.buttons["Session Info"].tap()
        XCTAssertTrue(app.staticTexts["Thread"].waitForExistence(timeout: 5)); app.buttons["Close"].tap()
        app.buttons["Session actions"].tap()
        XCTAssertTrue(app.buttons["Steer Current Turn"].waitForExistence(timeout: 5))
        // Menu inspection only; no mutation of this real workload.
        app.terminate()
    }
    func testPublicProductScreenshots() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for surface in ["fleet", "conversation", "needs-you", "question", "terminal", "tools", "diff", "machines", "account", "settings", "diagnostics", "pairing"] {
            app.launchArguments = ["--product-screenshot", surface, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "public-" + surface; screenshot.lifetime = .keepAlways; add(screenshot)
            if surface == "question" {
                XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Which validation scope should I use?")).count, 1)
                XCTAssertFalse(app.buttons["Respond"].isEnabled)
                app.buttons.containing(.staticText, identifier: "Full suite").firstMatch.tap()
                XCTAssertTrue(app.buttons["Respond"].isEnabled)
            }
            app.terminate()
        }
    }
    func testAppIconOnHomeScreen() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--preview-onboarding"]; app.launch()
        XCTAssertTrue(app.buttons["pairing.submit"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = home.icons["Codex Relay"]
        XCTAssertTrue(icon.waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: home.screenshot()); screenshot.name = "M2 app icon on iPhone 16 Home Screen"; screenshot.lifetime = .keepAlways; add(screenshot)
        icon.tap()
        XCTAssertTrue(app.buttons["pairing.submit"].waitForExistence(timeout: 10))
        app.terminate()
    }
    func testIsolatedOnboardingDoesNotTouchEnrollment() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--preview-onboarding"]; app.launch()
        XCTAssertTrue(app.staticTexts["One Hub"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Agents on your machines"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "M2 sanitized first-run onboarding"; screenshot.lifetime = .keepAlways; add(screenshot)
        let submit = app.buttons["pairing.submit"]
        XCTAssertFalse(submit.isEnabled)
        let url = app.textFields["pairing.url"]
        reveal(url, in: app); url.tap(); url.typeText("https://relay.invalid")
        let code = app.textFields["pairing.code"]
        reveal(code, in: app); code.tap(); code.typeText("12345678")
        XCTAssertTrue(submit.isEnabled); XCTAssertTrue(submit.isHittable)
        XCTAssertFalse(app.buttons["composer.dismissKeyboard"].exists)
        // No pairing request is submitted; the existing Keychain is never read or erased.
        app.terminate()
    }
    func testIsolatedItalianOnboardingAtLargeDynamicType() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--preview-onboarding", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Un Hub"].waitForExistence(timeout: 10))
        let submit = app.buttons["pairing.submit"]
        XCTAssertEqual(submit.label, "Abbina")
        XCTAssertLessThan(submit.frame.height, app.frame.height / 5)
        XCTAssertTrue(submit.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "M2 Italian onboarding large Dynamic Type"; screenshot.lifetime = .keepAlways; add(screenshot)
        XCTAssertFalse(app.staticTexts["One Hub"].exists)
        app.terminate()
    }
    func testLiveSettingsAndRedactedDiagnostics() throws {
        guard Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") != nil else { throw XCTSkip("Uses the existing paired controller without enrollment or mutations.") }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.textFields["fleet.search"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Controllers & Access"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["settings.hub"].exists)
        for label in ["Machines", "Codex Accounts", "Notifications", "Diagnostics"] { XCTAssertTrue(app.buttons[label].exists, label) }
        let settings = XCTAttachment(screenshot: app.screenshot()); settings.name = "M2 Settings"; settings.lifetime = .keepAlways; add(settings)
        app.buttons["Diagnostics"].tap()
        let copy = app.buttons["diagnostics.copy"]
        reveal(copy, in: app);
        XCTAssertTrue(copy.exists); wait(15) { copy.isEnabled }; copy.tap()
        XCTAssertEqual(copy.label, "Copied")
        let diagnostics = XCTAttachment(screenshot: app.screenshot()); diagnostics.name = "M2 Diagnostics"; diagnostics.lifetime = .keepAlways; add(diagnostics)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Controllers & Access"].tap()
        XCTAssertTrue(app.staticTexts["Authorized controllers"].waitForExistence(timeout: 10))
        let controllers = XCTAttachment(screenshot: app.screenshot()); controllers.name = "M2 Controllers"; controllers.lifetime = .keepAlways; add(controllers)
        // Never tap production revoke/remove/pause controls in acceptance tests.
    }
    func testLiveNotificationDeepLinks() throws {
        guard let configURL = Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") else { throw XCTSkip("Requires an existing paired Hub; no enrollment created.") }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: configURL))
        continueAfterFailure = false
        let app = XCUIApplication()
        app.terminate()
        let url = try XCTUnwrap(URL(string: "codex-relay://session/" + config.sessionID))
        app.open(url)
        XCTAssertTrue(app.buttons["Session Info"].waitForExistence(timeout: 30), "Cold URL launch must wait for the canonical snapshot")
        XCTAssertTrue(app.staticTexts["session.connection"].isHittable)
        let transcript = app.scrollViews["session.transcript"]
        wait(30) { let value = transcript.value as? String ?? ""; return !value.isEmpty && value != "0 items" }
        // The URL contains no form payload. Only canonical pending state can render a request.
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "M2 cold session deep link"; capture.lifetime = .keepAlways; add(capture)
        XCUIDevice.shared.press(.home)
        app.open(url)
        XCTAssertTrue(app.buttons["Session Info"].waitForExistence(timeout: 20))
        let machine = try XCTUnwrap(config.machineIDs.first)
        app.open(try XCTUnwrap(URL(string: "codex-relay://machine/" + machine)))
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15))
        let detail = XCTAttachment(screenshot: app.screenshot()); detail.name = "M2 machine notification destination"; detail.lifetime = .keepAlways; add(detail)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.textFields["fleet.search"].waitForExistence(timeout: 15))
    }
    func testLiveCodexAccountPresentation() throws {
        guard Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") != nil else { throw XCTSkip("Requires the paired Hub with account metadata.") }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.textFields["fleet.search"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Settings"].tap()
        let accounts = app.buttons["Codex Accounts"]
        XCTAssertTrue(accounts.waitForExistence(timeout: 10)); accounts.tap()
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "account.")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        let registry = XCTAttachment(screenshot: app.screenshot()); registry.name = "M2 actual Account Registry"; registry.lifetime = .keepAlways; add(registry)
        entry.tap()
        XCTAssertTrue(app.staticTexts["Plan"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Data"].exists)
        let detail = XCTAttachment(screenshot: app.screenshot()); detail.name = "M2 actual Codex Account"; detail.lifetime = .keepAlways; add(detail)
        // Only runtime-reported fields. No login, quota reset or account mutation.
    }
    func testLiveCataloguePaginationIsReadOnly() throws {
        guard let url = Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") else { throw XCTSkip("Requires the configured live fleet.") }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        guard !config.machineIDs.isEmpty else { throw XCTSkip("Requires configured machines.") }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let search = app.textFields["fleet.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap(); search.typeText("RELAY_NONEXISTENT_" + UUID().uuidString)
        app.swipeUp()
        for machine in config.machineIDs {
            let load = app.buttons["catalogue.load." + machine]
            XCTAssertTrue(load.waitForExistence(timeout: 10))
            for _ in 0..<8 {
                wait(15) { load.isEnabled }
                if load.label.contains("Reload history") { break }
                load.tap()
                // Wait for the response without racing the next page's cursor.
                sleep(1)
            }
            wait(15) { load.label.contains("Reload history") }
        }
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Live Codex catalogue pages completed"; capture.lifetime = .keepAlways; add(capture)
    }
    func testOwnedLiveTerminalAndQueueEdit() throws {
        guard let url = Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") else { throw XCTSkip("Requires one owned validation thread.") }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        guard config.sendTurn && config.sessionTitle == "Relay live validation" else { throw XCTSkip("Mutations only on the explicitly owned validation thread.") }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let search = app.textFields["fleet.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        let row = app.buttons["session." + config.sessionID]
        XCTAssertTrue(row.waitForExistence(timeout: 20)); row.tap()
        let attach = app.buttons["Connect thread"]
        if attach.waitForExistence(timeout: 3) { attach.tap() }
        let composer = app.descendants(matching: .any).matching(identifier: "composer.text").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 15))
        let live = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tool.live.")).firstMatch
        XCTAssertTrue(live.waitForExistence(timeout: 120), "Output must be visible while its command is running")
        XCTAssertTrue(live.label.contains("RELAY_PROGRESS_"))
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Actual output before command completion"; capture.lifetime = .keepAlways; add(capture)
        XCTAssertEqual(app.buttons["composer.send"].label, "Send follow-up")
        let marker = "RELAY_QUEUE_" + UUID().uuidString.prefix(8)
        let original = "Reply " + marker + "_ORIGINAL without tools."
        composer.tap(); composer.typeText(original); app.buttons["composer.send"].tap()
        XCTAssertTrue(app.staticTexts["FOLLOW-UP · QUEUED"].waitForExistence(timeout: 15))
        app.buttons["Session actions"].tap()
        let edit = app.buttons["Edit Last Queued Message"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); XCTAssertTrue(edit.isEnabled); edit.tap()
        XCTAssertEqual(composer.value as? String, original)
        composer.tap(); composer.typeText(" Reply " + marker + "_EDITED instead.")
        XCTAssertEqual(app.buttons["composer.send"].label, "Save queued message")
        app.buttons["composer.send"].tap()
        wait(15) { !app.descendants(matching: .any)["composer.editingQueue"].exists }
        let edited = original + " Reply " + marker + "_EDITED instead."
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", edited)).count, 1)
        let queued = XCTAttachment(screenshot: app.screenshot()); queued.name = "Canonical queue edit same bubble"; queued.lifetime = .keepAlways; add(queued)
        let answer = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND identifier BEGINSWITH %@", marker + "_EDITED", "activity.agentMessage")).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 150))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", edited)).count, 1, "Canonical reconciliation must not duplicate the queued bubble")
    }
    func testOwnedCurrentTurnSteer() throws {
        guard let url = Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") else { throw XCTSkip("Requires owned running turn.") }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        guard config.sendTurn && config.sessionTitle == "Relay live validation" else { throw XCTSkip("Owned validation only.") }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let search = app.textFields["fleet.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15)); search.tap(); search.typeText(config.sessionTitle)
        let row = app.buttons["session." + config.sessionID]
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        let send = app.buttons["composer.send"]
        wait(30) { send.label == "Send follow-up" }
        app.buttons["Session actions"].tap()
        let steer = app.buttons["Steer Current Turn"]
        XCTAssertTrue(steer.waitForExistence(timeout: 5)); XCTAssertTrue(steer.isEnabled); steer.tap()
        let marker = "RELAY_STEER_" + UUID().uuidString.prefix(8)
        let text = "For this current turn, finish with exactly " + marker + ". Do not queue another turn."
        let composer = app.descendants(matching: .any).matching(identifier: "composer.text").firstMatch
        composer.tap(); composer.typeText(text)
        XCTAssertEqual(send.label, "Send Steer"); send.tap()
        let canonical = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'activity.userMessage.' AND label == %@", text))
        wait(60) { canonical.count == 1 }
        let response = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'activity.agentMessage.' AND label CONTAINS %@", marker))
        wait(120) { response.count > 0 }
        XCTAssertEqual(canonical.count, 1)
        XCTAssertFalse(app.staticTexts["FOLLOW-UP · QUEUED"].exists)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Owned current-turn Steer canonical response"; image.lifetime = .keepAlways; add(image)
        app.terminate()
    }
    func testOwnedToolAndFilePresentation() throws {
        guard let url = Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") else { throw XCTSkip("Requires owned tool/file validation.") }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        guard config.sendTurn && config.sessionTitle == "Relay live validation" else { throw XCTSkip("Owned validation only.") }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let search = app.textFields["fleet.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15)); search.tap(); search.typeText(config.sessionTitle)
        let row = app.buttons["session." + config.sessionID]
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        let transcript = app.scrollViews["session.transcript"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 15))
        for kind in ["mcp", "changes"] {
            let matches = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tool." + kind + "."))
            wait(20) { matches.count > 0 }
            let card = matches.allElementsBoundByIndex.last!
            for _ in 0..<12 { if card.isHittable { break }; transcript.swipeDown() }
            XCTAssertTrue(card.isHittable); card.tap()
            app.buttons["tool.details." + card.identifier.dropFirst(5)].tap()
            let detail = XCTAttachment(screenshot: app.screenshot()); detail.name = "Live owned " + kind; detail.lifetime = .keepAlways; add(detail)
            if kind == "mcp" { XCTAssertTrue(app.staticTexts["list_api_endpoints"].exists) }
            else { XCTAssertTrue(app.staticTexts.matching(identifier: "validation-marker.txt").firstMatch.exists) }
            app.buttons["Close"].tap()
        }
        app.terminate()
    }
    func testOwnedPendingRequestAcrossSurfacesAndResolveElsewhere() throws {
        guard let url = Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") else { throw XCTSkip("Requires the owned request validation thread.") }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        guard config.sendTurn && config.sessionTitle == "Relay live validation" else { throw XCTSkip("Owned validation only.") }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let row = app.buttons["session." + config.sessionID]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Needs You"].exists)
        let fleet = XCTAttachment(screenshot: app.screenshot()); fleet.name = "Live Fleet Needs You"; fleet.lifetime = .keepAlways; add(fleet)
        row.tap()
        let question = app.staticTexts["Which validation marker?"]
        XCTAssertTrue(question.waitForExistence(timeout: 15))
        wait(10) { question.isHittable }
        let form = XCTAttachment(screenshot: app.screenshot()); form.name = "Actual pending question inline"; form.lifetime = .keepAlways; add(form)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Needs You"].tap()
        let inbox = app.buttons.containing(.staticText, identifier: config.sessionTitle).firstMatch
        XCTAssertTrue(inbox.waitForExistence(timeout: 10))
        let request = XCTAttachment(screenshot: app.screenshot()); request.name = "Actual cross-machine Needs You inbox"; request.lifetime = .keepAlways; add(request)
        inbox.tap(); XCTAssertTrue(question.waitForExistence(timeout: 10))
        print("NEEDS_YOU_INLINE_INBOX_CONFIRMED")
        wait(90) { !question.exists }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        wait(10) { !inbox.exists }
        app.tabBars.buttons["Settings"].tap()
        app.buttons["Diagnostics"].tap()
        for id in ["diagnostics.transport", "diagnostics.reducer"] {
            let timing = app.descendants(matching: .any).matching(identifier: id).firstMatch
            XCTAssertTrue(timing.waitForExistence(timeout: 5))
            print("M1_PENDING_NATIVE_TIMING", timing.label)
        }
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Needs You"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Needs You"].tap()
        XCTAssertFalse(app.buttons.containing(.staticText, identifier: config.sessionTitle).firstMatch.exists)
    }
    func testLiveLastKnownWorkingAcrossAgentSilence() throws {
        guard let url = Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") else { throw XCTSkip("Requires a paired read-only MacBook session.") }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        guard !config.sendTurn && config.sessionID.hasPrefix("macbook~") else { throw XCTSkip("Read-only MacBook observation only.") }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let row = app.buttons["session." + config.sessionID]
        XCTAssertTrue(row.waitForExistence(timeout: 30)); row.tap()
        let connection = app.staticTexts["session.connection"]
        wait(20) { connection.value as? String == "Live" }
        print("M1_AGENT_SILENCE_READY")
        wait(120) { connection.value as? String == "Offline" }
        XCTAssertTrue(app.staticTexts["Last known: Working"].isHittable, "Stale state must remain visible at the recent end of a long conversation")
        let stale = XCTAttachment(screenshot: app.screenshot()); stale.name = "M1 offline last-known Working"; stale.lifetime = .keepAlways; add(stale)
        print("M1_OFFLINE_LAST_KNOWN_CONFIRMED")
        wait(45) { connection.value as? String == "Live" }
        wait { !app.staticTexts["Last known: Working"].exists }
        let current = XCTAttachment(screenshot: app.screenshot()); current.name = "M1 reconnect current state"; current.lifetime = .keepAlways; add(current)
    }
    func testLiveCompleteMessageClipboard() throws {
        guard let url = Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") else { throw XCTSkip("Requires a canonical read-only copy target.") }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        guard let itemID = config.copyItemID, let expected = config.copyText else { throw XCTSkip("Requires canonical expected text.") }
        XCTAssertGreaterThanOrEqual(expected.components(separatedBy: "\n\n").count, 3)
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let search = app.textFields["fleet.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap(); search.typeText(config.sessionTitle)
        let row = app.buttons["session." + config.sessionID]
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        let transcript = app.scrollViews["session.transcript"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 15))
        let composer = app.descendants(matching: .any).matching(identifier: "composer.text").firstMatch
        // Both the last Markdown paragraph and the explicit message action
        // must copy the canonical source, not the focused text selection.
        let paragraphs = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "activity.agentMessage." + itemID + "."))
        for _ in 0..<30 {
            if paragraphs.count > 0 { break }
            transcript.swipeDown(velocity: .fast)
            let older = app.buttons["history.older"]
            if older.isHittable {
                let previous = older.value as? String
                older.tap()
                wait(15) { older.isEnabled && older.value as? String != previous }
            }
        }
        let lastParagraph = paragraphs.allElementsBoundByIndex.last
        let actions = app.buttons["message.actions." + itemID]
        for route in 0..<2 {
            let source = route == 0 ? try XCTUnwrap(lastParagraph) : actions
            for _ in 0..<24 {
                if source.isHittable { break }
                if source.exists && source.frame.minY > transcript.frame.maxY - 60 { transcript.swipeUp() }
                else { transcript.swipeDown() }
            }
            XCTAssertTrue(source.isHittable)
            if route == 0 { source.press(forDuration: 1) } else { source.tap() }
            let copy = app.buttons["Copy Full Message"]
            XCTAssertTrue(copy.waitForExistence(timeout: 5)); copy.tap()
            composer.tap(); composer.press(forDuration: 1)
            let paste = app.menuItems.matching(NSPredicate(format: "label IN %@", ["Paste", "Incolla"])).firstMatch
            XCTAssertTrue(paste.waitForExistence(timeout: 5)); paste.tap()
            let permission = app.buttons.matching(NSPredicate(format: "label IN %@", ["Allow Paste", "Consenti Incolla"])).firstMatch
            if permission.waitForExistence(timeout: 1) { permission.tap() }
            wait(5) { composer.value as? String == expected }
            print("CANONICAL_COPY_PASTE_MATCHED route=\(route) bytes=\(expected.utf8.count)")
            composer.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: expected.count))
            transcript.swipeDown()
        }
        // Never send the pasted text; terminating discards this local draft.
        app.terminate()
    }
    func testLiveReadOnlySettingsSurfaces() throws {
        guard Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") != nil else { throw XCTSkip("Requires a paired real Hub.") }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.textFields["fleet.search"].waitForExistence(timeout: 15))
        let fleet = XCTAttachment(screenshot: app.screenshot()); fleet.name = "Live Fleet iPhone 16"; fleet.lifetime = .keepAlways; add(fleet)
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Diagnostics"].waitForExistence(timeout: 10))
        let settings = XCTAttachment(screenshot: app.screenshot()); settings.name = "Live Settings"; settings.lifetime = .keepAlways; add(settings)
        app.buttons["Diagnostics"].tap()
        for id in ["diagnostics.transport", "diagnostics.reducer"] {
            let row = app.descendants(matching: .any).matching(identifier: id).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            print("M1_NATIVE_TIMING", id, row.label, row.value ?? "")
        }
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Notifications"].tap()
        XCTAssertTrue(app.staticTexts["iOS permission"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Relay registration"].exists)
        let notifications = XCTAttachment(screenshot: app.screenshot()); notifications.name = "Live notification capability"; notifications.lifetime = .keepAlways; add(notifications)
    }
    func testLiveReadingPositionSurvivesSmallScroll() throws {
        guard let url = Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") else { throw XCTSkip("Requires paired read-only live chat.") }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let search = app.textFields["fleet.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15)); search.tap(); search.typeText(config.sessionTitle)
        let row = app.buttons["session." + config.sessionID]
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        let transcript = app.scrollViews["session.transcript"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 15))
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tool.' AND NOT identifier BEGINSWITH 'tool.details.'"))
        wait(20) { cards.allElementsBoundByIndex.contains { $0.isHittable } }
        let anchor = try XCTUnwrap(cards.allElementsBoundByIndex.last(where: { $0.isHittable && $0.frame.midY > transcript.frame.minY + 60 }))
        let before = anchor.frame.minY
        let start = transcript.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: 55))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
        // A small deliberate move towards older messages must not snap back,
        // including after the finger is lifted and live activity changes.
        for _ in 0..<4 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            XCTAssertGreaterThan(anchor.frame.minY, before + 20, "Reading position snapped back to latest")
        }
        let composer = app.descendants(matching: .any).matching(identifier: "composer.text").firstMatch
        let reading = anchor.frame.minY
        composer.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(anchor.frame.minY, reading, accuracy: 20, "Keyboard opening moved the history being read")
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Live reading position with keyboard"; capture.lifetime = .keepAlways; add(capture)
        app.terminate()
    }
    func testLiveReadOnlyHistoryNavigation() throws {
        guard let url = Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") else {
            throw XCTSkip("Requires the paired Hub and a read-only history target.")
        }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let search = app.textFields["fleet.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap(); search.typeText(config.sessionTitle)
        let session = app.buttons["session." + config.sessionID]
        XCTAssertTrue(session.waitForExistence(timeout: 15)); session.tap()
        let composer = app.descendants(matching: .any).matching(identifier: "composer.text").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 15)); XCTAssertTrue(composer.isHittable)
        app.buttons["Session actions"].tap()
        let steer = app.buttons["Steer Current Turn"]
        XCTAssertTrue(steer.waitForExistence(timeout: 5))
        if steer.isEnabled {
            steer.tap()
            XCTAssertTrue(app.buttons["composer.send"].label == "Send Steer")
            app.buttons["Cancel"].tap()
        } else {
            app.buttons["Session actions"].tap()
        }
        let older = app.buttons["history.older"]
        let transcript = app.scrollViews["session.transcript"]
        wait(15) { older.exists && transcript.frame.height > 100 }
        transcript.swipeDown(velocity: .fast)
        for _ in 0..<12 {
            if older.isHittable { break }
            transcript.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(older.isHittable)
        let before = transcript.value as? String
        older.tap()
        wait(15) { transcript.value as? String != before }
        XCTAssertTrue(composer.isHittable)
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Live canonical history pagination"; capture.lifetime = .keepAlways; add(capture)
        let prose = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "activity.agentMessage."))
        var paragraph = prose.allElementsBoundByIndex.first(where: { $0.isHittable })
        for _ in 0..<30 where paragraph == nil {
            transcript.swipeUp()
            paragraph = prose.allElementsBoundByIndex.first(where: { $0.isHittable })
        }
        if let paragraph {
            paragraph.press(forDuration: 1)
            let copy = app.buttons["Copy Full Message"]
            XCTAssertTrue(copy.waitForExistence(timeout: 5)); copy.tap()
        } else { XCTFail("No real assistant paragraph available for whole-message copy acceptance") }
        for kind in ["changes", "terminal"] {
            let candidates = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tool." + kind + "."))
            var visible = candidates.allElementsBoundByIndex.first(where: { $0.isHittable })
            for _ in 0..<8 where visible == nil {
                transcript.swipeUp()
                visible = candidates.allElementsBoundByIndex.first(where: { $0.isHittable })
            }
            if let activity = visible {
                let identity = activity.identifier
                if activity.value as? String != "Details expanded" { activity.tap() }
                let details = app.buttons[identity.replacingOccurrences(of: "tool.", with: "tool.details.")]
                for _ in 0..<8 {
                    if details.isHittable { break }
                    if details.exists && details.frame.minY < transcript.frame.minY { transcript.swipeDown() }
                    else { transcript.swipeUp() }
                }
                XCTAssertTrue(details.isHittable); details.tap()
                XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
                let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Live " + kind; capture.lifetime = .keepAlways; add(capture)
                if kind == "terminal" {
                    app.buttons["Copy Activity"].tap()
                    let copy = app.buttons["Copy All Outputs"]
                    XCTAssertTrue(copy.waitForExistence(timeout: 5)); copy.tap()
                    let outputActions = app.buttons.matching(identifier: "Output actions").allElementsBoundByIndex.first { $0.isHittable }
                    XCTAssertNotNil(outputActions); outputActions?.tap()
                    XCTAssertTrue(app.buttons["Copy Available Output"].waitForExistence(timeout: 5))
                    app.buttons["Copy Available Output"].tap()
                }
                app.buttons["Close"].tap()
            }
        }
        // No attach, send, approval, interruption or other Codex mutation.
    }
    func testLiveKeychainFleetAndCanonicalTurn() throws {
        guard let url = Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") else {
            throw XCTSkip("Requires an owner-supplied live acceptance configuration and isolated thread.")
        }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        // The paired Keychain credential supplies the Hub origin; this test never enrolls.
        XCTAssertFalse(config.sessionID.isEmpty)
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let pairing = app.textFields["pairing.url"]
        if pairing.waitForExistence(timeout: 3) {
            throw XCTSkip("Live acceptance reuses one explicitly paired development controller. Pairing/security tests run against isolated temporary Hubs; never enroll a production controller per test run.")
        }
        wait { app.buttons["fleet.connection"].exists && app.buttons["fleet.connection"].label.contains("machines online") }
        app.buttons["fleet.connection"].tap()
        for machine in config.machineIDs { XCTAssertTrue(app.buttons["machine." + machine].exists) }
        app.buttons["machines.close"].tap()
        // A process restart must recover the paired credential from Keychain.
        app.terminate(); app.launch()
        wait { app.buttons["fleet.connection"].exists && app.buttons["fleet.connection"].label.contains("machines online") }
        XCTAssertFalse(app.textFields["pairing.url"].exists)
        let search = app.textFields["fleet.search"]
        search.tap(); search.typeText(config.sessionTitle)
        let session = app.buttons["session." + config.sessionID]
        XCTAssertTrue(session.waitForExistence(timeout: 15)); session.tap()
        guard config.sendTurn else { return }
        if app.buttons["Connect thread"].exists { app.buttons["Connect thread"].tap() }
        let composer = app.descendants(matching: .any).matching(identifier: "composer.text").firstMatch
        reveal(composer, in: app)
        let send = app.buttons["composer.send"]
        wait { send.exists && send.label == "Send" }
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
        wait(120) { reply.count > 0 && reply.firstMatch.isHittable }
        XCTAssertEqual(canonical.count, 1)
        // Background and foreground reconstruct the current Codex state.
        XCUIDevice.shared.press(.home); app.activate()
        wait { app.staticTexts["session.connection"].exists && (app.staticTexts["session.connection"].value as? String) == "Live" }
        // Hub connectivity precedes the asynchronous Codex history response.
        wait { canonical.count == 1 }
        XCTAssertEqual(canonical.count, 1)
    }
}
