package codex

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

func TestUnarchiveSubscribesAndPendingReplayRetainsSessionContext(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		c, err := (&websocket.Upgrader{}).Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer c.Close()
		for {
			var m rpcMessage
			if c.ReadJSON(&m) != nil {
				return
			}
			if m.Method == "initialized" {
				_ = c.WriteJSON(map[string]any{"method": "thread/unarchived", "params": map[string]any{"threadId": "t"}})
				continue
			}
			var result any = map[string]any{"data": []any{}}
			if m.Method == "thread/resume" {
				_ = c.WriteJSON(map[string]any{"id": "question", "method": "item/tool/requestUserInput", "params": map[string]any{"threadId": "t", "turnId": "turn", "itemId": "item", "questions": []any{map[string]any{"id": "choice", "question": "Choose?"}}}})
				result = map[string]any{"thread": map[string]any{"id": "t", "name": "Canonical title", "cwd": "/workspace/example", "canAcceptDirectInput": true, "status": map[string]any{"type": "active"}}}
			}
			if c.WriteJSON(map[string]any{"id": m.ID, "result": result}) != nil {
				return
			}
		}
	}))
	defer server.Close()
	a, err := Open(context.Background(), Config{MachineID: "m", Endpoint: "ws" + strings.TrimPrefix(server.URL, "http")})
	if err != nil {
		t.Fatal(err)
	}
	defer a.Close()
	deadline := time.After(3 * time.Second)
	for {
		select {
		case e := <-a.Events():
			if e.Kind == "session" && e.Session != nil {
				s := e.Session
				if s.ID != "m~t" || s.Title != "Canonical title" || s.Project != "example" || s.Status != protocol.NeedsYou {
					t.Fatalf("replay lost canonical context: %#v", s)
				}
				return
			}
		case <-deadline:
			t.Fatal("unarchived thread was not subscribed without a periodic snapshot")
		}
	}
}
