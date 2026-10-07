package codex

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/mothx9/codex-relay/internal/protocol"
)

func TestLivePatchProgressAndTerminalInteraction(t *testing.T) {
	a := &Adapter{cfg: Config{MachineID: "m"}, sessions: map[string]protocol.Session{"t": {ID: "m~t", ThreadID: "t", Status: protocol.Working, TurnID: "turn"}}, events: make(chan protocol.Event, 32), done: make(chan struct{})}
	send := func(method, params string) protocol.Event {
		t.Helper()
		a.handle(rpcMessage{Method: method, Params: json.RawMessage(params)})
		select {
		case e := <-a.Events():
			return e
		default:
			t.Fatalf("event dropped: %s", method)
			return protocol.Event{}
		}
	}
	send("item/started", `{"threadId":"t","turnId":"turn","item":{"id":"files","type":"fileChange","status":"inProgress","changes":[]}}`)
	patch := send("item/fileChange/patchUpdated", `{"threadId":"t","turnId":"turn","itemId":"files","changes":[{"path":"src/a.c","kind":{"type":"update"},"diff":"@@ -1 +1 @@\n-old\n+new"}]}`)
	if patch.Kind != "activity" || patch.Activity.ID != "files" || patch.Activity.State != "running" || len(patch.Activity.Files) != 1 || patch.Activity.Files[0].Patch == "" {
		t.Fatal(patch)
	}
	send("item/started", `{"threadId":"t","turnId":"turn","item":{"id":"tool","type":"mcpToolCall","tool":"fetch_document","server":"docs","status":"inProgress"}}`)
	progress := send("item/mcpToolCall/progress", `{"threadId":"t","turnId":"turn","itemId":"tool","message":"Reading page 2"}`)
	if progress.Kind != "tool_progress" || progress.ItemID != "tool" || progress.Text != "Reading page 2" {
		t.Fatal(progress)
	}
	send("item/started", `{"threadId":"t","turnId":"turn","item":{"id":"cmd","type":"commandExecution","command":"read value","status":"inProgress"}}`)
	interaction := send("item/commandExecution/terminalInteraction", `{"threadId":"t","turnId":"turn","itemId":"cmd","stdin":"SECRET_CREDENTIAL_CANARY","processId":"PRIVATE_PID"}`)
	wire, _ := json.Marshal(interaction)
	if interaction.Kind != "terminal_interaction" || strings.Contains(string(wire), "SECRET") || strings.Contains(string(wire), "PRIVATE_PID") {
		t.Fatal("terminal interaction disclosed input")
	}
	send("item/completed", `{"threadId":"t","turnId":"turn","item":{"id":"tool","type":"mcpToolCall","tool":"fetch_document","server":"docs","status":"completed"}}`)
	a.handle(rpcMessage{Method: "item/mcpToolCall/progress", Params: json.RawMessage(`{"threadId":"t","turnId":"turn","itemId":"tool","message":"late progress"}`)})
	if len(a.events) != 0 {
		t.Fatal("late progress revived a completed operation")
	}
	a.handle(rpcMessage{Method: "item/fileChange/patchUpdated", Params: json.RawMessage(`{"threadId":"t","turnId":"old-turn","itemId":"files","changes":[]}`)})
	if len(a.events) != 0 {
		t.Fatal("old-turn patch replaced current operation")
	}
}

func TestToolResultsOnlyExposeBoundedTextContent(t *testing.T) {
	raw := json.RawMessage(`{"id":"tool","type":"mcpToolCall","tool":"lookup","server":"docs","status":"completed","arguments":{"token":"ARGUMENT_CANARY"},"result":{"_meta":{"token":"META_CANARY"},"structuredContent":{"token":"STRUCTURED_CANARY"},"content":[{"type":"image","data":"IMAGE_CANARY"},{"type":"resource","resource":{"text":"RESOURCE_CANARY"}},{"type":"text","text":"Found documentation"}]}}`)
	value := activity(raw)
	wire, _ := json.Marshal(value)
	if value.ResultSummary != "Found documentation" || strings.Contains(string(wire), "CANARY") {
		t.Fatal("non-display MCP payload escaped adapter")
	}
	raw, _ = json.Marshal(map[string]any{"id": "big", "type": "mcpToolCall", "tool": "lookup", "result": map[string]any{"content": []any{map[string]string{"type": "text", "text": strings.Repeat("é", 10000)}}}})
	value = activity(raw)
	if !value.Truncated || len(value.ResultSummary) > 4096 || value.ContextBytes() > protocol.MaxText {
		t.Fatal("unbounded tool result")
	}
	adapter := &Adapter{}
	for i := 0; i < 140; i++ {
		adapter.rememberItem("t", protocol.Activity{ID: protocol.ID(), Kind: "mcpToolCall", Text: "bounded"})
	}
	if len(adapter.items) != 128 || len(adapter.itemOrder) != 128 {
		t.Fatal("unbounded operation cache")
	}
}
