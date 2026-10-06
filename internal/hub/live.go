package hub

import (
	"path/filepath"
	"strings"

	"github.com/mothx9/codex-relay/internal/protocol"
)

// Only operational boundaries reach Fleet. Output deltas never fan out as
// transcript text and repeated chunks do not publish another Fleet update.
func (h *Hub) updateLiveActivity(e protocol.Event) {
	previous := h.liveActivities[e.SessionID]
	next := protocol.LiveActivity{ItemID: e.ItemID, Timestamp: e.Timestamp, State: "running"}
	switch e.Kind {
	case "turn_started", "turn_completed", "failed":
		if previous.Kind == "" {
			return
		}
		delete(h.liveActivities, e.SessionID)
		h.broadcast(protocol.Message{Type: "event", Event: &protocol.Event{Kind: "live_activity", SessionID: e.SessionID}}, "")
		return
	case "activity":
		if e.Activity == nil {
			return
		}
		a := e.Activity
		next.ItemID, next.State = a.ID, a.State
		switch a.Kind {
		case "commandExecution":
			next.Kind = "terminal"
			next.Label = a.Command
			if next.Label == "" {
				next.Label = strings.SplitN(a.Text, "\n", 2)[0]
			}
		case "mcpToolCall":
			next.Kind = "tool"
			next.Label = a.ToolName
		case "fileChange":
			next.Kind = "file"
			if len(a.Files) > 0 {
				next.Label = filepath.Base(a.Files[0].Path)
			}
		case "agentMessage":
			next.Kind = "assistant"
		default:
			return
		}
	case "delta":
		next.Kind = "assistant"
	case "command_output":
		next.Kind = "terminal"
	case "diff":
		next.Kind = "diff"
		next.ItemID = e.TurnID + "/diff"
	default:
		return
	}
	if next.ItemID == previous.ItemID && next.Kind == previous.Kind && next.Label == "" {
		next.Label = previous.Label
	}
	// A completion for another item must not hide the currently observed
	// running operation (commands can overlap).
	if next.State != "running" && previous.State == "running" && next.ItemID != previous.ItemID {
		return
	}
	next.Label = protocol.Clip(strings.Join(strings.Fields(next.Label), " "), 160)
	if next.ItemID == previous.ItemID && next.Kind == previous.Kind && next.Label == previous.Label && next.State == previous.State {
		return
	}
	if h.liveActivities == nil {
		h.liveActivities = make(map[string]protocol.LiveActivity)
	}
	h.liveActivities[e.SessionID] = next
	h.broadcast(protocol.Message{Type: "event", Event: &protocol.Event{Kind: "live_activity", SessionID: e.SessionID, LiveActivity: &next}}, "")
}
