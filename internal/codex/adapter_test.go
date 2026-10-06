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

func TestAsyncQuestionAgentMessagePreservesCanonicalDisplayContext(t *testing.T) {
	for _, text := range []string{"", "Review the options below."} {
		raw, _ := json.Marshal(map[string]any{"type": "agentMessage", "id": "canonical-question", "text": text, "questions": []map[string]any{{"title": "Which scope?", "options": []string{"Minimal", "Complete"}}}})
		v := activity(raw)
		if v.ID != "canonical-question" || v.Kind != "agentMessage" || len(v.Questions) != 1 || v.Questions[0].Title != "Which scope?" || len(v.Questions[0].Options) != 2 || v.Truncated {
			t.Fatal("canonical async question context lost", v)
		}
		if text == "" && v.Text != "Which scope?" {
			t.Fatal("question-only messages would be dropped")
		}
		if text != "" && v.Text != text {
			t.Fatal("assistant text replaced")
		}
		wire, _ := json.Marshal(v)
		var decoded protocol.Activity
		if json.Unmarshal(wire, &decoded) != nil || len(decoded.Questions) != 1 {
			t.Fatal("question lost at Relay JSON boundary")
		}
	}
	a := &Adapter{cfg: Config{MachineID: "m"}, sessions: map[string]protocol.Session{"t": {ID: "m~t", ThreadID: "t", Status: protocol.Working, TurnID: "active"}}, requests: map[string]pending{}, events: make(chan protocol.Event, 8), done: make(chan struct{}), queue: true}
	a.handle(rpcMessage{Method: "item/completed", Params: json.RawMessage(`{"threadId":"t","turnId":"active","item":{"type":"agentMessage","id":"question","text":"","questions":[{"title":"Which scope?","options":["Minimal","Complete"]}]}}`)})
	ev := <-a.Events()
	if ev.Kind != "activity" || ev.Activity == nil || len(ev.Activity.Questions) != 1 {
		t.Fatal("question-only live event dropped")
	}
	if len(a.requests) != 0 || a.sessions["t"].Status != protocol.Working || a.sessions["t"].Capabilities.CanAnswer {
		t.Fatal("display question invented a pending RPC or changed turn state")
	}
}

