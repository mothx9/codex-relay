package codex

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/gorilla/websocket"
	"github.com/mothx9/codex-relay/internal/protocol"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestInstalledWaitingFlagsAndPendingOverride(t *testing.T) {
	for _, flag := range []string{"waitingOnApproval", "waitingOnUserInput", "waitingForApproval", "waitingForUserInput"} {
		if Normalize("active", []string{flag}) != protocol.NeedsYou {
			t.Fatalf("unrecognized waiting flag %s", flag)
		}
	}
	a := &Adapter{requests: map[string]pending{"r": {Request: protocol.PendingRequest{ThreadID: "t", Kind: "user_input"}}}}
	s := a.capabilities(protocol.Session{ThreadID: "t", Status: protocol.Working})
	if s.Status != protocol.NeedsYou || !s.Capabilities.CanAnswer {
		t.Fatal("status update obscured pending request")
	}
}

func TestSnapshotPagedLoadedAndPendingOutsideCatalogue(t *testing.T) {
	for _, failAttach := range []bool{false, true} {
		t.Run(fmt.Sprint(failAttach), func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
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
						continue
					}
					var params map[string]any
					_ = json.Unmarshal(m.Params, &params)
					result := any(map[string]any{})
					switch m.Method {
					case "thread/list":
						result = map[string]any{"data": []any{}}
					case "thread/loaded/list":
						if params["cursor"] == "second" {
							result = map[string]any{"data": []string{"b"}}
						} else {
							result = map[string]any{"data": []string{"a"}, "nextCursor": "second"}
						}
					case "thread/resume", "thread/read":
						if failAttach {
							_ = c.WriteJSON(map[string]any{"id": m.ID, "error": map[string]any{"code": -32000, "message": "unavailable"}})
							continue
						}
						id := params["threadId"].(string)
						result = map[string]any{"thread": map[string]any{"id": id, "status": map[string]any{"type": "active"}, "canAcceptDirectInput": true}}
					case "thread/turns/list", "thread/queue/list":
						result = map[string]any{"data": []any{}}
					}
					if c.WriteJSON(map[string]any{"id": m.ID, "result": result}) != nil {
						return
					}
				}
			}))
			defer srv.Close()
			a, err := Open(context.Background(), Config{Endpoint: "ws" + strings.TrimPrefix(srv.URL, "http"), MachineID: "m"})
			if err != nil {
				t.Fatal(err)
			}
			defer a.Close()
			a.mu.Lock()
			a.requests["r"] = pending{Request: protocol.PendingRequest{ID: "r", MachineID: "m", SessionID: "m~ancient", ThreadID: "ancient", Kind: "user_input"}}
			a.mu.Unlock()
			sessions, requests, err := a.Snapshot(context.Background())
			if failAttach {
				if err == nil {
					t.Fatal("incomplete replay admitted online")
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if len(sessions) != 3 || len(requests) != 1 {
				t.Fatalf("lost live or pending thread: %d %d", len(sessions), len(requests))
			}
			found := false
			for _, s := range sessions {
				if s.ThreadID == "ancient" {
					found = s.Status == protocol.NeedsYou
				}
			}
			if !found {
				t.Fatal("pending outside catalogue not hot")
			}
		})
	}
}
