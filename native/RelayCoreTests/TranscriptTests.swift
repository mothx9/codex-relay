import XCTest
@testable import RelayCore

final class TranscriptTests: XCTestCase {
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
        XCTAssertEqual(groups.map(\.kind), [.message, .terminal, .mcp, .message, .terminal])
        XCTAssertEqual(groups.map { $0.items.count }, [1, 2, 1, 1, 1])
        XCTAssertEqual(groups.flatMap(\.items).map(\.id), items.map(\.id))
        XCTAssertEqual(groups[3].items.first?.clientId, "canonical-client")
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

}
