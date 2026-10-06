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

func TestBackoffBoundedAndCancelled(t *testing.T) {
	for i := 0; i < 100; i++ {
		d := backoff(i, time.Second)
		if d <= 0 || d > time.Minute {
			t.Fatal(d)
		}
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if wait(ctx, nil, time.Hour) == nil {
		t.Fatal("wait ignored cancellation")
	}
}

type refreshBackend struct {
	events chan protocol.Event
	done   chan struct{}
}

func (b *refreshBackend) Snapshot(context.Context) ([]protocol.Session, []protocol.PendingRequest, error) {
	return nil, nil, nil
}
func (b *refreshBackend) Execute(context.Context, protocol.Command) protocol.Result {
	return protocol.Result{}
}
func (b *refreshBackend) Cursor() (string, uint64)      { return "epoch", 7 }
func (b *refreshBackend) Events() <-chan protocol.Event { return b.events }
func (b *refreshBackend) Done() <-chan struct{}         { return b.done }
func (b *refreshBackend) Close()                        {}

// Simulates an unavailable account provider: control must remain live until shutdown.
func (b *refreshBackend) Account(ctx context.Context) *protocol.Account {
	<-ctx.Done()
	return nil
}

func TestRefreshAndLiveSnapshotProceedWhileAccountReadBlocked(t *testing.T) {
	received := make(chan protocol.Message, 3)
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
	backend := &refreshBackend{make(chan protocol.Event), make(chan struct{})}
	finished := make(chan error, 1)
	order := []string{}
	go func() {
		finished <- serveRefreshing(ctx, p, backend, protocol.Machine{ID: "test"}, map[string]protocol.Result{}, &order, 10*time.Millisecond)
	}()
	for i := 0; i < 3; i++ {
		select {
		case msg := <-received:
			if msg.Type != "announce" || msg.Version != protocol.Version || msg.Epoch != "epoch" || msg.Sequence != 7 {
				t.Fatalf("invalid snapshot %d: %#v", i, msg)
			}
		case <-time.After(3 * time.Second):
			t.Fatal("periodic snapshot did not arrive on original connection")
		}
	}
	cancel()
	p.Close()
	select {
	case <-finished:
	case <-time.After(time.Second):
		t.Fatal("agent did not stop")
	}
}
