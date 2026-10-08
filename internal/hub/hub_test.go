package hub

import (
	"context"
	"encoding/json"
	"github.com/gorilla/websocket"
	"github.com/mothx9/codex-relay/internal/agent"
	"github.com/mothx9/codex-relay/internal/codex"
	"github.com/mothx9/codex-relay/internal/protocol"
	"github.com/mothx9/codex-relay/internal/store"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

const testToken = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

func testHub(t *testing.T, path string) (*Hub, *store.Store, *httptest.Server) {
	t.Helper()
	s, e := store.Open(path)
	if e != nil {
		t.Fatal(e)
	}
	h, e := New(s, Config{PublicURL: "http://relay.test", AdminToken: testToken})
	if e != nil {
		t.Fatal(e)
	}
	srv := httptest.NewServer(h.Handler())
	return h, s, srv
}
func testWS(t *testing.T, srv *httptest.Server, headers http.Header, path string) *websocket.Conn {
	t.Helper()
	c, resp, e := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(srv.URL, "http")+path, headers)
	if resp != nil {
		resp.Body.Close()
	}
	if e != nil {
		t.Fatal(e)
	}
	return c
}
func login(t *testing.T, srv *httptest.Server) string {
	t.Helper()
	r, _ := http.NewRequest("POST", srv.URL+"/api/login", strings.NewReader(`{"token":"`+testToken+`"}`))
	r.Header.Set("Origin", "http://relay.test")
	r.Header.Set("X-Relay-CSRF", "1")
	r.Header.Set("Content-Type", "application/json")
	resp, e := http.DefaultClient.Do(r)
	if e != nil {
		t.Fatal(e)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatal(resp.Status)
	}
	if !resp.Cookies()[0].HttpOnly || resp.Cookies()[0].SameSite != http.SameSiteStrictMode {
		t.Fatal("unsafe cookie")
	}
	return resp.Cookies()[0].String()
}
func readUntil(t *testing.T, c *websocket.Conn, fn func(protocol.Message) bool) protocol.Message {
	t.Helper()
	_ = c.SetReadDeadline(time.Now().Add(5 * time.Second))
	for {
		var m protocol.Message
		if e := c.ReadJSON(&m); e != nil {
			t.Fatal(e)
		}
		if fn(m) {
			return m
		}
	}
}
func TestRealtimeAuthOrderingAndPending(t *testing.T) {
	h, s, srv := testHub(t, filepath.Join(t.TempDir(), "db"))
	defer s.Close()
	defer srv.Close()
	defer h.Close()
	_ = s.Token("m", testToken)
	for _, test := range []struct {
		path    string
		headers http.Header
	}{{"/api/agent", http.Header{"X-Relay-Machine": []string{"m"}, "Authorization": []string{"Bearer wrong"}}}, {"/api/ui", http.Header{"Origin": []string{"http://relay.test"}}}} {
		_, resp, e := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(srv.URL, "http")+test.path, test.headers)
		if e == nil || resp.StatusCode != 401 {
			t.Fatal("authentication bypass")
		}
		resp.Body.Close()
	}
	cookie := login(t, srv)
	_, resp, e := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(srv.URL, "http")+"/api/ui", http.Header{"Cookie": []string{cookie}, "Origin": []string{"http://evil.test"}})
	if e == nil || resp.StatusCode != 403 {
		t.Fatal("origin bypass")
	}
	resp.Body.Close()
	ui := testWS(t, srv, http.Header{"Cookie": []string{cookie}, "Origin": []string{"http://relay.test"}}, "/api/ui")
	defer ui.Close()
	readUntil(t, ui, func(m protocol.Message) bool { return m.Type == "snapshot" })
	a := testWS(t, srv, http.Header{"X-Relay-Machine": []string{"m"}, "Authorization": []string{"Bearer " + testToken}}, "/api/agent")
	defer a.Close()
	session := protocol.Session{ID: "m~t", MachineID: "m", ThreadID: "t", Title: "test", Status: protocol.Ready, UpdatedAt: time.Now()}
	_ = a.WriteJSON(protocol.Message{Version: 1, Type: "announce", Machine: &protocol.Machine{ID: "m", Name: "M"}, Sessions: []protocol.Session{session}, Epoch: "epoch"})
	readUntil(t, ui, func(m protocol.Message) bool { return m.Type == "snapshot" && len(m.Snapshot.Sessions) == 1 })
	_ = ui.WriteJSON(protocol.Message{Type: "watch", SessionID: session.ID})
	cmd := readUntil(t, a, func(m protocol.Message) bool { return m.Type == "command" })
	_ = a.WriteJSON(protocol.Message{Type: "result", Result: &protocol.Result{ID: cmd.Command.ID, OK: true, History: []protocol.Activity{{ID: "a", Kind: "agentMessage", Text: "EPHEMERAL_CANARY", Questions: []protocol.AsyncQuestion{{Title: "EPHEMERAL_CANARY question", Options: []string{"Minimal", "Complete"}}}}}}})
	history := readUntil(t, ui, func(m protocol.Message) bool { return m.Type == "result" })
	if len(history.Result.History) != 1 || len(history.Result.History[0].Questions) != 1 {
		t.Fatal("async question lost while routing history")
	}
	session.Status = protocol.Working
	ev := protocol.Event{ID: "event-2", MachineID: "m", SessionID: session.ID, Sequence: 2, Epoch: "epoch", Kind: "session", Session: &session, Timestamp: time.Now()}
	_ = a.WriteJSON(protocol.Message{Type: "event", Event: &ev})
	readUntil(t, ui, func(m protocol.Message) bool { return m.Type == "event" && m.Event.Sequence == 2 })
	ev.Sequence = 1
	ev.ID = "event-1"
	session.Status = protocol.Ready
	_ = a.WriteJSON(protocol.Message{Type: "event", Event: &ev})
	ev.Sequence = 2
	_ = a.WriteJSON(protocol.Message{Type: "event", Event: &ev})
	req := protocol.PendingRequest{ID: "request", MachineID: "m", SessionID: session.ID, ThreadID: "t", Kind: "command_approval", Description: "EPHEMERAL_CANARY", Payload: json.RawMessage(`{"command":"EPHEMERAL_CANARY"}`), ExpiresAt: time.Now().Add(time.Hour), Status: "pending", CanApprove: true}
	ev = protocol.Event{ID: "event-3", MachineID: "m", SessionID: session.ID, Sequence: 3, Epoch: "epoch", Kind: "request", Request: &req, Timestamp: time.Now()}
	_ = a.WriteJSON(protocol.Message{Type: "event", Event: &ev})
	readUntil(t, ui, func(m protocol.Message) bool { return m.Type == "event" && m.Event.Kind == "request" })
	_ = ui.WriteJSON(protocol.Message{Type: "command", Command: &protocol.Command{ID: protocol.ID(), Kind: "respond", SessionID: session.ID, RequestID: req.ID, Decision: "approve"}})
	routed := readUntil(t, a, func(m protocol.Message) bool { return m.Type == "command" })
	if routed.Command.ThreadID != "t" || routed.Command.Decision != "approve" {
		t.Fatal("bad routing")
	}
	_ = ui.WriteJSON(protocol.Message{Type: "command", Command: &protocol.Command{ID: protocol.ID(), Kind: "respond", SessionID: session.ID, RequestID: req.ID, Decision: "approve"}})
	readUntil(t, ui, func(m protocol.Message) bool { return m.Type == "result" && !m.Result.OK })
	// An independent local client resolved it: no command result is needed to retire it.
	ev.Kind = "request_resolved"
	ev.Request = nil
	ev.RequestID = req.ID
	ev.Sequence = 4
	ev.ID = "event-4"
	_ = a.WriteJSON(protocol.Message{Type: "event", Event: &ev})
	readUntil(t, ui, func(m protocol.Message) bool { return m.Type == "event" && m.Event.Kind == "request_resolved" })
	h.mu.Lock()
	if len(h.requests) != 0 || h.sessions[session.ID].Status != protocol.Working {
		t.Error("dedupe/order/resolution failed")
	}
	h.mu.Unlock()
	ev = protocol.Event{ID: "event-5", MachineID: "m", SessionID: session.ID, Sequence: 5, Epoch: "epoch", Kind: "activity", Activity: &protocol.Activity{ID: "question", Kind: "agentMessage", Text: "EPHEMERAL_CANARY", Questions: []protocol.AsyncQuestion{{Title: "EPHEMERAL_CANARY question", Options: []string{"Minimal", "Complete"}}}}, Timestamp: time.Now()}
	_ = a.WriteJSON(protocol.Message{Type: "event", Event: &ev})
	question := readUntil(t, ui, func(m protocol.Message) bool { return m.Type == "event" && m.Event.Sequence == 5 })
	if question.Event.Activity == nil || len(question.Event.Activity.Questions) != 1 || len(question.Event.Activity.Questions[0].Options) != 2 {
		t.Fatal("async question lost on live WebSocket")
	}
	h.mu.Lock()
	if len(h.requests) != 0 || h.sessions[session.ID].Status != protocol.Working {
		t.Error("display question created a pending approval")
	}
	h.mu.Unlock()
	spectator := testWS(t, srv, http.Header{"Cookie": []string{cookie}, "Origin": []string{"http://relay.test"}}, "/api/ui")
	readUntil(t, spectator, func(m protocol.Message) bool { return m.Type == "snapshot" })
	privateMessage := "Selected model is at capacity. Please try a different model."
	session.Status = protocol.Failed
	session.FailureReason = "capacity"
	errorEvent := protocol.Event{ID: "event-6", MachineID: "m", SessionID: session.ID, Sequence: 6, Epoch: "epoch", Kind: "failed", Session: &session, Activity: &protocol.Activity{ID: "turn-error-1", Kind: "turnError", Text: privateMessage}, Timestamp: time.Now()}
	_ = a.WriteJSON(protocol.Message{Type: "event", Event: &errorEvent})
	public := readUntil(t, spectator, func(m protocol.Message) bool { return m.Type == "event" && m.Event.Kind == "failed" })
	if public.Event.Activity != nil || public.Event.Session.FailureReason != "capacity" {
		t.Fatal("failure detail leaked to fleet stream")
	}
	visible := readUntil(t, ui, func(m protocol.Message) bool { return m.Type == "event" && m.Event.Kind == "failed" })
	if visible.Event.Activity != nil {
		t.Fatal("private detail leaked to general event")
	}
	private := readUntil(t, ui, func(m protocol.Message) bool { return m.Type == "pending" && m.Event.Kind == "failed" })
	if private.Event.Activity == nil || private.Event.Activity.Text != privateMessage {
		t.Fatal("selected conversation lost Codex error")
	}
	spectator.Close()
	a.Close()
	readUntil(t, ui, func(m protocol.Message) bool {
		return m.Type == "snapshot" && m.Snapshot.Machines[0].Status == protocol.Offline
	})
	// Re-announcement replaces derived state after reconnect.
	a2 := testWS(t, srv, http.Header{"X-Relay-Machine": []string{"m"}, "Authorization": []string{"Bearer " + testToken}}, "/api/agent")
	defer a2.Close()
	_ = a2.WriteJSON(protocol.Message{Version: 1, Type: "announce", Machine: &protocol.Machine{ID: "m"}, Sessions: []protocol.Session{session}, Epoch: "new-epoch"})
	readUntil(t, ui, func(m protocol.Message) bool {
		return m.Type == "snapshot" && m.Snapshot.Machines[0].Status == protocol.Online
	})
}
func TestRecentBounded(t *testing.T) {
	r := Recent{}
	for i := 0; i < 1000; i++ {
		r.Put(protocol.Activity{ID: protocol.ID(), Text: strings.Repeat("x", 16384)})
	}
	if len(r.Items) > 50 || r.bytes() > 128<<10 {
		t.Fatal("unbounded buffer")
	}
	r.Apply(protocol.Event{Kind: "delta", ItemID: "same", Text: "one"})
	r.Apply(protocol.Event{Kind: "delta", ItemID: "same", Text: "two"})
	if r.Items[len(r.Items)-1].Text != "onetwo" {
		t.Fatal("delta merge")
	}
	r = Recent{}
	for i := 0; i < 50; i++ {
		r.Put(protocol.Activity{ID: protocol.ID(), Text: "question", Questions: []protocol.AsyncQuestion{{Title: strings.Repeat("q", 2048), Options: []string{strings.Repeat("o", 4096)}}}})
	}
	if r.bytes() > 128<<10 || len(r.Items) >= 50 {
		t.Fatal("question context escaped the byte budget")
	}
}

