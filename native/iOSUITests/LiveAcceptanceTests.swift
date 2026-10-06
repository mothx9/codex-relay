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
        let queued = app.staticTexts["FOLLOW-UP · IN CODA"]
        wait(10) { queued.isHittable }
        XCTAssertLessThanOrEqual(queued.frame.maxY, composer.frame.minY, "queued=\(queued.frame) composer=\(composer.frame) type=\(composer.elementType.rawValue)")
        let send = app.buttons["composer.send"]
        XCTAssertEqual(send.label, "Invia follow-up")
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
        XCTAssertTrue(app.staticTexts["activity.commandExecution.preview-command-0"].waitForExistence(timeout: 5))
        app.buttons["Chiudi"].tap()
        XCTAssertTrue(composer.isHittable)
        XCTAssertEqual(composer.value as? String, "Mantieni il testo corrente.")
    }
    func testLiveCataloguePaginationIsReadOnly() throws {
        guard let url = Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") else { throw XCTSkip("Requires the configured live fleet.") }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        guard !config.machineIDs.isEmpty else { throw XCTSkip("Requires configured machines.") }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap(); search.typeText("RELAY_NONEXISTENT_" + UUID().uuidString)
        app.swipeUp()
        for machine in config.machineIDs {
            let load = app.buttons["catalogue.load." + machine]
            XCTAssertTrue(load.waitForExistence(timeout: 10))
            for _ in 0..<8 {
                wait(15) { load.isEnabled }
                if load.label.contains("Rileggi cronologia") { break }
                load.tap()
                // Wait for the response without racing the next page's cursor.
                sleep(1)
            }
            wait(15) { load.label.contains("Rileggi cronologia") }
        }
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Live Codex catalogue pages completed"; capture.lifetime = .keepAlways; add(capture)
    }
    func testOwnedLiveTerminalAndQueueEdit() throws {
        guard let url = Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") else { throw XCTSkip("Requires one owned validation thread.") }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        guard config.sendTurn && config.sessionTitle == "Relay live validation" else { throw XCTSkip("Mutations only on the explicitly owned validation thread.") }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        let row = app.buttons["session." + config.sessionID]
        XCTAssertTrue(row.waitForExistence(timeout: 20)); row.tap()
        let attach = app.buttons["Collega thread"]
        if attach.waitForExistence(timeout: 3) { attach.tap() }
        let composer = app.descendants(matching: .any).matching(identifier: "composer.text").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 15))
        let live = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tool.live.")).firstMatch
        XCTAssertTrue(live.waitForExistence(timeout: 120), "Output must be visible while its command is running")
        XCTAssertTrue(live.label.contains("RELAY_PROGRESS_"))
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Actual output before command completion"; capture.lifetime = .keepAlways; add(capture)
        XCTAssertEqual(app.buttons["composer.send"].label, "Invia follow-up")
        let marker = "RELAY_QUEUE_" + UUID().uuidString.prefix(8)
        let original = "Reply " + marker + "_ORIGINAL without tools."
        composer.tap(); composer.typeText(original); app.buttons["composer.send"].tap()
        XCTAssertTrue(app.staticTexts["FOLLOW-UP · IN CODA"].waitForExistence(timeout: 15))
        app.buttons["Azioni della sessione"].tap()
        let edit = app.buttons["Modifica ultimo messaggio in coda"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); XCTAssertTrue(edit.isEnabled); edit.tap()
        XCTAssertEqual(composer.value as? String, original)
        composer.tap(); composer.typeText(" Reply " + marker + "_EDITED instead.")
        XCTAssertEqual(app.buttons["composer.send"].label, "Salva messaggio in coda")
        app.buttons["composer.send"].tap()
        wait(15) { !app.descendants(matching: .any)["composer.editingQueue"].exists }
        let edited = original + " Reply " + marker + "_EDITED instead."
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", edited)).count, 1)
        let queued = XCTAttachment(screenshot: app.screenshot()); queued.name = "Canonical queue edit same bubble"; queued.lifetime = .keepAlways; add(queued)
        let answer = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND identifier BEGINSWITH %@", marker + "_EDITED", "activity.agentMessage")).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 150))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", edited)).count, 1, "Canonical reconciliation must not duplicate the queued bubble")
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
        app.tabBars.buttons["Impostazioni"].tap()
        app.buttons["Connessione e diagnostica"].tap()
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
        XCTAssertTrue(app.staticTexts["Ultimo stato: In corso"].isHittable, "Stale state must remain visible at the recent end of a long conversation")
        let stale = XCTAttachment(screenshot: app.screenshot()); stale.name = "M1 offline last-known Working"; stale.lifetime = .keepAlways; add(stale)
        print("M1_OFFLINE_LAST_KNOWN_CONFIRMED")
        wait(45) { connection.value as? String == "Live" }
        XCTAssertFalse(app.staticTexts["Ultimo stato: In corso"].exists)
        let current = XCTAttachment(screenshot: app.screenshot()); current.name = "M1 reconnect current state"; current.lifetime = .keepAlways; add(current)
    }
    func testLiveCompleteMessageClipboard() throws {
        guard let url = Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") else { throw XCTSkip("Requires a canonical read-only copy target.") }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        guard let itemID = config.copyItemID, let expected = config.copyText else { throw XCTSkip("Requires canonical expected text.") }
        XCTAssertGreaterThanOrEqual(expected.components(separatedBy: "\n\n").count, 3)
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let search = app.searchFields.firstMatch
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
            let copy = app.buttons["Copia messaggio completo"]
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
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 15))
        let fleet = XCTAttachment(screenshot: app.screenshot()); fleet.name = "Live Fleet iPhone 16"; fleet.lifetime = .keepAlways; add(fleet)
        app.tabBars.buttons["Impostazioni"].tap()
        XCTAssertTrue(app.buttons["Connessione e diagnostica"].waitForExistence(timeout: 10))
        let settings = XCTAttachment(screenshot: app.screenshot()); settings.name = "Live Settings"; settings.lifetime = .keepAlways; add(settings)
        app.buttons["Connessione e diagnostica"].tap()
        for id in ["diagnostics.transport", "diagnostics.reducer"] {
            let row = app.descendants(matching: .any).matching(identifier: id).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            print("M1_NATIVE_TIMING", id, row.label, row.value ?? "")
        }
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Notifiche"].tap()
        XCTAssertTrue(app.staticTexts["Permesso iOS"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Registrazione Relay"].exists)
        let notifications = XCTAttachment(screenshot: app.screenshot()); notifications.name = "Live notification capability"; notifications.lifetime = .keepAlways; add(notifications)
    }
    func testLiveReadOnlyHistoryNavigation() throws {
        guard let url = Bundle(for: Self.self).url(forResource: "AcceptanceConfig", withExtension: "json") else {
            throw XCTSkip("Requires the paired Hub and a read-only history target.")
        }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap(); search.typeText(config.sessionTitle)
        let session = app.buttons["session." + config.sessionID]
        XCTAssertTrue(session.waitForExistence(timeout: 15)); session.tap()
        let composer = app.descendants(matching: .any).matching(identifier: "composer.text").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 15)); XCTAssertTrue(composer.isHittable)
        app.buttons["Azioni della sessione"].tap()
        let steer = app.buttons["Steer del turno corrente"]
        XCTAssertTrue(steer.waitForExistence(timeout: 5))
        if steer.isEnabled {
            steer.tap()
            XCTAssertTrue(app.buttons["composer.send"].label == "Invia Steer")
            app.buttons["Annulla"].tap()
        } else {
            app.buttons["Azioni della sessione"].tap()
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
        let before = older.value as? String
        older.tap()
        wait(15) { older.isEnabled && older.value as? String != before }
        XCTAssertTrue(composer.isHittable)
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Live canonical history pagination"; capture.lifetime = .keepAlways; add(capture)
        let prose = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "activity.agentMessage."))
        var paragraph = prose.allElementsBoundByIndex.first(where: { $0.isHittable })
        for _ in 0..<8 where paragraph == nil {
            transcript.swipeUp()
            paragraph = prose.allElementsBoundByIndex.first(where: { $0.isHittable })
        }
        if let paragraph {
            paragraph.press(forDuration: 1)
            let copy = app.buttons["Copia messaggio completo"]
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
                if activity.value as? String != "Dettagli aperti" { activity.tap() }
                let details = app.buttons[identity.replacingOccurrences(of: "tool.", with: "tool.details.")]
                for _ in 0..<8 {
                    if details.isHittable { break }
                    if details.exists && details.frame.minY < transcript.frame.minY { transcript.swipeDown() }
                    else { transcript.swipeUp() }
                }
                XCTAssertTrue(details.isHittable); details.tap()
                XCTAssertTrue(app.buttons["Chiudi"].waitForExistence(timeout: 5))
                let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Live " + kind; capture.lifetime = .keepAlways; add(capture)
                if kind == "terminal" {
                    app.buttons["Copia attività"].tap()
                    let copy = app.buttons["Copia tutti gli output"]
                    XCTAssertTrue(copy.waitForExistence(timeout: 5)); copy.tap()
                    app.buttons["Azioni output"].firstMatch.tap()
                    XCTAssertTrue(app.buttons["Copia output completo"].waitForExistence(timeout: 5))
                    app.buttons["Copia output completo"].tap()
                }
                app.buttons["Chiudi"].tap()
            }
        }
        // No attach, send, approval, interruption or other Codex mutation.
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
        wait { app.staticTexts["fleet.connection"].exists && app.staticTexts["fleet.connection"].label.contains("macchine online") }
        for machine in config.machineIDs {
            XCTAssertGreaterThan(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "session." + machine + "~")).count, 0)
        }
        // A process restart must recover the paired credential from Keychain.
        app.terminate(); app.launch()
        wait { app.staticTexts["fleet.connection"].exists && app.staticTexts["fleet.connection"].label.contains("macchine online") }
        XCTAssertFalse(app.textFields["pairing.url"].exists)
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText(config.sessionTitle)
        let session = app.buttons["session." + config.sessionID]
        XCTAssertTrue(session.waitForExistence(timeout: 15)); session.tap()
        guard config.sendTurn else { return }
        if app.buttons["Collega thread"].exists { app.buttons["Collega thread"].tap() }
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
        wait { app.staticTexts["session.connection"].exists && (app.staticTexts["session.connection"].value as? String) == "Live" }
        // Hub connectivity precedes the asynchronous Codex history response.
        wait { canonical.count == 1 }
        XCTAssertEqual(canonical.count, 1)
    }
}
