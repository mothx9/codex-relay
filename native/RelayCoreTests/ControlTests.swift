import XCTest
@testable import RelayCore
final class ControlTests: XCTestCase {
    func decode<T: Decodable>(_ text: String, as: T.Type = T.self) throws -> T { try RelayJSON.decoder().decode(T.self, from: Data(text.utf8)) }
    func testCanonicalSubmitAndSteerCapability() throws {
        var session: RelaySession = try decode(#"{"id":"m~t","machine_id":"m","thread_id":"t","title":"test","project":"test","cwd":"/tmp","status":"READY","updated_at":"2026-10-06T00:00:00Z","read_only":false,"capabilities":{"can_send":true,"can_follow_up":true,"can_steer":true,"can_interrupt":true,"can_answer":false}}"#)
        XCTAssertEqual(session.defaultCommand, "new_turn"); XCTAssertTrue(session.allows("new_turn"))
        session.status = "WORKING"; XCTAssertEqual(session.defaultCommand, "follow_up"); XCTAssertTrue(session.allows("follow_up")); XCTAssertFalse(session.allows("steer"))
        session.turnId = "active"; XCTAssertTrue(session.allows("steer")); session.capabilities.canSteer = false; XCTAssertFalse(session.allows("steer"))
        session.status = "NEEDS_YOU"; XCTAssertEqual(session.defaultCommand, "answer"); XCTAssertFalse(session.allows("follow_up"))
    }
    func testConnectivityOverridesStaleWorkingStatus() throws {
        let session: RelaySession = try decode(#"{"id":"m~t","machine_id":"m","thread_id":"t","title":"test","project":"test","cwd":"/tmp","status":"WORKING","updated_at":"2026-10-06T00:00:00Z","read_only":false,"capabilities":{"can_send":false,"can_follow_up":true,"can_steer":true,"can_interrupt":true,"can_answer":false}}"#)
        let offline: Machine = try decode(#"{"id":"m","name":"Machine","status":"OFFLINE","last_seen":"2026-10-06T00:00:00Z"}"#)
        let online: Machine = try decode(#"{"id":"m","name":"Machine","status":"ONLINE","last_seen":"2026-10-06T00:00:00Z"}"#)
        XCTAssertEqual(session.displayStatus(machine: offline, connected: true), "OFFLINE")
        XCTAssertEqual(session.displayStatus(machine: online, connected: false), "OFFLINE")
        XCTAssertEqual(session.displayStatus(machine: nil, connected: true), "OFFLINE")
        XCTAssertEqual(session.displayStatus(machine: online, connected: true), "WORKING")
        XCTAssertEqual(online.connectionLabel(hubConnected: true), "Relay connected")
        XCTAssertEqual(offline.connectionLabel(hubConnected: true, access: "PAUSED"), "Relay paused")
        XCTAssertEqual(offline.connectionLabel(hubConnected: true), "Relay not connected")
        XCTAssertEqual(online.connectionLabel(hubConnected: false), "Hub not connected")
        XCTAssertEqual(offline.connectionLabel(hubConnected: true, access: "REVOKED"), "Relay access revoked")
    }
    func testQueuedPromotionKeepsIdentityImagesAndRejectsLateQueueResurrection() throws {
        var box = Outbox()
        let image = ImageInput(data: Data([1, 2, 3]))
        _ = try box.add(id: "selected", session: "m~t", kind: "follow_up", text: "now", images: [image])
        let selected: FollowUp = try decode(#"{"id":"queue","client_id":"selected","text":"now","revision":"one","image_count":1}"#)
        let later: FollowUp = try decode(#"{"id":"later-queue","client_id":"later","text":"later","revision":"two"}"#)
        box.queue(session: "m~t", entries: [selected, later])
        box.beginQueueSteer("selected", turn: "active")
        box.queue(session: "m~t", entries: [selected, later])
        XCTAssertEqual(box.items.first?.phase, .steering)
        let result: CommandResult = try decode(#"{"id":"operation","ok":true,"queue_removed":true}"#)
        box.queueSteerResult("selected", result: result)
        box.queue(session: "m~t", entries: [selected, later])
        XCTAssertEqual(box.pending(session: "m~t").map(\.id), ["later"])
        XCTAssertEqual(box.conversation(session: "m~t").map(\.id), ["selected"])
        XCTAssertEqual(box.images(session: "m~t", clientID: "selected"), [image])
        box.materialize(session: "m~t", activity: Activity(id: "canonical", kind: "userMessage", text: "now", clientId: "selected"))
        box.queueSteerResult("selected", result: result)
        box.queue(session: "m~t", entries: [selected, later])
        XCTAssertTrue(box.conversation(session: "m~t").isEmpty)
        XCTAssertEqual(box.items.filter { $0.id == "selected" }.count, 1)
    }
    func testRemovedQueueFailureRetainsTextAndUncertainDeleteNeverResends() throws {
        for removed in [false, true] {
            var box = Outbox()
            let queued: FollowUp = try decode(#"{"id":"queue","client_id":"client","text":"keep text","revision":"one"}"#)
            box.queue(session: "m~t", entries: [queued]); box.beginQueueSteer("client", turn: "active")
            let result: CommandResult = try decode(removed ? #"{"id":"op","ok":false,"queue_removed":true,"error_code":"TURN_CHANGED","error":"turn changed"}"# : #"{"id":"op","ok":false,"error_code":"UNKNOWN_OUTCOME","error":"unknown"}"#)
            box.queueSteerResult("client", result: result)
            XCTAssertEqual(box.items.first?.text, "keep text")
            XCTAssertEqual(box.items.first?.phase, removed ? .failed : .unconfirmed)
            XCTAssertEqual(box.items.first?.kind, removed ? "steer" : "follow_up")
        }
    }
    func testQueueAckDoesNotCompleteAndCanonicalIdentityReconciles() throws {
        var box = Outbox(); let id = try box.add(id: "client", session: "m~t", kind: "follow_up", text: "later")
        XCTAssertEqual(box.items[0].phase, .local); box.sending(id); XCTAssertEqual(box.items[0].phase, .sending)
        let ack: CommandResult = try decode(#"{"id":"client","ok":true,"queue_id":"native-queue"}"#); box.result(ack)
        XCTAssertEqual(box.items[0].queueId, "native-queue"); XCTAssertEqual(box.items[0].phase, .queued); XCTAssertEqual(box.visible(session: "m~t").first?.text, "later")
        box.disconnected(); XCTAssertEqual(box.items[0].phase, .queued)
        box.dispatched(session: "m~t", clientId: id); XCTAssertEqual(box.items[0].phase, .dispatched)
        let item = Activity(id: "canonical", kind: "userMessage", text: "later", clientId: id)
        box.materialize(session: "m~t", activity: item); box.result(ack); XCTAssertTrue(box.visible(session: "m~t").isEmpty); XCTAssertEqual(box.items[0].phase, .materialized); XCTAssertEqual(box.items[0].text, "")
        var chat = RecentChat(); chat.put(item); chat.put(item); XCTAssertEqual(chat.items.count, 1)
    }
    func testFailedSteerAndUnknownOutcomeNeverRequeue() throws {
        var box = Outbox(); let id = try box.add(id: "steer", session: "m~t", kind: "steer", text: "keep text", expectedTurn: "original-turn"); box.sending(id)
        let error: CommandResult = try decode(#"{"id":"steer","ok":false,"error_code":"TURN_CHANGED","error":"Il turno è cambiato."}"#)
        box.result(error); XCTAssertEqual(box.items[0].text, "keep text"); XCTAssertEqual(box.items[0].kind, "steer"); XCTAssertEqual(box.items[0].phase, .failed)
        XCTAssertEqual(box.items[0].expectedTurn, "original-turn")
        let next = try box.add(session: "m~t", kind: "follow_up", text: "unknown"); box.sending(next); box.disconnected()
        XCTAssertEqual(box.items.last?.errorCode, "UNKNOWN_OUTCOME"); XCTAssertEqual(box.items.last?.text, "unknown")
        let emptyAfterRestart = Outbox(); XCTAssertTrue(emptyAfterRestart.items.isEmpty)
    }
    func testCanonicalQueueEditUpdatesOneBubbleAndDoesNotResurrectDispatchedMessage() throws {
        var box = Outbox()
        let original: FollowUp = try decode(#"{"id":"queue","client_id":"client","text":"original","editable":true,"revision":"old"}"#)
        box.queue(session: "m~t", entries: [original])
        let edited: FollowUp = try decode(#"{"id":"queue","client_id":"client","text":"corrected","editable":true,"revision":"new"}"#)
        box.queue(session: "m~t", entries: [edited])
        XCTAssertEqual(box.items.count, 1)
        XCTAssertEqual(box.items[0].text, "corrected")
        XCTAssertEqual(box.items[0].queueId, "queue")
        XCTAssertEqual(box.items[0].queueRevision, "new")
        XCTAssertTrue(box.items[0].queueEditable)
        box.materialize(session: "m~t", activity: Activity(id: "canonical", kind: "userMessage", text: "corrected", clientId: "client"))
        box.queue(session: "m~t", entries: [original])
        XCTAssertTrue(box.visible(session: "m~t").isEmpty)
    }
    func testCanonicalBeforeQueueCannotResurrectAndQueueIsSeparateFromSteer() throws {
        var box = Outbox()
        box.materialize(session: "m~t", activity: Activity(id: "real", kind: "userMessage", text: "old", clientId: "already-executed"))
        let stale: FollowUp = try decode(#"{"id":"q-old","client_id":"already-executed","text":"old"}"#)
        let next: FollowUp = try decode(#"{"id":"q-next","client_id":"next","text":"do this later","editable":true}"#)
        box.queue(session: "m~t", entries: [stale, next])
        let steer = try box.add(id: "steer", session: "m~t", kind: "steer", text: "do this now", expectedTurn: "active")
        box.sending(steer)
        XCTAssertEqual(box.pending(session: "m~t").map(\.id), ["next"])
        XCTAssertEqual(box.conversation(session: "m~t").map(\.id), ["steer"])
        box.materialize(session: "m~t", activity: Activity(id: "steer-real", kind: "userMessage", text: "do this now", clientId: steer))
        XCTAssertEqual(box.pending(session: "m~t").map(\.id), ["next"])
        XCTAssertTrue(box.conversation(session: "m~t").isEmpty)
        box.queue(session: "m~t", entries: [])
        XCTAssertEqual(box.pending(session: "m~t").first?.phase, .unconfirmed)
        XCTAssertFalse(box.pending(session: "m~t").first!.queueEditable)
        box.materialize(session: "m~t", activity: Activity(id: "next-real", kind: "userMessage", text: "do this later", clientId: "next"))
        box.queue(session: "m~t", entries: [next])
        XCTAssertTrue(box.pending(session: "m~t").isEmpty)
    }

    func testImagesRemainBoundedAndRetainedAcrossUnknownOutcome() throws {
        var box = Outbox()
        let image = ImageInput(data: Data(repeating: 1, count: ImageInput.maxBytes))
        XCTAssertThrowsError(try box.add(session: "m~t", kind: "follow_up", text: "", images: [image, image, image]))
        let id = try box.add(session: "m~t", kind: "steer", text: "inspect", images: [image], expectedTurn: "active")
        box.sending(id); box.disconnected()
        XCTAssertEqual(box.items[0].errorCode, "UNKNOWN_OUTCOME")
        XCTAssertEqual(box.items[0].images, [image])
        box.materialize(session: "m~t", activity: Activity(id: "real", kind: "userMessage", text: "inspect", clientId: id))
        XCTAssertTrue(box.visible(session: "m~t").isEmpty)
        XCTAssertEqual(box.images(session: "m~t", clientID: id), [image])
        for n in 0..<8 { _ = try box.add(id: "i\(n)", session: "m~t", kind: "follow_up", text: "", images: [image, image]) }
        XCTAssertTrue(box.images(session: "m~t", clientID: id).isEmpty)
        XCTAssertThrowsError(try box.add(session: "m~t", kind: "follow_up", text: "", images: [image]))
    }

    func testBoundedMemoryAndTTL() throws {
        var box = Outbox(); for _ in 0..<32 { _ = try box.add(session: "m~t", kind: "follow_up", text: "pending", now: Date(timeIntervalSince1970: 1)) }
        XCTAssertThrowsError(try box.add(session: "m~t", kind: "follow_up", text: "overflow")); box.prune(active: "", now: Date(timeIntervalSince1970: 302)); XCTAssertTrue(box.items.isEmpty)
        var chat = RecentChat(); for i in 0..<2200 { chat.put(Activity(id: "\(i)", kind: "agentMessage", text: String(repeating: "x", count: 16384))) }
        XCTAssertLessThanOrEqual(chat.items.count, RecentChat.maxItems); XCTAssertLessThanOrEqual(chat.items.reduce(0) { $0 + $1.text.utf8.count }, RecentChat.maxBytes); XCTAssertTrue(chat.trimmed)
    }
    func testPairingRequestAndHTTPSBoundary() throws {
        XCTAssertThrowsError(try HubAPI(url: "http://relay.local")); XCTAssertThrowsError(try HubAPI(url: "https://token@relay.local")); XCTAssertThrowsError(try HubAPI(url: "https://relay.local/path"))
        let api = try HubAPI(url: "https://relay.local", token: "device")
        let req = api.request(path: "api/pairing/exchange", body: Data("{}".utf8)); XCTAssertEqual(req.value(forHTTPHeaderField: "Origin"), "https://relay.local"); XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer device"); XCTAssertEqual(req.value(forHTTPHeaderField: "X-Relay-CSRF"), "1")
        XCTAssertEqual(api.socketRequest().url?.absoluteString, "wss://relay.local/api/ui")
    }
    func testTemporaryHubFailureRetriesWithoutTreatingItAsRevokedAccess() {
        for code in [408, 425, 429, 500, 502, 503, 504] {
            let error = HubFailure.http(code, "Temporary failure")
            XCTAssertTrue(error.retryable); XCTAssertFalse(error.authenticationRequired)
        }
        for code in [401, 403] {
            let error = HubFailure.http(code, "Revoked or expired")
            XCTAssertFalse(error.retryable); XCTAssertTrue(error.authenticationRequired)
        }
        XCTAssertFalse(HubFailure.message("Invalid origin").retryable)
    }
}
