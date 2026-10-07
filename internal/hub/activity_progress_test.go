package hub

import (
	"strings"
	"testing"

	"github.com/mothx9/codex-relay/internal/protocol"
)

func TestProgressPreservesOutputAndStableIdentity(t *testing.T) {
	b := &Recent{}
	b.Put(protocol.Activity{ID: "cmd", Kind: "commandExecution", Command: "printf hi", Text: "printf hi\noutput so far", State: "running"})
	b.Apply(protocol.Event{Kind: "terminal_interaction", ItemID: "cmd", Text: "Input sent to command"})
	if len(b.Items) != 1 || b.Items[0].Text != "printf hi\noutput so far" || b.Items[0].Progress == "" || b.Items[0].Command != "printf hi" {
		t.Fatal(b.Items)
	}
	b.Apply(protocol.Event{Kind: "command_output", ItemID: "cmd", Text: "\nmore output"})
	if !strings.HasSuffix(b.Items[0].Text, "\nmore output") || b.Items[0].Progress == "" {
		t.Fatal("output lost progress metadata")
	}
	b.Apply(protocol.Event{Kind: "tool_progress", ItemID: "tool", Text: strings.Repeat("x", 5000)})
	if len(b.Items) != 2 || len(b.Items[1].Progress) != 1024 || b.Items[1].Kind != "mcpToolCall" {
		t.Fatal("progress not bounded/canonical")
	}
	b.Put(protocol.Activity{ID: "tool", Kind: "mcpToolCall", State: "completed", ResultSummary: "Result"})
	b.Apply(protocol.Event{Kind: "tool_progress", ItemID: "tool", Text: "late"})
	if b.Items[1].State != "completed" || b.Items[1].Progress != "" {
		t.Fatal("completion regressed")
	}
	h := &Hub{}
	h.updateLiveActivity(protocol.Event{Kind: "tool_progress", ItemID: "tool", Text: "PRIVATE_PROGRESS"})
	if len(h.liveActivities) != 0 {
		t.Fatal("progress text leaked to Fleet")
	}
}
