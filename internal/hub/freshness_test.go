package hub

import (
	"github.com/mothx9/codex-relay/internal/protocol"
	"path/filepath"
	"testing"
	"time"
)

func TestConnectionRequiresSnapshotAndRejectsOldEpoch(t *testing.T) {
	h, db, srv := testHub(t, filepath.Join(t.TempDir(), "db"))
	defer srv.Close()
	defer db.Close()
	session := protocol.Session{ID: "m~t", MachineID: "m", ThreadID: "t", Status: protocol.Working}
	first := &agentPeer{}
	h.agents["m"] = first
	h.syncing("m", first)
	if h.machines["m"].Status != protocol.Syncing {
		t.Fatal("transport is not fresh state")
	}
	msg := protocol.Message{Version: protocol.Version, Machine: &protocol.Machine{ID: "m"}, Epoch: "old", Sequence: 5, Sessions: []protocol.Session{session}}
	if err := h.announce("m", first, msg); err != nil {
		t.Fatal(err)
	}
	if !h.snapshot().Sessions[0].Fresh {
		t.Fatal("accepted snapshot not current")
	}
	h.offline("m", first)
	if h.sessions[session.ID].Status != protocol.Working || h.snapshot().Sessions[0].Fresh || h.machines["m"].Status != protocol.Offline {
		t.Fatal("disconnect fabricated session state or retained freshness")
	}
	next := &agentPeer{}
	h.agents["m"] = next
	h.syncing("m", next)
	if h.snapshot().Sessions[0].Fresh {
		t.Fatal("reconnect reused previous snapshot")
	}
	msg.Epoch = "new"
	msg.Sequence = 1
	if err := h.announce("m", next, msg); err != nil {
		t.Fatal(err)
	}
	if h.machines["m"].Status != protocol.Online {
		t.Fatal("fresh snapshot did not admit online")
	}
	msg.Epoch = "old"
	msg.Sessions[0].Status = protocol.Ready
	if h.announce("m", next, msg) == nil {
		t.Fatal("same socket rewound its epoch")
	}
	if h.announce("m", first, msg) == nil {
		t.Fatal("old peer announced after takeover")
	}
	if h.event("m", first, protocol.Event{ID: "late", Epoch: "old", MachineID: "m", SessionID: "m~t", Sequence: 99, Session: &msg.Sessions[0]}) == nil {
		t.Fatal("old peer mutated state")
	}
	if h.sessions[session.ID].Status != protocol.Working {
		t.Fatal("stale state replaced work")
	}
}

func TestPendingUnseenSessionSurvivesRefreshAndAge(t *testing.T) {
	h, db, srv := testHub(t, filepath.Join(t.TempDir(), "db"))
	defer srv.Close()
	defer db.Close()
	a := &agentPeer{}
	h.agents["m"] = a
	msg := protocol.Message{Version: protocol.Version, Machine: &protocol.Machine{ID: "m"}, Epoch: "e"}
	if err := h.announce("m", a, msg); err != nil {
		t.Fatal(err)
	}
	req := protocol.PendingRequest{ID: "pending", MachineID: "m", SessionID: "m~cold", ThreadID: "cold", Kind: "user_input", Status: "pending", CreatedAt: time.Now().Add(-48 * time.Hour), ExpiresAt: time.Now().Add(-24 * time.Hour)}
	ev := protocol.Event{ID: "e1", Epoch: "e", Sequence: 1, MachineID: "m", SessionID: req.SessionID, Kind: "request", Request: &req}
	if err := h.event("m", a, ev); err != nil {
		t.Fatal(err)
	}
	if h.snapshot().Sessions[0].Status != protocol.NeedsYou {
		t.Fatal("pending cold thread not surfaced")
	}
	msg.Sequence = 1 // incomplete metadata refresh must not erase canonical requests
	if err := h.announce("m", a, msg); err != nil {
		t.Fatal(err)
	}
	if len(h.requests) != 1 || len(h.snapshot().Sessions) != 1 {
		t.Fatal("refresh lost request/session")
	}
	h.offline("m", a)
	h.maintain(time.Now())
	if len(h.requests) != 1 {
		t.Fatal("local expiry or offline retired unresolved request")
	}
	a = &agentPeer{}
	h.agents["m"] = a
	msg.Requests = []protocol.PendingRequest{req}
	if err := h.announce("m", a, msg); err != nil {
		t.Fatal(err)
	}
	ev.Request = nil
	ev.RequestID = req.ID
	ev.Kind = "request_resolved"
	ev.Sequence = 2
	ev.ID = "e2"
	if err := h.event("m", a, ev); err != nil {
		t.Fatal(err)
	}
	if err := h.event("m", a, ev); err != nil {
		t.Fatal(err)
	}
	if len(h.requests) != 0 {
		t.Fatal("resolution did not retire canonical request")
	}
}