// fakeBackend speaks Relay through the stable adapter interface, without inference.
type fakeBackend struct {
	mu        sync.Mutex
	events    chan protocol.Event
	done      chan struct{}
	once      sync.Once
	snapshots int
	title     string
	epoch     string
	requests  []protocol.PendingRequest
}

func (f *fakeBackend) Snapshot(context.Context) ([]protocol.Session, []protocol.PendingRequest, error) {
	f.mu.Lock()
	f.snapshots++
	f.mu.Unlock()
	return []protocol.Session{{ID: "m~t", MachineID: "m", ThreadID: "t", Title: f.title, Status: protocol.Ready}}, append([]protocol.PendingRequest(nil), f.requests...), nil
}
func (f *fakeBackend) Execute(_ context.Context, c protocol.Command) protocol.Result {
	return protocol.Result{ID: c.ID, OK: true}
}
func (f *fakeBackend) Events() <-chan protocol.Event { return f.events }
func (f *fakeBackend) Done() <-chan struct{}         { return f.done }
func (f *fakeBackend) Cursor() (string, uint64) {
	if f.epoch != "" {
		return f.epoch, 0
	}
	return "fake-epoch", 0
}
func (f *fakeBackend) Close() { f.once.Do(func() { close(f.done) }) }
func TestAgentReconnectAndHubRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "db")
	h, s, srv := testHub(t, path)
	_ = s.Token("m", testToken)
	tokenFile := filepath.Join(t.TempDir(), "token")
	if e := writeTestSecret(tokenFile, testToken); e != nil {
		t.Fatal(e)
	}
	f := &fakeBackend{events: make(chan protocol.Event, 16), done: make(chan struct{})}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	agentDone := make(chan error, 1)
	go func() {
		agentDone <- agent.Run(ctx, agent.Config{HubURL: srv.URL, TokenFile: tokenFile, MachineID: "m", Name: "M", Insecure: true, RetryMin: 10 * time.Millisecond, Open: func(context.Context, codex.Config) (codex.Backend, error) { return f, nil }})
	}()
	waitOnline := func(h *Hub) {
		t.Helper()
		end := time.Now().Add(5 * time.Second)
		for time.Now().Before(end) {
			h.mu.Lock()
			online := h.machines["m"].Status == protocol.Online
			h.mu.Unlock()
			if online {
				return
			}
			time.Sleep(10 * time.Millisecond)
		}
		t.Fatal("agent did not register")
	}
	waitOnline(h)
	addr := srv.Listener.Addr().String()
	h.Close()
	srv.Close()
	s.Close()
	// Same metadata DB, same address, a fresh Hub process state.
	s2, e := store.Open(path)
	if e != nil {
		t.Fatal(e)
	}
	defer s2.Close()
	h2, e := New(s2, Config{PublicURL: "http://relay.test", AdminToken: testToken})
	if e != nil {
		t.Fatal(e)
	}
	srv2 := httptest.NewUnstartedServer(h2.Handler())
	l, e := listenTest(addr)
	if e != nil {
		t.Fatal(e)
	}
	srv2.Listener = l
	srv2.Start()
	defer srv2.Close()
	defer h2.Close()
	waitOnline(h2)
	f.mu.Lock()
	n := f.snapshots
	f.mu.Unlock()
	if n < 2 {
		t.Fatal("no rehydration after Hub restart")
	}
	cancel()
	h2.Close()
	select {
	case <-agentDone:
	case <-time.After(5 * time.Second):
		t.Fatal("agent shutdown blocked")
	}
}

