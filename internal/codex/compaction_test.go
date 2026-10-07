package codex

import (
	"encoding/json"
	"github.com/mothx9/codex-relay/internal/protocol"
	"testing"
)

func TestCompactionLifecycleIsForwardedWithoutReasoning(t *testing.T) {
	a := &Adapter{epoch: "test", events: make(chan protocol.Event, 4), done: make(chan struct{}), sessions: map[string]protocol.Session{"t": {ID: "m~t", Status: protocol.Working, TurnID: "turn"}}}
	for _, step := range []struct{ method, state string }{{"item/started", "running"}, {"item/completed", "completed"}} {
		a.handle(rpcMessage{Method: step.method, Params: json.RawMessage(`{"threadId":"t","turnId":"turn","item":{"type":"contextCompaction","id":"compact"}}`)})
		select {
		case e := <-a.events:
			if e.Kind != "activity" || e.Activity.Kind != "context_compaction" || e.Activity.State != step.state || e.Activity.ID != "compact" || e.Activity.TurnID != "turn" {
				t.Fatalf("lost lifecycle: %+v", e)
			}
		default:
			t.Fatal("compaction was dropped")
		}
	}
	a.handle(rpcMessage{Method: "item/started", Params: json.RawMessage(`{"threadId":"t","turnId":"turn","item":{"type":"reasoning","id":"r","text":"private"}}`)})
	select {
	case <-a.events:
		t.Fatal("reasoning leaked")
	default:
	}
}
