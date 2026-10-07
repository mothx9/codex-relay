package hub

import (
	"github.com/mothx9/codex-relay/internal/protocol"
	"github.com/mothx9/codex-relay/internal/push"
)

// Live questions are an ephemeral observation channel, never pending RPCs.
// No question content is retained here, returned in snapshots, or stored in SQLite.
type liveQuestionNotice struct{ session, turn, machine, epoch string }

func (h *Hub) questionCurrent(v liveQuestionNotice) bool {
	s, ok := h.sessions[v.session]
	m := h.machines[v.machine]
	return ok && (s.Status == protocol.Working || s.Status == protocol.NeedsYou) && s.TurnID == v.turn && m.Status == protocol.Online && m.Freshness.Epoch == v.epoch
}

func (h *Hub) attention(e protocol.Event) {
	for key, v := range h.liveQuestionNotices {
		if !h.questionCurrent(v) {
			delete(h.liveQuestionNotices, key)
		}
	}
	clear := e.Kind == "turn_started" || e.Kind == "turn_completed" || e.Kind == "failed" || (e.Activity != nil && e.Activity.Kind == "userMessage")
	if clear {
		for key, v := range h.liveQuestionNotices {
			if v.session == e.SessionID {
				delete(h.liveQuestionNotices, key)
			}
		}
		notice := e
		notice.Kind = "live_question_cleared"
		notice.Activity = nil
		notice.Text = ""
		notice.Request = nil
		h.broadcast(protocol.Message{Type: "attention", Event: &notice}, "")
		return
	}
	if e.Kind != "activity" || e.Activity == nil || e.Activity.Kind != "agentMessage" || e.Activity.ID == "" || len(e.Activity.Questions) == 0 || e.TurnID == "" {
		return
	}
	identity := liveQuestionNotice{e.SessionID, e.TurnID, e.MachineID, e.Epoch}
	if !h.questionCurrent(identity) {
		return
	}
	notice := e
	notice.Kind = "live_question"
	notice.Text = ""
	notice.Request = nil
	item := protocol.Activity{ID: e.Activity.ID, Kind: "agentMessage", TurnID: e.TurnID, Timestamp: e.Timestamp, Questions: e.Activity.Questions}
	notice.Activity = &item
	// Independent from watched transcript events, with the same freshness envelope.
	h.broadcast(protocol.Message{Type: "attention", Event: &notice}, "")
	key := e.SessionID + "/live_question/" + e.TurnID + "/" + item.ID
	if h.liveQuestionNotices == nil {
		h.liveQuestionNotices = make(map[string]liveQuestionNotice)
	}
	if _, exists := h.liveQuestionNotices[key]; exists {
		return
	}
	if len(h.liveQuestionNotices) >= 128 {
		return
	}
	h.liveQuestionNotices[key] = identity
	if h.push == nil {
		return
	}
	h.push.Enqueue(push.Notice{Key: key, Kind: "live_question", SessionID: e.SessionID, MachineID: e.MachineID, Current: func() bool {
		h.mu.Lock()
		defer h.mu.Unlock()
		v, exists := h.liveQuestionNotices[key]
		return exists && h.questionCurrent(v)
	}})
}