func TestRecoveryExpiresBuffersAndRevokesConnections(t *testing.T) {
	h, s, srv := testHub(t, filepath.Join(t.TempDir(), "db"))
	defer s.Close()
	defer srv.Close()
	defer h.Close()
	_ = s.Token("m", testToken)
	a := testWS(t, srv, http.Header{"X-Relay-Machine": []string{"m"}, "Authorization": []string{"Bearer " + testToken}}, "/api/agent")
	defer a.Close()
	_ = a.WriteJSON(protocol.Message{Version: 1, Type: "announce", Machine: &protocol.Machine{ID: "m"}, Epoch: "epoch"})
	end := time.Now().Add(time.Second)
	for time.Now().Before(end) {
		h.mu.Lock()
		ready := h.agents["m"] != nil && h.agents["m"].epoch != ""
		h.mu.Unlock()
		if ready {
			break
		}
		time.Sleep(time.Millisecond)
	}
	h.mu.Lock()
	h.buffers["expired"] = &Recent{Touched: time.Now().Add(-6 * time.Minute), Items: []protocol.Activity{{Text: "temporary"}}}
	h.mu.Unlock()
	_ = s.Revoke("m")
	h.maintain(time.Now())
	_ = a.SetReadDeadline(time.Now().Add(time.Second))
	var m protocol.Message
	if a.ReadJSON(&m) == nil {
		t.Fatal("revoked connection not closed")
	}
	h.mu.Lock()
	if h.buffers["expired"] != nil {
		t.Error("ephemeral context survived TTL")
	}
	h.mu.Unlock()
}

