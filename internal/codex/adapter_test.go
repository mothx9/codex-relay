package codex

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/gorilla/websocket"
	"github.com/mothx9/codex-relay/internal/protocol"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"
)

func TestNormalize(t *testing.T) {
	for _, c := range []struct {
		raw   string
		flags []string
		want  string
	}{{"active", nil, protocol.Working}, {"active", []string{"waitingForApproval"}, protocol.NeedsYou}, {"active", []string{"waitingForUserInput"}, protocol.NeedsYou}, {"idle", nil, protocol.Ready}, {"notLoaded", nil, protocol.Inactive}, {"systemError", nil, protocol.Failed}, {"future", nil, protocol.Inactive}} {
		if got := Normalize(c.raw, c.flags); got != c.want {
			t.Errorf("%s: %s", c.raw, got)
		}
	}
}
func TestAdapterRoutingAndApproval(t *testing.T) {
	calls := make(chan rpcMessage, 32)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		c, e := (&websocket.Upgrader{}).Upgrade(w, r, nil)
		if e != nil {
			return
		}
		defer c.Close()
		active := false
		for {
			var m rpcMessage
			if c.ReadJSON(&m) != nil {
				return
			}
			if m.Method == "initialized" {
				continue
			}
			calls <- m
			if m.Method == "" {
				_ = c.WriteJSON(map[string]any{"method": "serverRequest/resolved", "params": map[string]any{"threadId": "t", "requestId": 9}})
				continue
			}
			result := any(map[string]any{})
			st := "idle"
			if active {
				st = "active"
			}
			th := map[string]any{"id": "t", "name": "test", "cwd": "/tmp/test", "status": map[string]any{"type": st}, "canAcceptDirectInput": true, "updatedAt": time.Now().Unix()}
			switch m.Method {
			case "thread/list":
				result = map[string]any{"data": []any{th}}
			case "thread/loaded/list":
				result = map[string]any{"data": []string{"t"}}
			case "thread/read", "thread/resume":
				result = map[string]any{"thread": th}
			case "thread/turns/list":
				data := []any{}
				if active {
					data = append(data, map[string]any{"id": "turn", "status": "inProgress"})
				}
				result = map[string]any{"data": data}
			case "thread/items/list":
				result = map[string]any{"data": []any{map[string]any{"turnId": "turn", "item": map[string]any{"type": "agentMessage", "id": "i", "text": "real protocol fixture"}}}}
			}
			if c.WriteJSON(map[string]any{"id": m.ID, "result": result}) != nil {
				return
			}
			if m.Method == "turn/start" {
				active = true
				_ = c.WriteJSON(map[string]any{"method": "turn/started", "params": map[string]any{"threadId": "t", "turn": map[string]any{"id": "turn", "status": "inProgress"}}})
				_ = c.WriteJSON(map[string]any{"id": 9, "method": "item/commandExecution/requestApproval", "params": map[string]any{"threadId": "t", "turnId": "turn", "itemId": "cmd", "command": "printf approved", "cwd": "/tmp/test", "reason": "test", "startedAtMs": time.Now().UnixMilli()}})
			}
		}
	}))
	defer srv.Close()
	ctx := context.Background()
	a, e := Open(ctx, Config{Endpoint: "ws" + strings.TrimPrefix(srv.URL, "http"), MachineID: "m"})
	if e != nil {
		t.Fatal(e)
	}
	defer a.Close()
	sessions, _, e := a.Snapshot(ctx)
	if e != nil || len(sessions) != 1 || sessions[0].ReadOnly {
		t.Fatalf("snapshot: %+v %v", sessions, e)
	}
	r := a.Execute(ctx, protocol.Command{ID: "start-id", Kind: "start", ThreadID: "t", Text: "hello"})
	if !r.OK {
		t.Fatal(r)
	}
	var req protocol.PendingRequest
	deadline := time.After(3 * time.Second)
	for req.ID == "" {
		select {
		case ev := <-a.Events():
			if ev.Request != nil {
				req = *ev.Request
			}
		case <-deadline:
			t.Fatal("missing request")
		}
	}
	for _, kind := range []string{"steer", "queue", "interrupt"} {
		r = a.Execute(ctx, protocol.Command{ID: kind, Kind: kind, ThreadID: "t", Text: "message", TurnID: "turn"})
		if !r.OK {
			t.Fatal(r)
		}
	}
	r = a.Execute(ctx, protocol.Command{ID: "history", Kind: "history", ThreadID: "t"})
	if !r.OK || len(r.History) != 1 || r.History[0].Text != "real protocol fixture" {
		t.Fatal(r)
	}
	r = a.Execute(ctx, protocol.Command{ID: "answer", Kind: "respond", ThreadID: "t", RequestID: req.ID, Decision: "approve"})
	if !r.OK {
		t.Fatal(r)
	}
	resolved := false
	for !resolved {
		select {
		case ev := <-a.Events():
			resolved = ev.Kind == "request_resolved"
		case <-deadline:
			t.Fatal("missing resolution")
		}
	}
	if a.Execute(ctx, protocol.Command{Kind: "respond", ThreadID: "t", RequestID: req.ID, Decision: "approve"}).OK {
		t.Fatal("request replay accepted")
	}
	seen := map[string]rpcMessage{}
	for len(calls) > 0 {
		m := <-calls
		seen[m.Method] = m
	}
	for _, method := range []string{"turn/start", "turn/steer", "turn/interrupt", "thread/queue/add"} {
		if _, ok := seen[method]; !ok {
			t.Error("missing", method)
		}
	}
	var steer struct {
		Expected string `json:"expectedTurnId"`
	}
	_ = json.Unmarshal(seen["turn/steer"].Params, &steer)
	if steer.Expected != "turn" {
		t.Fatal("steer missing precondition")
	}
}
func TestRealCodexDiscovery(t *testing.T) {
	if os.Getenv("RELAY_REAL_CODEX") != "1" {
		t.Skip("set RELAY_REAL_CODEX=1 for optional authenticated local daemon test")
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	a, e := Open(ctx, Config{MachineID: "integration"})
	if e != nil {
		t.Fatal(e)
	}
	defer a.Close()
	s, _, e := a.Snapshot(ctx)
	if e != nil {
		t.Fatal(e)
	}
	t.Logf("real daemon: %d sessions", len(s))
	if len(s) == 0 {
		t.Fatal("no sessions")
	}
	for _, v := range s {
		if !v.ReadOnly {
			r := a.Execute(ctx, protocol.Command{Kind: "history", ThreadID: v.ThreadID})
			if !r.OK {
				t.Fatal(r.Error)
			}
			t.Logf("recent context: %d items", len(r.History))
			return
		}
	}
	t.Log("all sessions currently read-only")
}

type captureTransport struct{ messages []json.RawMessage }

func (c *captureTransport) Read() (rpcMessage, error) { return rpcMessage{}, nil }
func (c *captureTransport) Write(v any) error {
	b, e := json.Marshal(v)
	c.messages = append(c.messages, b)
	return e
}
func (c *captureTransport) Close() error { return nil }
func TestStructuredResponsesAndFileContext(t *testing.T) {
	tr := &captureTransport{}
	a := &Adapter{cfg: Config{MachineID: "m"}, t: tr, sessions: map[string]protocol.Session{"t": {ID: "m~t", MachineID: "m", ThreadID: "t", Cwd: "/tmp/test"}}, requests: map[string]pending{}, items: map[string]protocol.Activity{}, events: make(chan protocol.Event, 32), done: make(chan struct{}), subscribed: map[string]bool{}, epoch: "epoch"}
	raw := json.RawMessage(`{"threadId":"t","turnId":"turn","item":{"id":"file","type":"fileChange","changes":[{"path":"/tmp/test/example.go","kind":{"type":"update"},"diff":"+added line"}]}}`)
	a.handle(rpcMessage{Method: "item/started", Params: raw})
	requests := []struct {
		method, params string
		decision       string
		answers        map[string][]string
		want           string
	}{
		{"item/fileChange/requestApproval", `{"threadId":"t","turnId":"turn","itemId":"file"}`, "approve", nil, `"decision":"accept"`},
		{"item/permissions/requestApproval", `{"threadId":"t","turnId":"turn","itemId":"perm","permissions":{"network":{"enabled":true}}}`, "approve", nil, `"scope":"turn"`},
		{"item/tool/requestUserInput", `{"threadId":"t","turnId":"turn","itemId":"input","isBlocking":true,"questions":[{"id":"q","header":"Choice","question":"Choose?","options":[]}]}`, "approve", map[string][]string{"q": {"answer"}}, `"answers":{"q":{"answers":["answer"]}}`},
	}
	for i, c := range requests {
		rid := json.RawMessage(fmt.Sprint(i + 10))
		a.handle(rpcMessage{ID: rid, Method: c.method, Params: json.RawMessage(c.params)})
		request := a.requests[a.requestID(rid)].Request
		if c.method == "item/fileChange/requestApproval" && !strings.Contains(request.Operation, "example.go") {
			t.Fatal("approval missing changed files")
		}
		if e := a.respond(protocol.Command{ThreadID: "t", RequestID: request.ID, Decision: c.decision, Answers: c.answers}); e != nil {
			t.Fatal(e)
		}
		if !strings.Contains(string(tr.messages[len(tr.messages)-1]), c.want) {
			t.Fatal("bad response", string(tr.messages[len(tr.messages)-1]))
		}
		if a.respond(protocol.Command{ThreadID: "t", RequestID: request.ID, Decision: c.decision, Answers: c.answers}) == nil {
			t.Fatal("reused request")
		}
	}
	a.handle(rpcMessage{ID: json.RawMessage(`30`), Method: "item/fileChange/requestApproval", Params: json.RawMessage(`{"threadId":"t","turnId":"turn","itemId":"missing"}`)})
	if a.requests[a.requestID(json.RawMessage(`30`))].Request.CanApprove {
		t.Fatal("approved file changes without context")
	}
}
