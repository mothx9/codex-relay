package hub

import (
	"github.com/mothx9/codex-relay/internal/protocol"
	"path/filepath"
	"testing"
	"time"
)

func TestPendingAnnouncementPreservesReservationAndOfflineVisibility(t *testing.T) {
	h, s, server := testHub(t, filepath.Join(t.TempDir(), "relay.db"))
	defer server.Close()
	defer s.Close()
	now := time.Now().UTC()
	request := protocol.PendingRequest{ID: "m~1", MachineID: "m", SessionID: "m~t", ThreadID: "t", TurnID: "turn", Kind: "command_approval", CreatedAt: now, ExpiresAt: now.Add(time.Hour), Status: "pending"}
	session := protocol.Session{ID: "m~t", MachineID: "m", ThreadID: "t", Status: protocol.NeedsYou, UpdatedAt: now}
	a := &agentPeer{epoch: "same"}
	h.agents["m"] = a
	msg := protocol.Message{Version: protocol.Version, Type: "announce", Epoch: "same", Machine: &protocol.Machine{ID: "m"}, Sessions: []protocol.Session{session}, Requests: []protocol.PendingRequest{request}}
	if err := h.announce("m", a, msg); err != nil {
		t.Fatal(err)
	}
	h.answering[request.ID] = "in-flight"
	if err := h.announce("m", a, msg); err != nil {
		t.Fatal(err)
	}
	if h.answering[request.ID] != "in-flight" {
		t.Fatal("periodic snapshot released approval reservation")
	}
	h.offline("m", a)
	if len(h.requests) != 1 || len(h.snapshot().Requests) != 1 {
		t.Fatal("transport loss erased pending request")
	}
	if h.snapshot().Sessions[0].Capabilities.CanAnswer {
		t.Fatal("offline request remained actionable")
	}
	a = &agentPeer{}
	h.agents["m"] = a
	msg.Requests = nil
	if err := h.announce("m", a, msg); err != nil {
		t.Fatal(err)
	}
	if len(h.requests) != 0 || len(h.answering) != 0 {
		t.Fatal("authoritative resolution did not remove request")
	}
}

func TestReusedPendingIDHasDistinctIncarnation(t *testing.T) {
	a := protocol.PendingRequest{ID: "same", CreatedAt: time.Now()}
	b := a
	if !samePending(a, b) {
		t.Fatal("same request changed identity")
	}
	b.CreatedAt = b.CreatedAt.Add(time.Second)
	if samePending(a, b) {
		t.Fatal("new request inherited old identity")
	}
}