// A new Codex connection must replace stale requests and reload source state.
func TestAgentReconnectAfterCodexRestart(t *testing.T) {
	h, s, srv := testHub(t, filepath.Join(t.TempDir(), "db"))
	defer s.Close()
	defer srv.Close()
	defer h.Close()
	if err := s.Token("m", testToken); err != nil {
		t.Fatal(err)
	}
	tokenFile := filepath.Join(t.TempDir(), "token")
	if err := writeTestSecret(tokenFile, testToken); err != nil {
		t.Fatal(err)
	}
	first := &fakeBackend{events: make(chan protocol.Event, 16), done: make(chan struct{}), title: "before restart", epoch: "first", requests: []protocol.PendingRequest{{ID: "old-request", MachineID: "m", SessionID: "m~t", ThreadID: "t", Kind: "command", Status: "pending", CreatedAt: time.Now(), ExpiresAt: time.Now().Add(time.Hour)}}}
	second := &fakeBackend{events: make(chan protocol.Event, 16), done: make(chan struct{}), title: "after restart", epoch: "second"}
	opens := 0
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() {
		done <- agent.Run(ctx, agent.Config{HubURL: srv.URL, TokenFile: tokenFile, MachineID: "m", Insecure: true, RetryMin: 10 * time.Millisecond, Open: func(context.Context, codex.Config) (codex.Backend, error) {
			opens++
			if opens == 1 {
				return first, nil
			}
			return second, nil
		}})
	}()
	await := func(title string, requestCount int) {
		t.Helper()
		deadline := time.Now().Add(5 * time.Second)
		for time.Now().Before(deadline) {
			h.mu.Lock()
			ok := h.machines["m"].Status == protocol.Online && h.sessions["m~t"].Title == title && len(h.requests) == requestCount
			h.mu.Unlock()
			if ok {
				return
			}
			time.Sleep(10 * time.Millisecond)
		}
		t.Fatalf("snapshot not recovered: %s", title)
	}
	await("before restart", 1)
	first.Close()
	await("after restart", 0)
	cancel()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("agent shutdown blocked")
	}
	if opens < 2 {
		t.Fatal("Codex connection was not reopened")
	}
}

