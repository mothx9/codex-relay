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

type slowHistoryBackend struct {
	refreshBackend
	reading chan struct{}
}

func (b *slowHistoryBackend) Execute(ctx context.Context, c protocol.Command) protocol.Result {
	if c.Kind == "history" {
		close(b.reading)
		<-ctx.Done()
	}
	return protocol.Result{ID: c.ID, OK: true}
}
func TestSlowHistoryCannotBlockCurrentTurnControl(t *testing.T) {
	b := &slowHistoryBackend{refreshBackend: refreshBackend{events: make(chan protocol.Event), done: make(chan struct{})}, reading: make(chan struct{})}
	received := make(chan protocol.Message, 1)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		c, err := (&websocket.Upgrader{}).Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer c.Close()
		var announce protocol.Message
		if c.ReadJSON(&announce) != nil {
			return
		}
		_ = c.WriteJSON(protocol.Message{Type: "command", Command: &protocol.Command{ID: "read", Kind: "history"}})
		select {
		case <-b.reading:
		case <-time.After(3 * time.Second):
			return
		}
		_ = c.WriteJSON(protocol.Message{Type: "command", Command: &protocol.Command{ID: "steer", Kind: protocol.Steer}})
		var response protocol.Message
		if c.ReadJSON(&response) == nil {
			received <- response
		}
	}))
	defer server.Close()
	c, _, err := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(server.URL, "http"), nil)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	p := protocol.NewPeer(c)
	go p.WriteLoop(ctx)
	finished := make(chan error, 1)
	order := []string{}
	go func() { finished <- serve(ctx, p, b, protocol.Machine{ID: "m"}, map[string]protocol.Result{}, &order) }()
	defer func() { cancel(); p.Close(); <-finished }()
	select {
	case result := <-received:
		if result.Result == nil || result.Result.ID != "steer" || !result.Result.OK {
			t.Fatal("control did not bypass read", result)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("control stalled behind a read")
	}
}
