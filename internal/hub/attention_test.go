package hub

import (
	"github.com/mothx9/codex-relay/internal/protocol"
	"path/filepath"
	"testing"
)

func TestLiveQuestionAttentionIsEphemeralAndEpochScoped(t *testing.T) {
	h, db, srv := testHub(t, filepath.Join(t.TempDir(), "db"))
	defer srv.Close()
	defer db.Close()
	a := &agentPeer{}
	h.agents["m"] = a
	s := protocol.Session{ID: "m~t", MachineID: "m", ThreadID: "t", Status: protocol.Working, TurnID: "turn"}
	msg := protocol.Message{Version: protocol.Version, Machine: &protocol.Machine{ID: "m"}, Epoch: "e", Sessions: []protocol.Session{s}}
	if err := h.announce("m", a, msg); err != nil {
		t.Fatal(err)
	}
	peer := &protocol.Peer{Send: make(chan protocol.Message, 128), Done: make(chan struct{})}
	h.operators[&operator{peer: peer}] = true // Inbox observer, no watched conversation
	e := protocol.Event{ID: "live", Epoch: "e", Sequence: 1, MachineID: "m", SessionID: s.ID, TurnID: s.TurnID, Kind: "activity", Activity: &protocol.Activity{ID: "question", Kind: "agentMessage", Questions: []protocol.AsyncQuestion{{Title: "Scope?"}}}}
	if err := h.event("m", a, e); err != nil {
		t.Fatal(err)
	}
	found := false
	for len(peer.Send) > 0 {
		message := <-peer.Send
		if message.Type != "attention" {
			continue
		}
		if message.Event.Kind != "live_question" || message.Event.Activity.Text != "" {
			t.Fatal("invalid live attention envelope")
		}
		found = true
	}
	if !found {
		t.Fatal("unwatched controller missed live question")
	}

	if len(h.liveQuestionNotices) != 1 || len(h.requests) != 0 || len(h.snapshot().Requests) != 0 {
		t.Fatal("live observation became canonical pending state")
	}
	for _, v := range h.liveQuestionNotices {
		if !h.questionCurrent(v) {
			t.Fatal("fresh live observation rejected")
		}
	}
	if err := h.event("m", a, e); err != nil {
		t.Fatal(err)
	}
	if len(h.liveQuestionNotices) != 1 {
		t.Fatal("duplicate")
	}
	e.ID = "input"
	e.Sequence = 2
	e.Activity = &protocol.Activity{ID: "reply", Kind: "userMessage"}
	if err := h.event("m", a, e); err != nil {
		t.Fatal(err)
	}
	if len(h.liveQuestionNotices) != 0 {
		t.Fatal("input did not retire hint")
	}
	e.ID = "q2"
	e.Sequence = 3
	e.Activity = &protocol.Activity{ID: "q2", Kind: "agentMessage", Questions: []protocol.AsyncQuestion{{Title: "Next?"}}}
	if err := h.event("m", a, e); err != nil {
		t.Fatal(err)
	}
	h.offline("m", a)
	for _, v := range h.liveQuestionNotices {
		if h.questionCurrent(v) {
			t.Fatal("offline hint remained current")
		}
	}
	b := &agentPeer{}
	h.agents["m"] = b
	msg.Epoch = "next"
	if err := h.announce("m", b, msg); err != nil {
		t.Fatal(err)
	}
	for _, v := range h.liveQuestionNotices {
		if h.questionCurrent(v) {
			t.Fatal("old epoch hint became current")
		}
	}
	if err := h.event("m", a, e); err == nil {
		t.Fatal("old epoch accepted")
	}
}