func TestLoginToleratesClipboardWhitespace(t *testing.T) {
	h, s, srv := testHub(t, filepath.Join(t.TempDir(), "db"))
	defer s.Close()
	defer srv.Close()
	defer h.Close()
	for _, tc := range []struct {
		token  string
		status int
	}{{" \n" + testToken + "\t", http.StatusOK}, {testToken + "x", http.StatusUnauthorized}} {
		body, _ := json.Marshal(map[string]string{"token": tc.token})
		req, _ := http.NewRequest("POST", srv.URL+"/api/login", strings.NewReader(string(body)))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Origin", "http://relay.test")
		req.Header.Set("X-Relay-CSRF", "1")
		response, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		response.Body.Close()
		if response.StatusCode != tc.status {
			t.Fatalf("status %d; want %d", response.StatusCode, tc.status)
		}
	}
}

func TestFailureReasonCannotPersistUpstreamMessage(t *testing.T) {
	if got := safeFailureReason(protocol.Failed, "Selected model is at capacity. Please try a different model."); got != "execution" {
		t.Fatalf("upstream text became durable metadata: %q", got)
	}
	if got := safeFailureReason(protocol.Failed, "capacity"); got != "capacity" {
		t.Fatalf("known category lost: %q", got)
	}
	if got := safeFailureReason(protocol.Ready, "capacity"); got != "" {
		t.Fatalf("resolved turn kept a failure reason: %q", got)
	}
}
