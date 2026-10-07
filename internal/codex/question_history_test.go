package codex

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"github.com/mothx9/codex-relay/internal/protocol"
)

// A transcript question is not a pending server RPC. In Codex 0.160.1 the
// terminal's async editor is client-local, ignores replay, and clears at turn
// end. Missing an exact reply envelope does not establish currentness.
func TestReconnectAndHistoryDoNotResurrectAsyncQuestions(t *testing.T) {
	for _, blocking := range []bool{false, true} {
		name := "history_only"
		if blocking {
			name = "with_real_pending_rpc"
		}
		t.Run(name, func(t *testing.T) {
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
					metadata := map[string]any{"id": "t", "name": "Existing work", "status": map[string]string{"type": "active"}, "canAcceptDirectInput": true}
					var result any = map[string]any{}
					switch m.Method {
					case "thread/list":
						result = map[string]any{"data": []any{metadata}}
					case "thread/loaded/list":
						result = map[string]any{"data": []string{"t"}}
					case "thread/resume", "thread/read":
						if blocking && m.Method == "thread/resume" {
							_ = c.WriteJSON(map[string]any{"id": "real-request", "method": "item/tool/requestUserInput", "params": map[string]any{"threadId": "t", "turnId": "current", "questions": []any{map[string]string{"id": "choice", "question": "Current decision?"}}}})
						}
						result = map[string]any{"thread": metadata}
					case "thread/turns/list":
						result = map[string]any{"data": []any{map[string]string{"id": "current", "status": "inProgress"}}}
					case "thread/items/list":
						// An unanswered historical batch from completed/interrupted work.
						// Reading it again, including after reconnect, must be display-only.
						result = map[string]any{"data": []any{map[string]any{"turnId": "old", "item": json.RawMessage(`{"type":"agentMessage","id":"old-question","delivery":"async","questions":[{"title":"Old setup question?"},{"title":"Old scope question?"}]}`)}}}
					case "thread/queue/list":
						result = map[string]any{"data": []any{}}
					}
					if c.WriteJSON(map[string]any{"id": m.ID, "result": result}) != nil {
						return
					}
				}
			}))
			defer srv.Close()
			for reconnect := 0; reconnect < 2; reconnect++ {
				a, err := Open(context.Background(), Config{MachineID: "m", Endpoint: "ws" + strings.TrimPrefix(srv.URL, "http")})
				if err != nil {
					t.Fatal(err)
				}
				func() {
					defer a.Close()
					ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
					defer cancel()
					for refresh := 0; refresh < 2; refresh++ {
						sessions, requests, err := a.Snapshot(ctx)
						if err != nil {
							t.Fatal(err)
						}
						wantCount, wantState := 0, protocol.Working
						if blocking {
							wantCount, wantState = 1, protocol.NeedsYou
						}
						if len(requests) != wantCount || len(sessions) != 1 || sessions[0].Status != wantState {
							t.Fatalf("history altered canonical state: sessions=%v requests=%v", sessions, requests)
						}
						history, _, err := a.history(ctx, "t", "")
						if err != nil || len(history) != 1 || len(history[0].Questions) != 2 {
							t.Fatalf("question history must remain readable: %v %v", history, err)
						}
					}
				}()
			}
		})
	}
}
