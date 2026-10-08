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
        let activityGroupID: String?
    }
    private func wait(_ seconds: TimeInterval = 30, _ condition: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: seconds), .completed)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<25 {
            if element.exists && element.isHittable { return }
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
    func testComposerRemainsVisibleWithContextualActions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--product-screenshot", "conversation", "-AppleLanguages", "(en)"]
        app.launch()
        let composer = app.descendants(matching: .any).matching(identifier: "composer.text").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(app.buttons["composer.stop"].frame.height, 48)
        let before = composer.frame
        app.buttons["composer.attach"].tap()
        XCTAssertTrue(app.buttons["Add photos"].waitForExistence(timeout: 5))
        XCTAssertTrue(composer.isHittable)
        XCTAssertEqual(composer.frame.minY, before.minY, accuracy: 2)
        XCTAssertFalse(app.buttons["Copy Session Link"].exists)
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Compact composer with persistent action panel"; capture.lifetime = .keepAlways; add(capture)
        app.buttons["composer.attach"].tap()
        composer.tap(); composer.typeText("Keep the draft.")
        XCTAssertEqual(app.buttons["composer.send"].label, "Send follow-up")
        app.buttons["composer.attach"].tap()
        XCTAssertTrue(composer.isHittable); XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.buttons["Add photos"].exists)
        XCTAssertFalse(app.buttons["Steer Current Turn"].exists)
        XCTAssertEqual(composer.value as? String, "Keep the draft.")
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
        XCTAssertTrue(app.buttons["composer.stop"].exists)
        composer.tap(); composer.typeText("Mantieni il testo corrente.")
        let send = app.buttons["composer.send"]
        XCTAssertEqual(send.label, "Send follow-up")
        XCTAssertTrue(send.isEnabled); XCTAssertTrue(send.isHittable)
        XCTAssertFalse(app.buttons["composer.dismissKeyboard"].exists)
        app.scrollViews["session.transcript"].swipeDown()
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
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "activity.commandExecution.preview-command-0").firstMatch.waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(composer.isHittable)
        XCTAssertEqual(composer.value as? String, "Mantieni il testo corrente.")
    }
    func testLiveProductNavigationAndHeartbeat() throws {
        guard let url = Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") else { throw XCTSkip("Requires a paired live Hub.") }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        app.buttons["navigation.relay"].tap()
        let machines = app.buttons["Machines"]
        XCTAssertTrue(machines.waitForExistence(timeout: 20)); machines.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "machine.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "M2 Machines live"; capture.lifetime = .keepAlways; add(capture)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Close"].tap()
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
        app.buttons["composer.attach"].tap()
        XCTAssertTrue(app.buttons["Add photos"].waitForExistence(timeout: 5))
        // Menu inspection only; no mutation of this real workload.
        app.terminate()
    }
    func testLiveQuestionDraftIsSeparateFromPendingInbox() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--product-screenshot", "live-question", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["session.liveQuestion"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Asked during this live turn"].exists)
        XCTAssertFalse(app.staticTexts["Reply using the live question above the composer."].exists)
        XCTAssertTrue(app.buttons["session.liveQuestion"].exists)
        XCTAssertFalse(app.staticTexts["question.example-async.0"].exists)
        XCTAssertFalse(app.staticTexts["activity.agentMessage.example-async"].exists)
        app.buttons["session.liveQuestion"].tap()
        let panel = app.navigationBars["Live question"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(panel.frame.minY, app.frame.height * 0.35, "A short question should preserve context above the sheet")
        app.buttons.containing(.staticText, identifier: "Full suite").firstMatch.tap()
        let composer = app.descendants(matching: .any).matching(identifier: "composer.text").firstMatch
        XCTAssertEqual(composer.value as? String, "Full suite")
        XCTAssertEqual(app.buttons["composer.send"].label, "Send Steer")
        XCTAssertFalse(app.buttons["Respond"].exists)
        // Preparing text never sends or resolves a request. History has no live action.
        app.terminate()
        app.launchArguments = ["--product-screenshot", "history-question", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.staticTexts["question.example-async.0"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Asked during this live turn"].exists)
        XCTAssertFalse(app.buttons.containing(.staticText, identifier: "Full suite").firstMatch.exists)
        XCTAssertFalse(app.buttons["Respond"].exists)
    }
    func testDraftRemainsEditableWhenLiveControlIsUnavailable() {
        let app = XCUIApplication()
        app.launchArguments = ["--product-screenshot", "draft-offline", "-AppleLanguages", "(en)"]
        app.launch()
        let composer = app.descendants(matching: .any).matching(identifier: "composer.text").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10)); XCTAssertTrue(composer.isEnabled)
        composer.tap(); composer.typeText("S"); composer.typeText("till writing while offline")
        XCTAssertEqual(composer.value as? String, "Still writing while offline")
        XCTAssertFalse(app.buttons["composer.send"].isEnabled)
    }
    func testQueuedSteerIsDirectAndPlusContainsOnlyAttachments() {
        let app = XCUIApplication()
        app.launchArguments = ["--product-screenshot", "queue", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["queue.steer.follow-next"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["queue.steer.follow-next"].isHittable)
        app.buttons["composer.attach"].tap()
        XCTAssertTrue(app.buttons["Add photos"].exists)
        XCTAssertFalse(app.buttons["Steer Current Turn"].exists)
        XCTAssertFalse(app.otherElements["composer.attachmentsMenu"].buttons["Interrupt Turn"].exists)
        XCTAssertFalse(app.buttons["Edit Last Queued Message"].exists)
        app.buttons["composer.attach"].tap()
        XCTAssertTrue(app.buttons["composer.stop"].exists)
    }
    func testFleetWorkingUsesOneCategoryLineWithoutCommandBody() {
        let app = XCUIApplication()
        app.launchArguments = ["--product-screenshot", "fleet", "-AppleLanguages", "(en)"]
        app.launch()
        let row = app.buttons["session.workstation~build"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Terminal")).firstMatch.exists)
        let source = row.staticTexts["session.source.workstation~build"]
        XCTAssertTrue(source.isHittable, "The title must not collapse the machine/project column")
        XCTAssertEqual(source.label, "Workstation · compiler")
        XCTAssertFalse(row.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "cargo test")).firstMatch.exists)
        row.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "cargo test")).firstMatch.waitForExistence(timeout: 10))
    }

    func testWorkingScrollsWithTranscriptAndComposerStaysVisible() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-chat", "--long-transcript", "-AppleLanguages", "(en)"]
        app.launch()
        let composer = app.descendants(matching: .any).matching(identifier: "composer.text").firstMatch
        let working = app.staticTexts["session.connection"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        wait(10) { working.isHittable }
        let transcript = app.scrollViews["session.transcript"]
        for _ in 0..<5 { if !working.isHittable { break }; transcript.swipeDown() }
        XCTAssertFalse(working.isHittable, "Working belongs to the latest messages, not the fixed composer")
        XCTAssertTrue(composer.isHittable)
        app.buttons["transcript.latest"].tap()
        wait(5) { working.isHittable }
    }

    func testAdministrativeHomesDoNotDuplicateSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--product-screenshot", "fleet", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["navigation.relay"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.buttons["Settings"].exists)
        app.buttons["navigation.relay"].tap()
        for label in ["Machines", "Codex Accounts", "Controllers & Access", "Diagnostics", "Settings"] { XCTAssertTrue(app.buttons[label].exists) }
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Notifications"].exists)
        for label in ["Machines", "Codex Accounts", "Controllers & Access", "Diagnostics"] { XCTAssertFalse(app.buttons[label].exists) }
    }
    func testOwnedLiveQuestionAttentionAndExpiry() throws {
        guard let url = Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") else { throw XCTSkip("Requires owned live validation thread") }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        guard config.sendTurn && config.sessionTitle == "Relay live attention acceptance" else { throw XCTSkip("Owned validation only") }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["navigation.relay"].waitForExistence(timeout: 20)); app.buttons["navigation.relay"].tap()
        app.buttons["Settings"].tap(); app.buttons["Notifications"].tap()
        if app.buttons["Allow notifications"].exists { app.buttons["Allow notifications"].tap() }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Allow"].waitForExistence(timeout: 2) { springboard.buttons["Allow"].tap() }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Close"].tap()
        app.tabBars.buttons["Needs You"].tap()
        print("LIVE_QUESTION_LISTENER_READY")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "live-question.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 100))
        XCTAssertTrue(app.staticTexts["Live questions"].exists)
        let banner = springboard.staticTexts["Codex asked a live question"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); capture.name = "Real Codex live question and local banner"; capture.lifetime = .keepAlways; add(capture)
        banner.tap() // Exercise the same safe deep link as a real notification tap.
        XCTAssertTrue(app.buttons["session.liveQuestion"].waitForExistence(timeout: 15))
        app.buttons["session.liveQuestion"].tap()
        let option = app.buttons.containing(.staticText, identifier: "Focused").firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 10)); option.tap()
        let composer = app.descendants(matching: .any).matching(identifier: "composer.text").firstMatch
        XCTAssertTrue((composer.value as? String ?? "").contains("Focused"))
        print("LIVE_QUESTION_OBSERVED")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Needs You"].tap()
        wait(40) { !row.exists }
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Needs You"].waitForExistence(timeout: 15)); app.tabBars.buttons["Needs You"].tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "live-question.")).firstMatch.exists)
        print("LIVE_QUESTION_RESTART_EMPTY")
    }
    func testLocalForegroundNotificationKindsAndDedupe() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--notification-acceptance", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["Allow notifications"].waitForExistence(timeout: 10))
        app.buttons["Allow notifications"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        XCTAssertTrue(app.staticTexts["Local alerts ready"].waitForExistence(timeout: 5))
        for (kind, title) in [("turn_completed", "Codex finished"), ("request", "Codex needs your input"), ("live_question", "Codex asked a live question"), ("failed", "Codex needs attention")] {
            app.buttons["notice." + kind].tap()
            let banner = springboard.staticTexts[title].firstMatch
            XCTAssertTrue(banner.waitForExistence(timeout: 5), "Missing native banner: " + title)
            XCTAssertTrue(springboard.staticTexts["Workstation · compiler"].exists)
            let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); capture.name = "local-banner-" + kind; capture.lifetime = .keepAlways; add(capture)
            wait(12) { !banner.exists }
            app.buttons["notice." + kind].tap()
            XCTAssertFalse(banner.waitForExistence(timeout: 2), "Duplicate semantic alert")
        }
        app.buttons["Read delivered alerts"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        print("DELIVERED_RECEIPT", app.staticTexts["notice.delivered"].label)
        XCTAssertTrue(app.staticTexts["notice.delivered"].label.contains("acceptance/failed"))
        // Dismissing the banner must leave the delivered notice in the system list.
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        top.press(forDuration: 0.1, thenDragTo: bottom)
        springboard.swipeDown()
        let retained = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        retained.name = "Local alerts retained in Notification Center"; retained.lifetime = .keepAlways; add(retained)
        XCTAssertTrue(springboard.staticTexts["Codex needs attention"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["Attention: 2"].waitForExistence(timeout: 5))
        app.buttons["Clear attention"].tap()
        XCTAssertTrue(app.staticTexts["Attention: 0"].exists)
        app.buttons["Disable alerts"].tap()
        XCTAssertTrue(app.staticTexts["Local alerts off"].exists)
    }
    func testOwnedImageReachesCodex() throws {
        guard let url = Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") else { throw XCTSkip("Requires a paired Hub and an owned image-validation thread.") }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        guard config.sendTurn && config.sessionTitle == "Relay input acceptance" else { throw XCTSkip("Requires an explicitly owned disposable image thread.") }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let search = app.textFields["fleet.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 20)); search.tap(); search.typeText(config.sessionTitle)
        let session = app.buttons["session." + config.sessionID]
        XCTAssertTrue(session.waitForExistence(timeout: 20)); session.tap()
        XCTAssertTrue(app.buttons["composer.attach"].waitForExistence(timeout: 15)); app.buttons["composer.attach"].tap()
        XCTAssertTrue(app.buttons["Add photos"].waitForExistence(timeout: 5)); app.buttons["Add photos"].tap()
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 15)); photo.tap(); app.navigationBars["Photos"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Remove image"].waitForExistence(timeout: 15))
        let composer = app.descendants(matching: .any).matching(identifier: "composer.text").firstMatch
        composer.tap(); composer.typeText("Reply with RELAY_IMAGE_COLOR followed by the dominant color of the attached image. Do not use tools or files.")
        app.buttons["composer.send"].tap()
        wait(90) { app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@ AND label CONTAINS[c] %@", "activity.agentMessage.", "RELAY_IMAGE_COLOR", "red")).firstMatch.exists }
        print("REAL_RELAY_IMAGE_RECOGNIZED")
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Image delivered through canonical Hub and Agent"; capture.lifetime = .keepAlways; add(capture)
    }

    func testOwnedQueueAndSteerStaySequential() throws {
        guard let url = Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") else { throw XCTSkip("Requires an owned control-validation thread.") }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        guard config.sendTurn && config.sessionTitle == "Relay input acceptance" else { throw XCTSkip("Owned validation only.") }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let search = app.textFields["fleet.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 20)); search.tap(); search.typeText(config.sessionTitle)
        let row = app.buttons["session." + config.sessionID]
        XCTAssertTrue(row.waitForExistence(timeout: 20)); row.tap()
        let composer = app.descendants(matching: .any).matching(identifier: "composer.text").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 15))
        let send = app.buttons["composer.send"]
        wait(15) { send.label == "Send" }
        composer.tap(); composer.typeText("Run only sleep 70, then say WAIT_FINISHED. No other tools or files."); send.tap()
        wait(30) { app.buttons["composer.stop"].exists }
        let marker = String(UUID().uuidString.prefix(8))
        let queued = "In the next turn reply only QUEUE_" + marker + ". No tools."
        composer.tap(); composer.typeText(queued); send.tap()
        wait(15) { app.staticTexts["FOLLOW-UP · QUEUED"].exists }
        let transcript = app.scrollViews["session.transcript"]
        XCTAssertFalse(transcript.staticTexts[queued].exists)
        let steer = "For the current turn finish with CURRENT_" + marker + ". Keep the next turn queued."
        composer.tap(); composer.typeText(steer); send.tap()
        wait(15) { app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'queue.steer.'")).count == 2 }
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'queue.steer.'")).element(boundBy: 1).tap()
        wait(30) { transcript.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'activity.userMessage.' AND label == %@", steer)).count == 1 }
        XCTAssertFalse(transcript.staticTexts[queued].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "FOLLOW-UP · QUEUED").count, 1)
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Real current-turn control with separate canonical queue"; capture.lifetime = .keepAlways; add(capture)
        wait(120) { transcript.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'activity.agentMessage.' AND label CONTAINS %@", "CURRENT_" + marker)).firstMatch.exists }
        wait(120) { transcript.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'activity.agentMessage.' AND label CONTAINS %@", "QUEUE_" + marker)).firstMatch.exists }
        XCTAssertEqual(transcript.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'activity.userMessage.' AND label == %@", queued)).count, 1)
        XCTAssertFalse(app.staticTexts["FOLLOW-UP · QUEUED"].exists)
        print("REAL_QUEUE_STEER_ORDER_CONFIRMED")
    }

    func testPhotoPickerImportsImageIntoComposer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--product-screenshot", "conversation", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["composer.attach"].waitForExistence(timeout: 10))
        app.buttons["composer.attach"].tap()
        app.buttons["Add photos"].tap()
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 15)); photo.tap()
        app.navigationBars["Photos"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Remove image"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["composer.send"].isEnabled)
        app.buttons["Remove image"].tap()
        XCTAssertTrue(app.buttons["composer.stop"].exists)
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); capture.name = "Native photo picker"; capture.lifetime = .keepAlways; add(capture)
    }

    func testQueueRemainsOutsideConversationAfterCanonicalSteer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--product-screenshot", "queue", "-AppleLanguages", "(en)"]
        app.launch()
        let queue = app.otherElements["session.queue"]
        XCTAssertTrue(app.staticTexts["Next up"].waitForExistence(timeout: 10))
        let transcript = app.scrollViews["session.transcript"]
        XCTAssertFalse(transcript.staticTexts["Then update the installation guide."].exists)
        XCTAssertTrue(app.staticTexts["Then update the installation guide."].isHittable)
        XCTAssertTrue(transcript.staticTexts["Keep the change limited to validation."].exists)
        let composer = app.descendants(matching: .any).matching(identifier: "composer.text").firstMatch
        XCTAssertLessThan(app.staticTexts["FOLLOW-UP · QUEUED"].frame.maxY, composer.frame.minY)
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Current-turn Steer and separate follow-up queue"; capture.lifetime = .keepAlways; add(capture)
        app.buttons["Edit queued message"].tap()
        XCTAssertEqual(composer.value as? String, "Then update the installation guide.")
        XCTAssertEqual(app.buttons["composer.send"].label, "Save queued message")
        _ = queue
    }

    func testExpandedActivityReplacesCollapsedPreview() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--product-screenshot", "conversation", "-AppleLanguages", "(en)"]
        app.launch()
        let group = app.buttons["tool.terminal.example-command"]
        XCTAssertTrue(group.waitForExistence(timeout: 10))
        let command = app.staticTexts.matching(NSPredicate(format: "label == %@", "cargo test --workspace"))
        XCTAssertEqual(command.count, 1)
        group.tap()
        XCTAssertEqual(command.count, 1, "Expansion must replace, not repeat, the collapsed command")
        XCTAssertFalse(app.buttons["activity.file.src/validation.rs"].exists)
        XCTAssertTrue(app.buttons["tool.details.terminal.example-command"].exists)
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Activity expanded without duplicate preview"; capture.lifetime = .keepAlways; add(capture)
        app.buttons["activity.item.example-tool"].tap()
        XCTAssertTrue(app.navigationBars["Operation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["The validation API rejects empty input and returns a typed error. Source: local API reference."].isHittable)
        XCTAssertFalse(app.staticTexts["cargo test --workspace"].isHittable)
        let detailCapture = XCTAttachment(screenshot: app.screenshot()); detailCapture.name = "One tool operation"; detailCapture.lifetime = .keepAlways; add(detailCapture)
        app.buttons["Close"].tap()
        group.tap()
        XCTAssertEqual(command.count, 1)
        XCTAssertTrue(app.buttons["activity.file.src/validation.rs"].exists)
    }
    func testActivityFilesAndAggregateHaveDistinctDestinations() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--product-screenshot", "activity-routing", "-AppleLanguages", "(en)"]
        app.launch()
        let files = app.buttons["activity.files.terminal.example-command"]
        XCTAssertTrue(files.waitForExistence(timeout: 10)); files.tap()
        XCTAssertTrue(app.navigationBars["Changed files"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["activity.path.src/validation.rs"].exists)
        XCTAssertTrue(app.buttons["activity.path.docs/validation.md"].exists)
        XCTAssertFalse(app.staticTexts["cargo test --workspace"].isHittable)
        app.buttons["activity.path.docs/validation.md"].tap()
        XCTAssertTrue(app.navigationBars["validation.md"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["+Empty inputs return a typed error."].exists)
        app.buttons["Close"].tap()
        // Collapsed operations route to themselves, just like expanded operations.
        app.buttons["activity.preview.example-command"].tap()
        XCTAssertTrue(app.navigationBars["Operation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Running integration checks")).firstMatch.exists)
        XCTAssertFalse(app.buttons["file.detail.docs/validation.md"].isHittable)
        app.buttons["Close"].tap()
        app.buttons["tool.terminal.example-command"].tap()
        app.buttons["tool.details.terminal.example-command"].tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["activity.aggregate.example-command"].exists)
        XCTAssertTrue(app.buttons["activity.aggregate.example-guide"].exists)
        XCTAssertFalse(app.buttons["activity.output.example-command"].exists)
        app.buttons["activity.aggregate.example-tool"].tap()
        XCTAssertTrue(app.navigationBars["Operation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["The validation API rejects empty input and returns a typed error. Source: local API reference."].exists)
    }

    func testWholeMessageCopyFromLastParagraph() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--product-screenshot", "conversation", "-AppleLanguages", "(en)"]
        app.launch()
        let paragraph = app.staticTexts["activity.agentMessage.example-code.2"]
        XCTAssertTrue(paragraph.waitForExistence(timeout: 10))
        paragraph.press(forDuration: 1)
        let copy = app.buttons["Copy Full Message"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5)); copy.tap()
        let composer = app.descendants(matching: .any).matching(identifier: "composer.text").firstMatch
        composer.tap(); composer.press(forDuration: 1)
        let paste = app.menuItems["Paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5)); paste.tap()
        let expected = "The guard keeps the failure explicit:\n\n```rust\nif input.is_empty() {\n    return Err(Error::EmptyInput);\n}\nrun_checks(input)?;\n```\n\nThe regression test has passed. Integration checks are still running."
        wait(5) { composer.value as? String == expected }
        app.terminate() // Never submit the draft.
    }

    func testCompactionAndDirectFileInspection() {
        let app = XCUIApplication()
        app.launchArguments = ["--product-screenshot", "compaction", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.staticTexts["session.connection"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["session.connection"].label, "Compacting context")
        XCTAssertTrue(app.staticTexts["context.compaction"].exists)
        let file = app.buttons["activity.file.src/validation.rs"]
        for _ in 0..<6 { if file.isHittable { break }; app.scrollViews["session.transcript"].swipeDown() }; XCTAssertTrue(file.isHittable); file.tap()
        XCTAssertTrue(app.navigationBars["validation.rs"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["1 event"].exists)
        XCTAssertTrue(app.staticTexts["+    if input.is_empty() {"].exists)
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Direct file diff"; capture.lifetime = .keepAlways; add(capture)
    }

    func testPublicProductWalkthrough() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--product-screenshot", "fleet", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["session.workstation~build"].waitForExistence(timeout: 10))
        let start = XCTAttachment(screenshot: app.screenshot()); start.name = "Public walkthrough start"; start.lifetime = .keepAlways; add(start)
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        app.buttons["session.workstation~build"].tap()
        XCTAssertTrue(app.buttons["composer.attach"].waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        app.buttons["composer.attach"].tap()
        XCTAssertTrue(app.buttons["Add photos"].exists)
        XCTAssertFalse(app.buttons["Steer Current Turn"].exists)
        XCTAssertFalse(app.otherElements["composer.attachmentsMenu"].buttons["Interrupt Turn"].exists)
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        app.buttons["composer.attach"].tap()
        let file = app.buttons["activity.file.src/validation.rs"]
        if !file.isHittable { app.scrollViews["session.transcript"].swipeDown() }
        XCTAssertTrue(file.isHittable); file.tap()
        XCTAssertTrue(app.navigationBars["validation.rs"].waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        app.buttons["Close"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Needs You"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Public walkthrough end"; capture.lifetime = .keepAlways; add(capture)
    }
    func testPublicProductScreenshots() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for surface in ["fleet", "conversation", "needs-you", "question", "terminal", "tools", "diff", "machines", "account", "settings", "diagnostics", "pairing", "navigation", "machine-diagnostics", "live-question", "live-inbox", "notifications", "compaction", "queue", "question-reply", "activity", "changed-files", "question-panel"] {
            app.launchArguments = ["--product-screenshot", surface == "question-panel" ? "live-question" : surface, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
            if surface == "pairing" {
                app.scrollViews.firstMatch.swipeDown()
                XCTAssertTrue(app.staticTexts["Your Codex fleet.\nOn iPhone."].isHittable)
            }
            if surface == "question-panel" {
                app.buttons["session.liveQuestion"].tap()
                XCTAssertTrue(app.navigationBars["Live question"].waitForExistence(timeout: 5))
            }
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
        app.buttons["navigation.relay"].tap()
        XCTAssertTrue(app.buttons["Controllers & Access"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["settings.hub"].exists)
        XCTAssertTrue(app.buttons["Notifications"].exists)
        XCTAssertFalse(app.buttons["Controllers & Access"].exists)
        XCTAssertFalse(app.buttons["Diagnostics"].exists)
        let settings = XCTAttachment(screenshot: app.screenshot()); settings.name = "M2 Settings"; settings.lifetime = .keepAlways; add(settings)
        app.navigationBars.buttons.element(boundBy: 0).tap()
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
        app.buttons["navigation.relay"].tap()
        let accounts = app.buttons["Codex Accounts"]
        XCTAssertTrue(accounts.waitForExistence(timeout: 10)); accounts.tap()
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "account.")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        let registry = XCTAttachment(screenshot: app.screenshot()); registry.name = "M2 actual Account Registry"; registry.lifetime = .keepAlways; add(registry)
        entry.tap()
        XCTAssertTrue(app.staticTexts["account.plan"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Updated"].exists)
        let relationship = app.buttons.containing(.staticText, identifier: "Used on").firstMatch
        reveal(relationship, in: app)
        XCTAssertTrue(relationship.exists)
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
        XCTAssertTrue(app.buttons["composer.stop"].exists)
        let marker = "RELAY_QUEUE_" + UUID().uuidString.prefix(8)
        let original = "Reply " + marker + "_ORIGINAL without tools."
        composer.tap(); composer.typeText(original); app.buttons["composer.send"].tap()
        XCTAssertTrue(app.staticTexts["FOLLOW-UP · QUEUED"].waitForExistence(timeout: 15))
        let edit = app.buttons["Edit queued message"].firstMatch
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
        wait(30) { app.buttons["composer.stop"].exists }
        let marker = "RELAY_STEER_" + UUID().uuidString.prefix(8)
        let text = "For this current turn, finish with exactly " + marker + ". Do not queue another turn."
        let composer = app.descendants(matching: .any).matching(identifier: "composer.text").firstMatch
        composer.tap(); composer.typeText(text)
        XCTAssertEqual(send.label, "Send follow-up"); send.tap()
        let steer = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "queue.steer.")).firstMatch
        XCTAssertTrue(steer.waitForExistence(timeout: 15)); wait(15) { steer.isEnabled }; steer.tap()
        let canonical = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'activity.userMessage.' AND label == %@", text))
        wait(60) { canonical.count == 1 }
        let response = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'activity.agentMessage.' AND label CONTAINS %@", marker))
        wait(120) { response.count > 0 }
        XCTAssertEqual(canonical.count, 1)
        XCTAssertFalse(app.staticTexts["FOLLOW-UP · QUEUED"].exists)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Owned current-turn Steer canonical response"; image.lifetime = .keepAlways; add(image)
        app.terminate()
    }
    func testOwnedMixedActivityGrouping() throws {
        guard let url = Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") else { throw XCTSkip("Owned activity only") }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        guard config.sendTurn, config.sessionTitle == "Relay grouped activity acceptance", let groupID = config.activityGroupID else { throw XCTSkip("Owned activity only") }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let search = app.textFields["fleet.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15)); search.tap(); search.typeText(config.sessionTitle)
        let row = app.buttons["session." + config.sessionID]
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        let group = app.buttons["tool." + groupID]
        XCTAssertTrue(group.waitForExistence(timeout: 20))
        let transcript = app.scrollViews["session.transcript"]
        for _ in 0..<8 { if group.isHittable { break }; transcript.swipeDown() }
        XCTAssertTrue(group.label.contains("2 commands")); XCTAssertTrue(group.label.contains("2 files changed"))
        let file = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'activity.file.' AND label == 'first.txt'")).firstMatch
        XCTAssertTrue(file.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Real grouped command file command file"; screenshot.lifetime = .keepAlways; add(screenshot)
        group.tap(); app.buttons["tool.details." + groupID].tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 10))
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'file.detail.' AND label CONTAINS 'first.txt'")).firstMatch
        reveal(first, in: app); XCTAssertTrue(first.exists)
        app.buttons["Close"].tap()
        file.tap(); XCTAssertTrue(app.navigationBars["first.txt"].waitForExistence(timeout: 5))
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
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tool.' AND NOT identifier BEGINSWITH 'tool.details.' AND NOT identifier BEGINSWITH 'tool.live.' AND NOT identifier BEGINSWITH 'tool.progress.'"))
        wait(20) { cards.count > 0 }
        var sawTool = false, sawFile = false
        for id in cards.allElementsBoundByIndex.map(\.identifier) {
            let card = app.buttons[id]
            for _ in 0..<12 { if card.isHittable { break }; transcript.swipeDown() }
            XCTAssertTrue(card.isHittable); card.tap()
            app.buttons["tool.details." + id.dropFirst(5)].tap()
            let tool = app.staticTexts["list_api_endpoints"]
            let file = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'file.detail.' AND label CONTAINS 'validation-marker.txt'")).firstMatch
            for _ in 0..<8 {
                sawTool = sawTool || tool.exists; sawFile = sawFile || file.exists
                if sawTool && sawFile { break }; app.swipeUp()
            }
            let detail = XCTAttachment(screenshot: app.screenshot()); detail.name = "Live owned operational detail"; detail.lifetime = .keepAlways; add(detail)
            app.buttons["Close"].tap()
            if sawTool && sawFile { break }
        }
        XCTAssertTrue(sawTool); XCTAssertTrue(sawFile)
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
        app.buttons["navigation.relay"].tap()
        app.buttons["Diagnostics"].tap()
        XCTAssertTrue(app.navigationBars["Diagnostics"].waitForExistence(timeout: 10))
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
        // Both the first and last Markdown paragraph actions
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
        let actions = try XCTUnwrap(paragraphs.allElementsBoundByIndex.first)
        for route in 0..<2 {
            let source = route == 0 ? try XCTUnwrap(lastParagraph) : actions
            for _ in 0..<24 {
                if source.isHittable { break }
                if source.exists && source.frame.minY > transcript.frame.maxY - 60 { transcript.swipeUp() }
                else { transcript.swipeDown() }
            }
            XCTAssertTrue(source.isHittable)
            source.press(forDuration: 1)
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
        app.buttons["navigation.relay"].tap()
        XCTAssertTrue(app.buttons["Diagnostics"].waitForExistence(timeout: 10))
        let settings = XCTAttachment(screenshot: app.screenshot()); settings.name = "Live Settings"; settings.lifetime = .keepAlways; add(settings)
        app.buttons["Diagnostics"].tap()
        XCTAssertTrue(app.navigationBars["Diagnostics"].waitForExistence(timeout: 10))
        for id in ["diagnostics.transport", "diagnostics.reducer"] {
            let row = app.descendants(matching: .any).matching(identifier: id).firstMatch
            reveal(row, in: app)
            XCTAssertTrue(row.exists)
        }
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Settings"].tap()
        app.buttons["Notifications"].tap()
        XCTAssertTrue(app.staticTexts["Local alerts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Remote push"].exists)
        let details = app.buttons["Delivery details"]; reveal(details, in: app); details.tap()
        XCTAssertTrue(app.staticTexts["iOS permission"].waitForExistence(timeout: 5))
        let registration = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Relay registration")).firstMatch
        reveal(registration, in: app)
        XCTAssertTrue(registration.exists)
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
        // Compact summaries can make a 40-item page fit entirely onscreen.
        // Load real earlier context so an upward reading gesture has scroll range.
        let earlier = app.buttons["history.older"]
        if earlier.isHittable {
            let count = transcript.value as? String
            earlier.tap()
            wait(20) { transcript.value as? String != count }
            let latest = app.buttons["transcript.latest"]
            XCTAssertTrue(latest.waitForExistence(timeout: 5)); latest.tap()
        }
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
        app.buttons["composer.attach"].tap()
        XCTAssertTrue(app.buttons["Add photos"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Steer Current Turn"].exists)
        app.buttons["composer.attach"].tap()
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
        wait { app.buttons["navigation.relay"].exists }
        app.buttons["navigation.relay"].tap()
        app.buttons["Machines"].tap()
        for machine in config.machineIDs { XCTAssertTrue(app.buttons["machine." + machine].exists) }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Close"].tap()
        // A process restart must recover the paired credential from Keychain.
        app.terminate(); app.launch()
        wait { app.buttons["navigation.relay"].exists }
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
