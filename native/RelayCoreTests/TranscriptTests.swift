import XCTest
@testable import RelayCore

final class TranscriptTests: XCTestCase {
    func testSmallScrollAndDecelerationDoNotResumeFollowing() {
        var policy = TranscriptScrollPolicy()
        XCTAssertTrue(policy.shouldFollow)
        policy.beginInteraction()
        XCTAssertFalse(policy.shouldFollow)
        // Finger lift does not end interaction; the view waits for native idle.
        XCTAssertTrue(policy.isInteracting)
        policy.endInteraction(distanceFromBottom: 55)
        XCTAssertFalse(policy.shouldFollow)
        policy.readHistory()
        XCTAssertFalse(policy.shouldFollow)
        policy.jumpToLatest()
        XCTAssertTrue(policy.shouldFollow)
    }
    func testOnlyUserArrivalAtBottomResumesFollowing() {
        var policy = TranscriptScrollPolicy()
        policy.beginInteraction()
        policy.endInteraction(distanceFromBottom: 0)
        XCTAssertTrue(policy.shouldFollow)
        policy.beginInteraction()
        policy.endInteraction(distanceFromBottom: nil)
        XCTAssertFalse(policy.shouldFollow)
        policy.jumpToLatest()
        XCTAssertTrue(policy.shouldFollow)
    }

