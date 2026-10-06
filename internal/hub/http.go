package hub

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"github.com/gorilla/websocket"
	"github.com/mothx9/codex-relay/internal/protocol"
	"github.com/mothx9/codex-relay/internal/push"
	"github.com/mothx9/codex-relay/internal/store"
	"github.com/mothx9/codex-relay/web"
	"io"
	"log/slog"
	"net/http"
	"regexp"
	"strings"
	"time"
)

const cookieName = "relay_operator"

var machinePattern = regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}$`)

func (h *Hub) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) { jsonResponse(w, map[string]string{"status": "ok"}) })
	mux.HandleFunc("POST /api/login", h.login)
	mux.HandleFunc("POST /api/logout", h.logout)
	mux.HandleFunc("POST /api/pairing/code", h.createPairing)
	mux.HandleFunc("POST /api/pairing/exchange", h.exchangePairing)
	mux.HandleFunc("GET /api/devices", h.devices)
	mux.HandleFunc("POST /api/devices/{id}/revoke", h.revokeDevice)
	mux.HandleFunc("POST /api/devices/{id}/remove", h.removeDevice)
	mux.HandleFunc("POST /api/machines/{id}/{action}", h.manageMachine)
	mux.HandleFunc("GET /api/bootstrap", h.bootstrap)
	mux.HandleFunc("GET /api/diagnostics", h.diagnostics)
	mux.HandleFunc("GET /api/ui", h.ui)
	mux.HandleFunc("GET /api/agent", h.agent)
	mux.HandleFunc("GET /api/agent/status", func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get("X-Relay-Machine")
		token := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !h.store.Authenticate(id, token) {
			http.Error(w, "Agent authentication rejected", 401)
			return
		}
		h.mu.Lock()
		m := h.machines[id]
		connected := h.agents[id] != nil
		h.mu.Unlock()
		jsonResponse(w, map[string]any{"connected": connected, "machine": m})
	})
	mux.HandleFunc("POST /api/push/subscribe", h.subscribePush)
	mux.HandleFunc("POST /api/push/unsubscribe", h.unsubscribePush)
	mux.HandleFunc("POST /api/push/test", h.testPush)
	mux.HandleFunc("POST /api/native-push/subscribe", h.subscribeAPNS)
	mux.HandleFunc("POST /api/native-push/unsubscribe", h.unsubscribeAPNS)
	mux.Handle("/", web.Handler())
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; worker-src 'self'; manifest-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")
		if h.secure {
			w.Header().Set("Strict-Transport-Security", "max-age=31536000")
		}
		mux.ServeHTTP(w, r)
	})
}
func jsonResponse(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(v)
}
func readJSON(w http.ResponseWriter, r *http.Request, v any) error {
	if !strings.HasPrefix(r.Header.Get("Content-Type"), "application/json") {
		return errors.New("JSON required")
	}
	r.Body = http.MaxBytesReader(w, r.Body, protocol.MaxMessage)
	d := json.NewDecoder(r.Body)
	d.DisallowUnknownFields()
	if e := d.Decode(v); e != nil {
		return e
	}
	var extra any
	if d.Decode(&extra) != io.EOF {
		return errors.New("trailing JSON")
	}
	return nil
}
func (h *Hub) mutation(w http.ResponseWriter, r *http.Request) bool {
	if r.Header.Get("Origin") != h.origin || r.Header.Get("X-Relay-CSRF") != "1" {
		http.Error(w, "Origin/CSRF rejected", http.StatusForbidden)
		return false
	}
	return true
}
func (h *Hub) auth(w http.ResponseWriter, r *http.Request) (string, time.Time, bool) {
	if authorization := r.Header.Get("Authorization"); authorization != "" {
		if !strings.HasPrefix(authorization, "Bearer ") {
			http.Error(w, "Device authentication rejected", 401)
			return "", time.Time{}, false
		}
		token := strings.TrimPrefix(authorization, "Bearer ")
		_, expires, ok := h.store.DeviceLogin(token)
		if !ok {
			http.Error(w, "Device access expired or revoked", 401)
		}
		return token, expires, ok
	}
	c, e := r.Cookie(cookieName)
	if e != nil {
		http.Error(w, "Login required", 401)
		return "", time.Time{}, false
	}
	_, expires, ok := h.store.OperatorLogin(c.Value)
	if !ok {
		http.Error(w, "Login expired", 401)
	}
	return c.Value, expires, ok
}
func (h *Hub) login(w http.ResponseWriter, r *http.Request) {
	if !h.mutation(w, r) {
		return
	}
	h.loginMu.Lock()
	if time.Since(h.loginWindow) > time.Minute {
		h.loginWindow = time.Now()
		h.loginAttempts = 0
	}
	h.loginAttempts++
	limited := h.loginAttempts > 20
	h.loginMu.Unlock()
	if limited {
		http.Error(w, "Try again later", 429)
		return
	}
	var input struct {
		Token string `json:"token"`
	}
	if readJSON(w, r, &input) != nil {
		http.Error(w, "Invalid login", 400)
		return
	}
	want, got := store.Hash(h.config.AdminToken), store.Hash(strings.TrimSpace(input.Token))
	if subtle.ConstantTimeCompare([]byte(want), []byte(got)) != 1 {
		http.Error(w, "Invalid token", 401)
		return
	}
	token := protocol.ID() + protocol.ID()
	expires := time.Now().Add(12 * time.Hour)
	if h.store.NewLogin(token, expires) != nil {
		http.Error(w, "Login unavailable", 503)
		return
	}
	http.SetCookie(w, &http.Cookie{Name: cookieName, Value: token, Path: "/", Expires: expires, MaxAge: 43200, Secure: h.secure, HttpOnly: true, SameSite: http.SameSiteStrictMode})
	jsonResponse(w, map[string]bool{"ok": true})
}
func (h *Hub) logout(w http.ResponseWriter, r *http.Request) {
	if !h.mutation(w, r) {
		return
	}
	token, _, ok := h.auth(w, r)
	if !ok {
		return
	}
	_ = h.store.Logout(token)
	_ = h.store.RevokeDeviceToken(token)
	h.mu.Lock()
	for o := range h.operators {
		if o.token == token {
			o.peer.Close()
		}
	}
	h.mu.Unlock()
	http.SetCookie(w, &http.Cookie{Name: cookieName, Value: "", Path: "/", MaxAge: -1, Secure: h.secure, HttpOnly: true, SameSite: http.SameSiteStrictMode})
	jsonResponse(w, map[string]bool{"ok": true})
}
func (h *Hub) bootstrap(w http.ResponseWriter, r *http.Request) {
	if _, _, ok := h.auth(w, r); !ok {
		return
	}
	jsonResponse(w, map[string]any{"version": protocol.Version, "push_public_key": h.push.PublicKey(), "secure": h.secure, "native_push": h.push.APNS != nil})
}
func (h *Hub) agent(w http.ResponseWriter, r *http.Request) {
	id := r.Header.Get("X-Relay-Machine")
	header := r.Header.Get("Authorization")
	if !machinePattern.MatchString(id) || !strings.HasPrefix(header, "Bearer ") || r.Header.Get("Origin") != "" {
		http.Error(w, "Agent authentication rejected", 401)
		return
	}
	token := strings.TrimPrefix(header, "Bearer ")
	if !h.store.Authenticate(id, token) {
		http.Error(w, "Agent authentication rejected", 401)
		return
	}
	conn, e := (&websocket.Upgrader{CheckOrigin: func(*http.Request) bool { return true }}).Upgrade(w, r, nil)
	if e != nil {
		return
	}
	p := protocol.NewPeer(conn)
	defer p.Close()
	go p.WriteLoop(r.Context())
	a := &agentPeer{peer: p, lastSeen: time.Now(), token: token}
	h.mu.Lock()
	if h.closing {
		h.mu.Unlock()
		return
	}
	h.wg.Add(1)
	defer h.wg.Done()
	if old := h.agents[id]; old != nil {
		old.peer.Close()
	}
	h.agents[id] = a
	h.syncing(id, a)
	h.mu.Unlock()
	defer h.offline(id, a)
	for {
		msg, e := p.Read()
		if e != nil {
			return
		}
		h.mu.Lock()
		if h.agents[id] != a {
			h.mu.Unlock()
			return
		}
		switch msg.Type {
		case "announce":
			e = h.announce(id, a, msg)
		case "heartbeat":
			a.lastSeen = time.Now()
			m := h.machines[id]
			m.LastSeen = a.lastSeen
			m.Freshness.LastHeartbeat = a.lastSeen
			h.machines[id] = m
		case "event":
			if msg.Event == nil {
				e = errors.New("missing event")
			} else {
				e = h.event(id, a, *msg.Event)
			}
		case "result":
			if msg.Result == nil {
				e = errors.New("missing result")
			} else {
				h.result(id, *msg.Result)
			}
		default:
			e = errors.New("invalid agent message")
		}
		h.mu.Unlock()
		if e != nil {
			// Never log payloads, commands, credentials, or arbitrary storage errors.
			reason := "storage_or_internal"
			switch e.Error() {
			case "invalid announcement", "machine capacity reached", "fleet session capacity reached", "invalid session", "invalid request", "missing event", "missing result", "invalid agent message", "invalid session update", "invalid pending request":
				reason = e.Error()
			}
			slog.Warn("agent message rejected", "machine", id, "type", msg.Type, "reason", reason)
			return
		}
	}
}
func (h *Hub) ui(w http.ResponseWriter, r *http.Request) {
	token, expires, ok := h.auth(w, r)
	if !ok {
		return
	}
	if r.Header.Get("Origin") != h.origin {
		http.Error(w, "WebSocket origin rejected", 403)
		return
	}
	h.mu.Lock()
	full := len(h.operators) >= 32
	h.mu.Unlock()
	if full {
		http.Error(w, "Operator connection limit", 503)
		return
	}
	conn, e := (&websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return r.Header.Get("Origin") == h.origin }}).Upgrade(w, r, nil)
	if e != nil {
		return
	}
	p := protocol.NewPeer(conn)
	defer p.Close()
	go p.WriteLoop(r.Context())
	o := &operator{peer: p, token: token, expires: expires}
	_ = h.store.TouchDevice(token)
	h.mu.Lock()
	if h.closing {
		h.mu.Unlock()
		return
	}
	h.wg.Add(1)
	defer h.wg.Done()
	h.operators[o] = true
	snap := h.snapshot()
	p.Enqueue(protocol.Message{Type: "snapshot", Snapshot: &snap})
	h.mu.Unlock()
	defer func() {
		h.mu.Lock()
		defer h.mu.Unlock()
		delete(h.operators, o)
		if !h.watched(o.session) {
			delete(h.buffers, o.session)
		}
		for id, f := range h.flights {
			if f.operator == o {
				delete(h.flights, id)
			}
		}
	}()
	for {
		msg, e := p.Read()
		if e != nil {
			return
		}
		if _, _, valid := h.store.OperatorLogin(token); time.Now().After(expires) || !valid {
			return
		}
		h.mu.Lock()
		switch msg.Type {
		case "watch":
			old := o.session
			o.session = msg.SessionID
			if old != o.session && !h.watched(old) {
				delete(h.buffers, old)
			}
			if o.session != "" {
				if _, known := h.discoverySession(o.session); !known {
					o.session = ""
					break
				}
				if h.buffers[o.session] == nil && len(h.buffers) < 64 {
					h.buffers[o.session] = &Recent{Touched: time.Now()}
				}
				for _, req := range h.requests {
					if req.SessionID == o.session {
						v := req
						p.Enqueue(protocol.Message{Type: "pending", Event: &protocol.Event{SessionID: o.session, Kind: "request", Request: &v}})
					}
				}
				id := msg.HistoryRequestID
				if id == "" {
					id = protocol.ID()
				}
				h.route(o, protocol.Command{ID: id, Kind: "history", SessionID: o.session})
			}
		case "command":
			if msg.Command == nil {
				h.mu.Unlock()
				return
			}
			h.route(o, *msg.Command)
		default:
			h.mu.Unlock()
			return
		}
		h.mu.Unlock()
	}
}
func (h *Hub) route(o *operator, c protocol.Command) {
	c.Kind = protocol.CommandKind(c.Kind)
	fail := func(code string) {
		r := protocol.Failure(c, code)
		o.peer.Enqueue(protocol.Message{Type: "result", Result: &r})
	}
	if len(c.ID) < 16 || len(c.ID) > 128 || len(c.Text) > protocol.MaxText || len(c.Content) > 64<<10 || len(c.CatalogueCursor) > 8192 || len(c.HistoryCursor) > 8192 || len(c.QueueID) > 256 || len(c.QueueClientID) > 128 || len(c.QueueRevision) > 64 {
		fail(protocol.CodexRejected)
		return
	}
	if _, exists := h.flights[c.ID]; exists {
		fail(protocol.UnknownOutcome)
		return
	}
	if len(h.flights) >= 128 {
		fail(protocol.CodexRejected)
		return
	}
	s, ok := h.sessions[c.SessionID]
	if c.Kind == "catalogue" {
		_, ok = h.machines[c.MachineID]
		s = protocol.Session{MachineID: c.MachineID}
		c.SessionID = ""
	} else if !ok && (c.Kind == "history" || c.Kind == "attach") {
		s, ok = h.discoverySession(c.SessionID)
	}
	if !ok {
		fail(protocol.SessionReadOnly)
		return
	}
	a := h.agents[s.MachineID]
	if a == nil || a.epoch == "" || h.machines[s.MachineID].Status != protocol.Online {
		fail(protocol.MachineOffline)
		return
	}
	if !h.store.Authenticate(s.MachineID, a.token) {
		a.peer.Close()
		fail(protocol.MachineOffline)
		return
	}
	c.ThreadID = s.ThreadID
	switch c.Kind {
	case "history", "attach", "catalogue":
	case protocol.QueueUpdate, protocol.NewTurn, protocol.Steer, protocol.FollowUpCommand, protocol.Interrupt:
		if code := protocol.CheckControl(s, c); code != "" {
			fail(code)
			return
		}
		if (c.Kind == protocol.NewTurn || c.Kind == protocol.Steer || c.Kind == protocol.FollowUpCommand || c.Kind == protocol.QueueUpdate) && strings.TrimSpace(c.Text) == "" {
			fail(protocol.CodexRejected)
			return
		}
	case protocol.Answer:
		r, ok := h.requests[c.RequestID]
		if !ok || r.SessionID != s.ID {
			fail(protocol.PendingRequestChanged)
			return
		}
		if _, busy := h.answering[r.ID]; busy {
			fail(protocol.PendingRequestChanged)
			return
		}
		h.answering[r.ID] = c.ID
	default:
		fail(protocol.CodexRejected)
		return
	}
	h.flights[c.ID] = flight{o, s.MachineID, s.ID, c.Kind, c.RequestID, time.Now()}
	a.peer.Enqueue(protocol.Message{Type: "command", Command: &c})
	_ = h.store.Audit(c.Kind, s.MachineID, s.ID, c.ID, "sent")
}
func (h *Hub) result(machine string, r protocol.Result) {
	f, ok := h.flights[r.ID]
	if !ok || f.machine != machine {
		return
	}
	delete(h.flights, r.ID)
	r.SessionID = f.session
	if f.kind == protocol.Answer && !r.OK {
		delete(h.answering, f.request)
	}
	// Only allowlisted canonical codes and safe messages reach the operator.
	if !r.OK {
		r = protocol.Failure(protocol.Command{ID: r.ID, SessionID: r.SessionID}, r.ErrorCode)
	}
	if f.kind == "catalogue" && r.OK {
		if !validCatalogue(machine, r) {
			r = protocol.Failure(protocol.Command{ID: r.ID}, protocol.CodexRejected)
		}
		for i := range r.Sessions {
			r.Sessions[i].ReadOnly = true
			r.Sessions[i].Fresh = false
			r.Sessions[i].Capabilities = protocol.Capabilities{}
		}
	} else {
		r.Sessions = nil
		r.CatalogueCursor = ""
		r.MachineID = ""
	}
	if f.kind == "history" {
		if b := h.buffers[f.session]; b != nil {
			for _, v := range r.History {
				b.Put(v)
			}
		}
	} else {
		r.History = nil
		r.HistoryCursor = ""
		r.FollowUps = nil
	}
	if f.operator.session == f.session || f.kind != "history" {
		f.operator.peer.Enqueue(protocol.Message{Type: "result", Result: &r})
	}
	outcome := "ok"
	if !r.OK {
		outcome = "failed"
	}
	_ = h.store.Audit(f.kind, machine, f.session, r.ID, outcome)
}
func (h *Hub) subscribePush(w http.ResponseWriter, r *http.Request) {
	if !h.mutation(w, r) {
		return
	}
	if _, _, ok := h.auth(w, r); !ok {
		return
	}
	var input struct {
		Subscription json.RawMessage `json:"subscription"`
		Privacy      bool            `json:"privacy"`
	}
	if readJSON(w, r, &input) != nil {
		http.Error(w, "Invalid subscription", 400)
		return
	}
	v, e := push.Validate(input.Subscription)
	if e != nil {
		http.Error(w, e.Error(), 400)
		return
	}
	if e = h.store.Subscribe(store.PushSubscription{Endpoint: v.Endpoint, JSON: input.Subscription, Privacy: input.Privacy}); e != nil {
		http.Error(w, "Cannot store subscription", 503)
		return
	}
	jsonResponse(w, map[string]bool{"ok": true})
}
func (h *Hub) unsubscribePush(w http.ResponseWriter, r *http.Request) {
	if !h.mutation(w, r) {
		return
	}
	if _, _, ok := h.auth(w, r); !ok {
		return
	}
	var input struct {
		Endpoint string `json:"endpoint"`
	}
	if readJSON(w, r, &input) != nil {
		http.Error(w, "Invalid endpoint", 400)
		return
	}
	_ = h.store.Unsubscribe(input.Endpoint)
	jsonResponse(w, map[string]bool{"ok": true})
}
func (h *Hub) testPush(w http.ResponseWriter, r *http.Request) {
	if !h.mutation(w, r) {
		return
	}
	if _, _, ok := h.auth(w, r); !ok {
		return
	}
	if h.push.PublicKey() == "" && h.push.APNS == nil {
		http.Error(w, "Push not configured", 503)
		return
	}
	var input struct {
		SessionID string `json:"session_id"`
	}
	if r.ContentLength != 0 && readJSON(w, r, &input) != nil {
		http.Error(w, "Invalid push test", 400)
		return
	}
	if input.SessionID != "" {
		h.mu.Lock()
		_, known := h.sessions[input.SessionID]
		h.mu.Unlock()
		if !known {
			http.Error(w, "Unknown session", 404)
			return
		}
	}
	h.push.Enqueue(push.Notice{Key: "test/" + protocol.ID(), Kind: "test", SessionID: input.SessionID})
	jsonResponse(w, map[string]bool{"queued": true})
}

// Unknown canonical identities may be read/attached, never controlled directly.
func (h *Hub) discoverySession(id string) (protocol.Session, bool) {
	if s, ok := h.sessions[id]; ok {
		return s, true
	}
	machine, thread, ok := strings.Cut(id, "~")
	_, known := h.machines[machine]
	if !ok || !known || thread == "" || len(thread) > 256 || strings.ContainsAny(thread, "~\r\n\x00") {
		return protocol.Session{}, false
	}
	return protocol.Session{ID: id, MachineID: machine, ThreadID: thread, ReadOnly: true}, true
}
func validCatalogue(machine string, r protocol.Result) bool {
	if r.MachineID != machine || len(r.Sessions) > 100 || len(r.CatalogueCursor) > 8192 {
		return false
	}
	seen := map[string]bool{}
	for _, s := range r.Sessions {
		if s.MachineID != machine || s.ThreadID == "" || len(s.ThreadID) > 256 || s.ID != protocol.SessionID(machine, s.ThreadID) || seen[s.ID] || len(s.Title) > 128 || len(s.Cwd) > 1024 {
			return false
		}
		seen[s.ID] = true
	}
	return true
}
