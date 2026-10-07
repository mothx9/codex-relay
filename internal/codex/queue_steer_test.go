package codex

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gorilla/websocket"
	"github.com/mothx9/codex-relay/internal/protocol"
)

func TestQueueSteerConsumesOnlySelectedInputWithoutNewIdentity(t *testing.T) {
	for _, scenario := range []string{"success", "stale", "already-dispatched", "turn-changed", "uncertain-delete"} {
		t.Run(scenario, func(t *testing.T) {
			mutations := make(chan string, 4)
			input := []json.RawMessage{json.RawMessage(`{"type":"text","text":"do this now","text_elements":[]}`), json.RawMessage(`{"type":"image","url":"data:image/png;base64,owned-image"}`)}
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				conn, err := (&websocket.Upgrader{CheckOrigin: func(*http.Request) bool { return true }}).Upgrade(w, r, nil)
				if err != nil {
					return
				}
				defer conn.Close()
				removed := false
				for {
					var m rpcMessage
					if conn.ReadJSON(&m) != nil {
						return
					}
					if m.Method == "initialized" {
						continue
					}
					var result any = map[string]any{}
					switch m.Method {
					case "thread/queue/list":
						data := []any{map[string]any{"id": "later", "clientUserMessageId": "later-client", "input": []map[string]any{{"type": "text", "text": "later"}}}}
						if !removed {
							data = append(data, map[string]any{"id": "selected", "clientUserMessageId": "original-client", "input": input})
						}
						result = map[string]any{"data": data}
					case "thread/queue/delete":
						mutations <- m.Method
						var p struct {
							ID string `json:"queuedSubmissionId"`
						}
						_ = json.Unmarshal(m.Params, &p)
						if p.ID != "selected" {
							t.Error("deleted a different queued item")
						}
						if scenario == "uncertain-delete" {
							conn.Close()
							return
						}
						removed = scenario != "already-dispatched"
						result = map[string]any{"deleted": removed}
					case "turn/steer":
						mutations <- m.Method
						var p struct {
							Client string            `json:"clientUserMessageId"`
							Turn   string            `json:"expectedTurnId"`
							Input  []json.RawMessage `json:"input"`
						}
						_ = json.Unmarshal(m.Params, &p)
						if !removed || p.Client != "original-client" || p.Turn != "active" || queueRevision(p.Input) != queueRevision(input) {
							t.Error("lost input, identity or removal precondition")
						}
						if scenario == "turn-changed" {
							_ = conn.WriteJSON(map[string]any{"id": m.ID, "error": map[string]any{"code": -32000, "message": "expected turn mismatch"}})
							continue
						}
					case "thread/queue/add", "turn/start", "thread/queue/update":
						t.Error("unexpected mutation", m.Method)
					}
					if conn.WriteJSON(map[string]any{"id": m.ID, "result": result}) != nil {
						return
					}
				}
			}))
			defer srv.Close()
			a, err := Open(context.Background(), Config{MachineID: "m", Endpoint: "ws" + strings.TrimPrefix(srv.URL, "http")})
			if err != nil {
				t.Fatal(err)
			}
			defer a.Close()
			a.mu.Lock()
			a.sessions["t"] = protocol.Session{ID: "m~t", ThreadID: "t", Status: protocol.Working, TurnID: "active", Capabilities: protocol.Capabilities{CanSteer: true, CanSteerQueue: true}}
			a.mu.Unlock()
			revision := queueRevision(input)
			if scenario == "stale" {
				revision = "stale"
			}
			result := a.Execute(context.Background(), protocol.Command{ID: "promotion", Kind: protocol.QueueSteer, ThreadID: "t", TurnID: "active", QueueID: "selected", QueueClientID: "original-client", QueueRevision: revision})
			want := 2
			switch scenario {
			case "success":
				if !result.OK || !result.QueueRemoved || len(result.FollowUps) != 1 || result.FollowUps[0].ClientID != "later-client" {
					t.Fatal(result)
				}
			case "stale":
				want = 0
				if result.ErrorCode != protocol.QueueChanged || result.QueueRemoved {
					t.Fatal(result)
				}
			case "already-dispatched":
				want = 1
				if result.ErrorCode != protocol.QueueChanged || result.QueueRemoved {
					t.Fatal(result)
				}
			case "uncertain-delete":
				want = 1
				if result.ErrorCode != protocol.UnknownOutcome || result.QueueRemoved {
					t.Fatal(result)
				}
			case "turn-changed":
				if result.OK || !result.QueueRemoved || result.ErrorCode != protocol.TurnChanged {
					t.Fatal(result)
				}
			}
			if len(mutations) != want {
				t.Fatalf("mutations %d, want %d", len(mutations), want)
			}
		})
	}
}
