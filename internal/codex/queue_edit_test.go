package codex

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/gorilla/websocket"
	"github.com/mothx9/codex-relay/internal/protocol"
)

func TestQueueEditKeepsCanonicalIdentityAndRejectsStaleContent(t *testing.T) {
	var edits atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		c, err := (&websocket.Upgrader{CheckOrigin: func(*http.Request) bool { return true }}).Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer c.Close()
		text := "original"
		for {
			var m rpcMessage
			if c.ReadJSON(&m) != nil {
				return
			}
			if m.Method == "initialized" {
				continue
			}
			entry := func() map[string]any {
				return map[string]any{"id": "queue-1", "clientUserMessageId": "client-1", "input": []map[string]any{{"type": "text", "text": text}}}
			}
			var result any = map[string]any{}
			switch m.Method {
			case "thread/queue/list":
				result = map[string]any{"data": []any{entry()}}
			case "thread/queue/update":
				var params struct {
					QueueID string `json:"queuedSubmissionId"`
					Input   []struct {
						Text string `json:"text"`
					} `json:"input"`
				}
				if json.Unmarshal(m.Params, &params) != nil || params.QueueID != "queue-1" || len(params.Input) != 1 {
					return
				}
				text = params.Input[0].Text
				edits.Add(1)
				result = map[string]any{"queuedSubmission": entry()}
			case "thread/queue/add", "thread/queue/delete", "turn/steer", "turn/start":
				t.Error("editing issued an unrelated mutation", m.Method)
				return
			}
			if c.WriteJSON(map[string]any{"id": m.ID, "result": result}) != nil {
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
	a.sessions["t"] = protocol.Session{ID: "m~t", ThreadID: "t", Status: protocol.Working, Capabilities: protocol.Capabilities{CanEditQueue: true}}
	a.mu.Unlock()
	queue, err := a.nativeQueue(context.Background(), "t")
	if err != nil || len(queue) != 1 {
		t.Fatal(queue, err)
	}
	original := queue[0]
	c := protocol.Command{ID: "edit", Kind: protocol.QueueUpdate, SessionID: "m~t", ThreadID: "t", QueueID: original.ID, QueueClientID: original.ClientID, QueueRevision: original.Revision, Text: "corrected"}
	result := a.Execute(context.Background(), c)
	if !result.OK || result.QueueID != original.ID || len(result.FollowUps) != 1 || result.FollowUps[0].ClientID != original.ClientID || result.FollowUps[0].Text != "corrected" {
		t.Fatal(result)
	}
	if result.FollowUps[0].Revision == original.Revision {
		t.Fatal("content revision did not change")
	}
	result = a.Execute(context.Background(), c)
	if result.ErrorCode != protocol.QueueChanged || edits.Load() != 1 {
		t.Fatal("stale edit reached backend", result, edits.Load())
	}
	c.QueueID = "already-dispatched"
	if result = a.Execute(context.Background(), c); result.ErrorCode != protocol.QueueChanged {
		t.Fatal(result)
	}
	if edits.Load() != 1 {
		t.Fatal("duplicate queue mutation")
	}
}