func TestAsyncQuestionContextIsBoundedAndMarkedPartial(t *testing.T) {
	questions := make([]protocol.AsyncQuestion, 30)
	for i := range questions {
		questions[i] = protocol.AsyncQuestion{Title: strings.Repeat("é", 2048), Options: []string{strings.Repeat("x", 1024), strings.Repeat("y", 1024)}}
	}
	raw, _ := json.Marshal(map[string]any{"type": "agentMessage", "id": "bounded-question", "questions": questions})
	v := activity(raw)
	bytes := 0
	for _, q := range v.Questions {
		bytes += len(q.Title)
		for _, o := range q.Options {
			bytes += len(o)
		}
	}
	if !v.Truncated || bytes+len(v.Text) > protocol.MaxText || len(v.Questions) > 8 {
		t.Fatal("question display escaped bounds", bytes, len(v.Questions))
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
				_ = c.WriteJSON(map[string]any{"method": "thread/status/changed", "params": map[string]any{"threadId": "t", "status": map[string]any{"type": "active"}}})
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
			case "thread/queue/list":
				result = map[string]any{"data": []any{}}
			case "thread/queue/add":
				var params struct {
					ClientID string `json:"clientUserMessageId"`
				}
				_ = json.Unmarshal(m.Params, &params)
				result = map[string]any{"queuedSubmission": map[string]any{"id": "queue-id", "clientUserMessageId": params.ClientID}}
			case "thread/items/list":
				var params struct {
					Cursor string `json:"cursor"`
				}
				_ = json.Unmarshal(m.Params, &params)
				if params.Cursor == "older-page" {
					result = map[string]any{"data": []any{map[string]any{"turnId": "old-turn", "item": map[string]any{"type": "agentMessage", "id": "old", "text": "previous canonical page"}}}}
				} else {
					result = map[string]any{"data": []any{map[string]any{"turnId": "turn", "item": map[string]any{"type": "agentMessage", "id": "i", "text": "real protocol fixture"}}}, "nextCursor": "older-page"}
				}
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
	r = a.Execute(ctx, protocol.Command{ID: "history", Kind: "history", ThreadID: "t"})
	if !r.OK || len(r.History) != 1 || r.History[0].Text != "real protocol fixture" {
		t.Fatal(r)
	}
	if r.HistoryCursor != "older-page" {
		t.Fatal("canonical history cursor lost", r.HistoryCursor)
	}
	r = a.Execute(ctx, protocol.Command{ID: "older-history", Kind: "history", ThreadID: "t", HistoryCursor: r.HistoryCursor})
	if !r.OK || len(r.History) != 1 || r.History[0].ID != "old" || r.HistoryCursor != "" {
		t.Fatal("history pagination failed", r)
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
	for {
		a.mu.Lock()
		working := a.sessions["t"].Status == protocol.Working
		a.mu.Unlock()
		if working {
			break
		}
		select {
		case <-a.Events():
		case <-deadline:
			t.Fatal("missing working status after answer")
		}
	}
	for _, kind := range []string{"steer", "queue", "interrupt"} {
		r = a.Execute(ctx, protocol.Command{ID: kind, Kind: kind, ThreadID: "t", Text: "message", TurnID: "turn"})
		if !r.OK {
			t.Fatal(r)
		}
		if kind == "queue" {
			a.mu.Lock()
			status, turnID := a.sessions["t"].Status, a.sessions["t"].TurnID
			a.mu.Unlock()
			if r.QueueID != "queue-id" || status != protocol.Working || turnID != "turn" {
				t.Fatal("queue ACK changed turn lifecycle", r)
			}
		}
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

func TestNativeIdentityAndQueueSignal(t *testing.T) {
	a := &Adapter{cfg: Config{MachineID: "m"}, sessions: map[string]protocol.Session{"t": {ID: "m~t", ThreadID: "t", Status: protocol.Ready}}, requests: map[string]pending{}, subscribed: map[string]bool{"t": true}, events: make(chan protocol.Event, 16), done: make(chan struct{}), queueSignals: make(chan string, 2), queue: true}
	a.handle(rpcMessage{Method: "thread/queue/changed", Params: json.RawMessage(`{"threadId":"t"}`)})
	if <-a.queueSignals != "t" {
		t.Fatal("queue signal lost")
	}
	a.handle(rpcMessage{Method: "turn/started", Params: json.RawMessage(`{"threadId":"t","turn":{"id":"next","status":"inProgress","items":[{"type":"userMessage","id":"real-item","clientId":"command-id","content":[{"type":"text","text":"follow-up"}]}]}}`)})
	ev := <-a.Events()
	if ev.Kind != "turn_started" || ev.ClientID != "command-id" || !ev.Session.Capabilities.CanSteer {
		t.Fatal(ev)
	}
	ev = <-a.Events()
	if ev.Activity == nil || ev.Activity.ClientID != "command-id" || ev.Activity.ID != "real-item" {
		t.Fatal(ev)
	}
	if v := activity(json.RawMessage(`{"type":"userMessage","id":"real-item","clientId":"command-id","content":[{"type":"text","text":"follow-up"}]}`)); v.ClientID != "command-id" {
		t.Fatal(v)
	}
	a.handle(rpcMessage{Method: "item/started", Params: json.RawMessage(`{"threadId":"t","turnId":"next","item":{"type":"userMessage","id":"real-item","clientId":"command-id","content":[{"type":"text","text":"follow-up"}]}}`)})
	if ev := <-a.Events(); ev.Kind != "message_dispatched" || ev.ClientID != "command-id" {
		t.Fatal(ev)
	}
	if ev := <-a.Events(); ev.Kind != "activity" || ev.Activity.ClientID != "command-id" {
		t.Fatal(ev)
	}
}

func TestAdapterCanonicalErrorMapping(t *testing.T) {
	a := &Adapter{sessions: map[string]protocol.Session{}, requests: map[string]pending{}, events: make(chan protocol.Event, 16), done: make(chan struct{}), queue: true}
	code := a.errorCode(protocol.Command{Kind: protocol.Steer}, &rpcError{Code: -32000, Message: "expected turn ID mismatch: PRIVATE_PROMPT_CANARY"})
	if code != protocol.TurnChanged {
		t.Fatal(code)
	}
	result := protocol.Failure(protocol.Command{ID: "id"}, code)
	if strings.Contains(result.Error, "PRIVATE") {
		t.Fatal("raw backend error leaked")
	}
	if code = a.errorCode(protocol.Command{Kind: protocol.FollowUpCommand}, &rpcError{Code: -32601, Message: "unknown method"}); code != protocol.FollowUpUnavailable || a.queue {
		t.Fatal(code)
	}
}

func TestPendingAnswerIndependentOfDirectInput(t *testing.T) {
	a := &Adapter{requests: map[string]pending{
		"request": {Request: protocol.PendingRequest{ThreadID: "t", Kind: "user_input"}},
	}, queue: true}
	s := a.capabilities(protocol.Session{ThreadID: "t", ReadOnly: true, Status: protocol.NeedsYou, TurnID: "active"})
	if !s.Capabilities.CanAnswer || s.Capabilities.CanSend || s.Capabilities.CanSteer || s.Capabilities.CanFollowUp {
		t.Fatal("server request must allow an answer without granting direct input", s.Capabilities)
	}
	p := a.requests["request"]
	p.Sent = true
	a.requests["request"] = p
	if a.capabilities(s).Capabilities.CanAnswer {
		t.Fatal("answered request still grants answer capability")
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

func TestRealCodexRoundTrip(t *testing.T) {
	if os.Getenv("RELAY_REAL_CODEX_TURN") != "1" {
		t.Skip("set RELAY_REAL_CODEX_TURN=1; creates an isolated thread and consumes two small Codex turns")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()
	primary, e := Open(ctx, Config{MachineID: "primary"})
	if e != nil {
		t.Fatal(e)
	}
	defer primary.Close()
	raw, e := primary.rpc(ctx, "thread/start", map[string]any{"cwd": t.TempDir(), "sandbox": "read-only", "approvalPolicy": "on-request", "approvalsReviewer": "user", "developerInstructions": "This is a bounded transport validation. Do not use tools, modify files or delegate."})
	if e != nil {
		t.Fatal(e)
	}
	var r struct {
		Thread thread `json:"thread"`
	}
	if e = decode(raw, &r); e != nil {
		t.Fatal(e)
	}
	defer func() {
		_, _ = primary.rpc(context.Background(), "thread/archive", map[string]any{"threadId": r.Thread.ID})
	}()
	// Codex cannot resume a newly allocated zero-turn thread before its first rollout exists.
	_, e = primary.rpc(ctx, "turn/start", map[string]any{"threadId": r.Thread.ID, "input": []map[string]any{{"type": "text", "text": "Reply exactly RELAY_PRIMED without tools.", "text_elements": []any{}}}})
	if e != nil {
		t.Fatal(e)
	}
	primed := false
	for !primed {
		select {
		case <-ctx.Done():
			t.Fatal(ctx.Err())
		case event := <-primary.Events():
			if event.SessionID == protocol.SessionID("primary", r.Thread.ID) && event.Kind == "turn_completed" {
				primed = true
			}
			if event.Kind == "failed" {
				t.Fatal("priming turn failed")
			}
		}
	}
	secondary, e := Open(ctx, Config{MachineID: "secondary"})
	if e != nil {
		t.Fatal(e)
	}
	defer secondary.Close()
	s, e := secondary.attach(ctx, r.Thread.ID)
	if e != nil || s.ReadOnly {
		t.Fatalf("second client attach: %+v %v", s, e)
	}
	result := secondary.Execute(ctx, protocol.Command{ID: protocol.ID(), Kind: "start", ThreadID: s.ThreadID, SessionID: s.ID, Text: "Reply exactly CODEX_RELAY_ROUND_TRIP_OK without tools."})
	if !result.OK {
		t.Fatal(result.Error)
	}
	text := ""
	working := false
	for {
		select {
		case <-ctx.Done():
			t.Fatal(ctx.Err())
		case e := <-secondary.Events():
			if e.SessionID != s.ID {
				continue
			}
			switch e.Kind {
			case "turn_started":
				working = true
			case "delta":
				text += e.Text
			case "failed":
				t.Fatal("real turn failed")
			case "turn_completed":
				if !working || !strings.Contains(text, "CODEX_RELAY_ROUND_TRIP_OK") {
					t.Fatalf("missing stream or lifecycle: working=%v marker=%v", working, strings.Contains(text, "CODEX_RELAY_ROUND_TRIP_OK"))
				}
				t.Log("real thread: second client start, streaming and completion verified")
				return
			}
		}
	}
}