    func testToolGroupsPreserveConversationOrderAndIdentity() {
        let items = [
            Activity(id: "agent", kind: "agentMessage", text: "Checking"),
            Activity(id: "cmd1", kind: "commandExecution", text: "pwd"),
            Activity(id: "cmd2", kind: "command_output", text: "output"),
            Activity(id: "mcp", kind: "mcpToolCall", text: "MCP tool call"),
            Activity(id: "user", kind: "userMessage", text: "Next", clientId: "canonical-client"),
            Activity(id: "cmd3", kind: "commandExecution", text: "ls")
        ]
        let groups = TranscriptGroup.make(items)
        XCTAssertEqual(groups.map(\.kind), [.message, .activity, .message, .terminal])
        XCTAssertEqual(groups.map { $0.items.count }, [1, 3, 1, 1])
        XCTAssertEqual(groups.flatMap(\.items).map(\.id), items.map(\.id))
        XCTAssertEqual(groups[2].items.first?.clientId, "canonical-client")
    }
    func testStreamingAndCanonicalToolReplacementCountOnce() {
        var chat = RecentChat()
        chat.put(Activity(id: "cmd", kind: "commandExecution", text: "pwd"))
        chat.put(Activity(id: "cmd", kind: "command_output", text: "/demo"))
        let streaming = TranscriptGroup.make(chat.items)
        XCTAssertEqual(streaming.count, 1)
        XCTAssertEqual(streaming[0].kind, .terminal)
        XCTAssertEqual(streaming[0].items.count, 1)
        chat.put(Activity(id: "cmd", kind: "commandExecution", text: "pwd\n/demo"))
        XCTAssertEqual(TranscriptGroup.make(chat.items)[0].items.count, 1)
    }
    func testUnknownActivityIsRetainedAndMessagesAreNeverMerged() {
        let groups = TranscriptGroup.make([
            Activity(id: "1", kind: "agentMessage", text: "One"),
            Activity(id: "2", kind: "delta", text: "Two"),
            Activity(id: "3", kind: "futureTool", text: "Keep this context")
        ])
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.last?.kind, .activity)
        XCTAssertEqual(groups.last?.items.first?.text, "Keep this context")
        XCTAssertTrue(TranscriptGroup.make([]).isEmpty)
    }
    func testCanonicalAsyncQuestionSurvivesDecodingAndMemoryBounds() throws {
        let item = try RelayJSON.decoder().decode(Activity.self, from: Data(#"{"id":"question-item","kind":"agentMessage","text":"Which scope?","questions":[{"title":"Which scope?","options":["Minimal","Complete"]}]}"#.utf8))
        XCTAssertEqual(item.questions?.first?.title, "Which scope?")
        XCTAssertEqual(item.questions?.first?.options, ["Minimal", "Complete"])
        var chat = RecentChat(); chat.put(item)
        XCTAssertEqual(TranscriptGroup.make(chat.items).first?.items.first?.questions?.count, 1)
        for i in 0..<600 {
            chat.put(Activity(id: "large-\(i)", kind: "agentMessage", text: "Question", questions: [AsyncQuestion(title: String(repeating: "q", count: 16384))]))
        }
        XCTAssertLessThanOrEqual(chat.items.reduce(0) { $0 + $1.contextBytes }, RecentChat.maxBytes)
        XCTAssertLessThan(chat.items.count, 600)
    }
    func testLongConversationRetainsMessagesBeyondOldWindow() {
        var chat = RecentChat()
        for i in 0..<180 { chat.put(Activity(id: "item-\(i)", kind: "agentMessage", text: "Message \(i)")) }
        XCTAssertEqual(chat.items.count, 180)
        XCTAssertEqual(chat.items.first?.id, "item-0")
    }
    func testOlderHistoryPrependsWithoutDuplicatingCanonicalItems() {
        var chat = RecentChat()
        chat.put(Activity(id: "recent", kind: "userMessage", text: "New", clientId: "client"))
        chat.beginHistory()
        chat.mergeHistory([Activity(id: "old", kind: "agentMessage", text: "Older"), Activity(id: "recent", kind: "userMessage", text: "New", clientId: "client")])
        XCTAssertEqual(chat.items.map(\.id), ["old", "recent"])
        chat.mergeHistory([Activity(id: "old", kind: "agentMessage", text: "Older")])
        XCTAssertEqual(chat.items.count, 2)
    }
    func testHistoryCannotOverwriteNewerStreamingContentOrIdentity() throws {
        var chat = RecentChat()
        chat.put(Activity(id: "a", kind: "agentMessage", text: "Start", clientId: "identity"))
        chat.beginHistory()
        let delta = try RelayJSON.decoder().decode(RelayEvent.self, from: Data(#"{"kind":"delta","session_id":"m~t","item_id":"a","text":" continued"}"#.utf8))
        chat.apply(delta)
        chat.mergeHistory([Activity(id: "a", kind: "agentMessage", text: "Start")])
        XCTAssertEqual(chat.items[0].text, "Start continued")
        XCTAssertEqual(chat.items[0].kind, "agentMessage")
        XCTAssertEqual(chat.items[0].clientId, "identity")
        chat.beginHistory()
        chat.mergeHistory([Activity(id: "a", kind: "agentMessage", text: "Canonical after reconnect")])
        XCTAssertEqual(chat.items[0].text, "Canonical after reconnect")
    }

    func testReconnectMergesOlderAndNewerHistoryAroundExistingAnchor() {
        var chat = RecentChat()
        chat.put(Activity(id: "middle", kind: "agentMessage", text: "Before reconnect"))
        chat.beginHistory()
        chat.mergeHistory(["old", "middle", "new"].map { Activity(id: $0, kind: "agentMessage", text: $0) })
        XCTAssertEqual(chat.items.map(\.id), ["old", "middle", "new"])
    }

    func testCommandOutputStreamsWithoutLosingCommandOrLifecycle() throws {
        var chat = RecentChat()
        let command = try RelayJSON.decoder().decode(Activity.self, from: Data(#"{"id":"cmd","kind":"commandExecution","command":"make test","text":"make test","state":"running"}"#.utf8))
        chat.put(command)
        let delta = try RelayJSON.decoder().decode(RelayEvent.self, from: Data(#"{"session_id":"m~t","kind":"command_output","item_id":"cmd","text":"test 1 passed\n"}"#.utf8))
        chat.apply(delta); chat.apply(delta)
        XCTAssertEqual(chat.items.count, 1)
        XCTAssertEqual(chat.items[0].command, "make test")
        XCTAssertEqual(chat.items[0].commandOutput, "test 1 passed\ntest 1 passed\n")
        XCTAssertEqual(chat.items[0].state, "running")
        XCTAssertEqual(chat.items[0].kind, "commandExecution")
    }

}

extension TranscriptTests {
    func testProgressDoesNotReplaceOutputOrResurrectCompletedTool() throws {
        var chat = RecentChat()
        var item = Activity(id: "command", kind: "commandExecution", text: "printf hi\nhello")
        item.command = "printf hi"; item.state = "running"
        chat.put(item)
        func event(_ kind: String, _ id: String, _ text: String) throws -> RelayEvent {
            let data = try JSONSerialization.data(withJSONObject: ["kind": kind, "session_id": "m~t", "item_id": id, "text": text])
            return try RelayJSON.decoder().decode(RelayEvent.self, from: data)
        }
        chat.apply(try event("terminal_interaction", "command", "Input sent to command"))
        XCTAssertEqual(chat.items.count, 1)
        XCTAssertEqual(chat.items[0].commandOutput, "hello")
        chat.apply(try event("command_output", "command", " again"))
        XCTAssertEqual(chat.items[0].commandOutput, "hello again")
        XCTAssertEqual(chat.items[0].progress, "Input sent to command")
        chat.beginHistory()
        chat.apply(try event("tool_progress", "tool", "Reading page 2"))
        chat.mergeHistory([Activity(id: "tool", kind: "mcpToolCall", text: "lookup")])
        XCTAssertEqual(chat.items.last?.progress, "Reading page 2")
        var completed = Activity(id: "tool", kind: "mcpToolCall", text: "lookup")
        completed.state = "completed"; completed.resultSummary = "Found documentation"
        chat.put(completed)
        chat.apply(try event("tool_progress", "tool", "Late"))
        XCTAssertEqual(chat.items.last?.state, "completed")
        XCTAssertNil(chat.items.last?.progress)
        XCTAssertEqual(chat.items.last?.resultSummary, "Found documentation")
        XCTAssertEqual(TranscriptGroup.make(chat.items).map(\.id), ["terminal.command"])
    }
}

extension TranscriptTests {
    private func liveQuestionEvent(_ id: String = "question", kind: String = "activity", turn: String = "turn") throws -> RelayEvent {
        let data = try JSONSerialization.data(withJSONObject: ["kind": kind, "session_id": "machine~thread", "turn_id": turn,
            "activity": ["id": id, "kind": "agentMessage", "text": "Which scope?", "questions": [["title": "Which scope?", "options": ["Focused", "Full"]]]]])
        return try RelayJSON.decoder().decode(RelayEvent.self, from: data)
    }
    func testLiveQuestionHintNeverComesFromHistoryOrReconnect() throws {
        var hints = LiveQuestions(); var chat = RecentChat()
        let event = try liveQuestionEvent()
        chat.mergeHistory([try XCTUnwrap(event.activity)])
        hints.reconcile(activeTurn: "turn", current: true)
        XCTAssertTrue(hints.itemIDs.isEmpty)
        hints.observe(event, activeTurn: "turn", current: true)
        hints.observe(event, activeTurn: "turn", current: true)
        XCTAssertEqual(hints.itemIDs, ["question"])
        hints.reset() // socket loss or leaving the conversation
        hints.reconcile(activeTurn: "turn", current: true)
        XCTAssertTrue(hints.itemIDs.isEmpty)
        XCTAssertEqual(chat.items.first?.questions?.count, 1, "Conversation content remains readable")
    }
    func testLiveQuestionsExpireWithTurnAndConnectivityAndStayBounded() throws {
        var hints = LiveQuestions()
        hints.observe(try liveQuestionEvent(), activeTurn: "other", current: true)
        XCTAssertTrue(hints.itemIDs.isEmpty)
        hints.observe(try liveQuestionEvent(), activeTurn: "turn", current: false)
        XCTAssertTrue(hints.itemIDs.isEmpty)
        for i in 0..<100 { hints.observe(try liveQuestionEvent("q-\(i)"), activeTurn: "turn", current: true) }
        XCTAssertEqual(hints.itemIDs.count, 64)
        hints.observe(try liveQuestionEvent(kind: "turn_completed"), activeTurn: "turn", current: true)
        XCTAssertTrue(hints.itemIDs.isEmpty)
        hints.observe(try liveQuestionEvent(), activeTurn: "turn", current: true)
        hints.reconcile(activeTurn: "next", current: true)
        XCTAssertTrue(hints.itemIDs.isEmpty)
        hints.observe(try liveQuestionEvent(), activeTurn: "turn", current: true)
        hints.reconcile(activeTurn: "turn", current: false)
        XCTAssertTrue(hints.itemIDs.isEmpty)
    }
}


extension TranscriptTests {
    func testMixedOperationsKeepAnchorAndRespectTurnBoundaries() {
        var command = Activity(id: "c", kind: "commandExecution", text: "check"); command.turnId = "turn-a"
        var file = Activity(id: "f", kind: "fileChange", text: ""); file.turnId = "turn-a"
        file.files = [ChangedFile(path: "src/kernel.cu", kind: "modify", previousPath: nil, patch: nil)]
        var next = Activity(id: "next", kind: "commandExecution", text: "check again"); next.turnId = "turn-b"
        let first = TranscriptGroup.make([command])[0]
        let groups = TranscriptGroup.make([command, file, next])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(first.id, groups[0].id)
        XCTAssertEqual(groups[0].kind, .activity)
        XCTAssertEqual(groups[0].changedPaths, ["src/kernel.cu"])
        XCTAssertEqual(groups[0].commandCount, 1)
        XCTAssertEqual(groups.flatMap(\.items).map(\.id), ["c", "f", "next"])
    }
}