func TestDegradedAnnouncePreservesLastKnownSession(t *testing.T) {
	h, db, srv := testHub(t, filepath.Join(t.TempDir(), "db"))
	defer srv.Close()
	defer db.Close()
	h.sessions["m~t"] = protocol.Session{ID: "m~t", MachineID: "m", ThreadID: "t", Status: protocol.Working}
	a := &agentPeer{}
	h.agents["m"] = a
	h.syncing("m", a)
	if err := h.announce("m", a, protocol.Message{Version: protocol.Version, Epoch: "e", Machine: &protocol.Machine{ID: "m", Status: protocol.Degraded}}); err != nil {
		t.Fatal(err)
	}
	if h.machines["m"].Status != protocol.Degraded || h.snapshot().Sessions[0].Status != protocol.Working || h.snapshot().Sessions[0].Fresh {
		t.Fatal("Codex outage erased or renewed last known work")
	}
}

func TestOrderingAndRestartRouting(t *testing.T) {
	h, db, srv := testHub(t, filepath.Join(t.TempDir(), "db"))
	defer srv.Close()
	defer db.Close()
	a := &agentPeer{}
	h.agents["m"] = a
	s := protocol.Session{ID: "m~t", MachineID: "m", ThreadID: "t", Status: protocol.Working}
	msg := protocol.Message{Version: protocol.Version, Machine: &protocol.Machine{ID: "m"}, Epoch: "e", Sequence: 1, Sessions: []protocol.Session{s}}
	if err := h.announce("m", a, msg); err != nil {
		t.Fatal(err)
	}
	r := protocol.PendingRequest{ID: "request", MachineID: "m", SessionID: s.ID, ThreadID: "t", Kind: "user_input", Status: "pending"}
	ev := protocol.Event{ID: "event", MachineID: "m", SessionID: s.ID, Epoch: "e", Sequence: 3, Request: &r}
	if err := h.event("m", a, ev); err != nil {
		t.Fatal(err)
	}
	// Same event ID with a later sequence must not reapply it or its state.
	ready := s
	ready.Status = protocol.Ready
	ev.Sequence = 4
	ev.Session = &ready
	if err := h.event("m", a, ev); err != nil {
		t.Fatal(err)
	}
	if a.sequence != 3 || h.sessions[s.ID].Status != protocol.Working {
		t.Fatal("duplicate event reapplied")
	}
	ev.ID = "reordered"
	ev.Sequence = 2
	ev.Request = nil
	if err := h.event("m", a, ev); err != nil {
		t.Fatal(err)
	}
	msg.Sessions[0] = ready
	if err := h.announce("m", a, msg); err != nil {
		t.Fatal(err)
	}
	if h.sessions[s.ID].Status != protocol.Working || len(h.requests) != 1 {
		t.Fatal("older state regressed canonical state")
	}
	recovered, err := New(db, h.config)
	if err != nil {
		t.Fatal(err)
	}
	if recovered.machines["m"].Status != protocol.Offline || len(recovered.requests) != 1 || recovered.snapshot().Sessions[0].Fresh {
		t.Fatal("Hub restart lost routing or fabricated freshness")
	}
	if recovered.snapshot().Sessions[0].Status != protocol.NeedsYou {
		t.Fatal("restart hid pending state")
	}
	if len(recovered.requests[r.ID].Payload) != 0 {
		t.Fatal("persisted sensitive request context")
	}
}

func TestSnapshotRevisionRejectsEqualWatermarkReplay(t *testing.T) {
	h, db, srv := testHub(t, filepath.Join(t.TempDir(), "db"))
	defer srv.Close()
	defer db.Close()
	a := &agentPeer{}
	h.agents["m"] = a
	s := protocol.Session{ID: "m~t", MachineID: "m", ThreadID: "t", Status: protocol.Working}
	msg := protocol.Message{Version: protocol.Version, Machine: &protocol.Machine{ID: "m"}, Epoch: "e", Sequence: 5, SnapshotRevision: 2, Sessions: []protocol.Session{s}}
	if err := h.announce("m", a, msg); err != nil {
		t.Fatal(err)
	}
	msg.SnapshotRevision = 1
	msg.Sessions[0].Status = protocol.Ready
	if err := h.announce("m", a, msg); err != nil {
		t.Fatal(err)
	}
	if h.sessions[s.ID].Status != protocol.Working {
		t.Fatal("older equal-watermark snapshot regressed state")
	}
}
