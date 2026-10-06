package agent

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"github.com/mothx9/codex-relay/internal/protocol"
)

type inFlightSnapshotBackend struct {
	refreshBackend
	snapshots int
}

func (b *inFlightSnapshotBackend) Snapshot(context.Context) ([]protocol.Session, []protocol.PendingRequest, error) {
	b.snapshots++
	if b.snapshots == 2 {
		b.events <- protocol.Event{ID: "epoch/8", Epoch: "epoch", Sequence: 8, Kind: "activity", SessionID: "m~t", Activity: &protocol.Activity{ID: "response", Kind: "agentMessage", Text: "final answer"}}
	}
	return nil, nil, nil
}
func (b *inFlightSnapshotBackend) Cursor() (string, uint64) {
	if b.snapshots >= 2 {
		return "epoch", 8
	}
	return "epoch", 7
}
func TestRefreshDeliversTranscriptBeforeAdvancingSnapshotCursor(t *testing.T) {
	received := make(chan protocol.Message, 4)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		c, err := (&websocket.Upgrader{}).Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer c.Close()
		for i := 0; i < 3; i++ {
			var msg protocol.Message
			if c.ReadJSON(&msg) != nil {
				return
			}
			received <- msg
		}
	}))
	defer server.Close()
	c, _, err := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(server.URL, "http"), nil)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	p := protocol.NewPeer(c)
	defer p.Close()
	go p.WriteLoop(ctx)
	b := &inFlightSnapshotBackend{refreshBackend: refreshBackend{events: make(chan protocol.Event, 8), done: make(chan struct{})}}
	finished := make(chan error, 1)
	order := []string{}
	go func() {
		finished <- serveRefreshing(ctx, p, b, protocol.Machine{ID: "m"}, map[string]protocol.Result{}, &order, 10*time.Millisecond)
	}()
	var messages []protocol.Message
	for len(messages) < 3 {
		select {
		case m := <-received:
			messages = append(messages, m)
		case <-time.After(3 * time.Second):
			t.Fatal("missing messages")
		}
	}
	cancel()
	p.Close()
	<-finished
	if messages[0].Type != "announce" || messages[0].Sequence != 7 {
		t.Fatal("initial cursor", messages[0])
	}
	if messages[1].Type != "event" || messages[1].Event == nil || messages[1].Event.Activity == nil || messages[1].Event.Activity.Text != "final answer" {
		t.Fatal("metadata refresh discarded the final response", messages[1])
	}
	if messages[2].Type != "announce" || messages[2].Sequence != 8 {
		t.Fatal("snapshot did not follow its events", messages[2])
	}
}
