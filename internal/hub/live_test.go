package hub

import (
	"github.com/mothx9/codex-relay/internal/protocol"
	"testing"
	"time"
)

func TestFleetActivityIsOperationalBoundedAndIndependentOfWatching(t *testing.T) {
	h := &Hub{}
	now := time.Now()
	h.updateLiveActivity(protocol.Event{Kind: "activity", SessionID: "m~t", Timestamp: now, Activity: &protocol.Activity{ID: "cmd", Kind: "commandExecution", Command: "go test ./...", Text: "go test ./...\nPRIVATE OUTPUT", State: "running"}})
	live := h.liveActivities["m~t"]
	if live.Kind != "terminal" || live.Label != "go test ./..." || live.State != "running" {
		t.Fatal(live)
	}
	h.updateLiveActivity(protocol.Event{Kind: "command_output", SessionID: "m~t", ItemID: "cmd", Text: "MORE PRIVATE OUTPUT", Timestamp: now.Add(time.Second)})
	if h.liveActivities["m~t"] != live {
		t.Fatal("output chunk re-published or leaked into Fleet")
	}
	h.updateLiveActivity(protocol.Event{Kind: "activity", SessionID: "m~t", Timestamp: now, Activity: &protocol.Activity{ID: "other", Kind: "commandExecution", State: "completed"}})
	if h.liveActivities["m~t"] != live {
		t.Fatal("unrelated completion hid running operation")
	}
	h.updateLiveActivity(protocol.Event{Kind: "activity", SessionID: "m~t", Timestamp: now, Activity: &protocol.Activity{ID: "cmd", Kind: "commandExecution", State: "failed"}})
	if h.liveActivities["m~t"].State != "failed" {
		t.Fatal("failure not reflected")
	}
	snap := h.snapshot()
	h.updateLiveActivity(protocol.Event{Kind: "turn_completed", SessionID: "m~t"})
	if len(h.liveActivities) != 0 || len(snap.LiveActivities) != 1 {
		t.Fatal("snapshot aliased mutable live map or completion not cleared")
	}
}

func TestFleetNeverUsesAssistantTextOrReasoning(t *testing.T) {
	h := &Hub{}
	h.updateLiveActivity(protocol.Event{Kind: "delta", SessionID: "m~t", ItemID: "assistant", Text: "Private assistant response"})
	if v := h.liveActivities["m~t"]; v.Kind != "assistant" || v.Label != "" {
		t.Fatal(v)
	}
	h.updateLiveActivity(protocol.Event{Kind: "activity", SessionID: "m~t", Activity: &protocol.Activity{ID: "reason", Kind: "reasoning", Text: "never display"}})
	if h.liveActivities["m~t"].ItemID != "assistant" {
		t.Fatal("reasoning entered live presentation")
	}
}

func TestCompactionLiveSummaryEndsOnCompletionAndTurnBoundary(t *testing.T) {
	h := &Hub{}
	for _, state := range []string{"running", "completed"} {
		h.updateLiveActivity(protocol.Event{Kind: "activity", SessionID: "m~t", Activity: &protocol.Activity{ID: "compact", Kind: "context_compaction", State: state}})
		if v := h.liveActivities["m~t"]; v.Kind != "context_compaction" || v.State != state {
			t.Fatal(v)
		}
	}
	h.updateLiveActivity(protocol.Event{Kind: "turn_completed", SessionID: "m~t"})
	if len(h.liveActivities) != 0 {
		t.Fatal("compaction survived turn completion")
	}
}
