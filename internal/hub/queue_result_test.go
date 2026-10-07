package hub

import (
	"encoding/json"
	"path/filepath"
	"testing"

	"github.com/mothx9/codex-relay/internal/protocol"
)

func TestQueueEditResultCarriesCanonicalQueueWithoutWaitingForEvent(t *testing.T) {
	h, store, server := testHub(t, filepath.Join(t.TempDir(), "db"))
	defer store.Close()
	defer server.Close()
	defer h.Close()
	peer := &protocol.Peer{Send: make(chan protocol.Message, 1), Done: make(chan struct{})}
	op := &operator{peer: peer, session: "m~t"}
	for _, kind := range []string{protocol.QueueUpdate, protocol.QueueSteer, "history", protocol.Steer} {
		id := protocol.ID()
		h.flights[id] = flight{operator: op, machine: "m", session: "m~t", kind: kind}
		h.result("m", protocol.Result{ID: id, OK: true, FollowUps: []protocol.FollowUp{{ID: "q", ClientID: "client", Text: "edited", Revision: "new", Editable: true}}})
		got := (<-peer.Send).Result
		if kind == protocol.Steer {
			if got.FollowUps != nil {
				t.Fatal("steer result must not pretend to read the queue")
			}
		} else if len(got.FollowUps) != 1 || got.FollowUps[0].Text != "edited" {
			t.Fatal("canonical queue discarded", got)
		}
	}
}

func TestEmptyQueueReadIsDistinctFromCommandWithoutQueueRead(t *testing.T) {
	for _, values := range [][]protocol.FollowUp{nil, {}} {
		data, err := json.Marshal(protocol.Result{ID: "result", OK: true, FollowUps: values})
		if err != nil {
			t.Fatal(err)
		}
		var got protocol.Result
		if err := json.Unmarshal(data, &got); err != nil {
			t.Fatal(err)
		}
		if (got.FollowUps == nil) != (values == nil) {
			t.Fatal("empty authoritative queue became absent", string(data))
		}
	}
}
