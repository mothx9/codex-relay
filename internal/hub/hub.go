// Package hub routes canonical Relay state. It never speaks Codex RPC.
package hub

import (
	"context"
	"errors"
	"github.com/mothx9/codex-relay/internal/protocol"
	"github.com/mothx9/codex-relay/internal/push"
	"github.com/mothx9/codex-relay/internal/store"
	"log/slog"
	"net/url"
	"sort"
	"sync"
	"time"
)

type Config struct {
	PublicURL, AdminToken string
	PushKeys              push.Keys
	PushSubject           string
	APNS                  *push.APNS
}
type agentPeer struct {
	peer     *protocol.Peer
	epoch    string
	sequence uint64
	lastSeen time.Time
	token    string
}
type operator struct {
	peer    *protocol.Peer
	session string
	token   string
	expires time.Time
}
type flight struct {
	operator                        *operator
	machine, session, kind, request string
	created                         time.Time
}
type Hub struct {
	mu             sync.Mutex
	wg             sync.WaitGroup
	closing        bool
	store          *store.Store
	config         Config
	origin         string
	secure         bool
	machines       map[string]protocol.Machine
	sessions       map[string]protocol.Session
	requests       map[string]protocol.PendingRequest
	agents         map[string]*agentPeer
	operators      map[*operator]bool
	flights        map[string]flight
	answering      map[string]string
	buffers        map[string]*Recent
	liveActivities map[string]protocol.LiveActivity
	push           *push.Worker
	loginMu        sync.Mutex
	loginWindow    time.Time
	loginAttempts  int
	pairMu         sync.Mutex
	pairings       map[string]pairing
	pairWindow     time.Time
	pairAttempts   int
}

func New(s *store.Store, c Config) (*Hub, error) {
	u, e := url.Parse(c.PublicURL)
	if e != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") || u.User != nil || u.RawQuery != "" || u.Fragment != "" || (u.Path != "" && u.Path != "/") {
		return nil, errors.New("public URL must be an HTTP(S) origin")
	}
	if len(c.AdminToken) < 32 {
		return nil, errors.New("admin bootstrap token too short")
	}
	h := &Hub{store: s, config: c, origin: u.Scheme + "://" + u.Host, secure: u.Scheme == "https", machines: map[string]protocol.Machine{}, sessions: map[string]protocol.Session{}, requests: map[string]protocol.PendingRequest{}, agents: map[string]*agentPeer{}, operators: map[*operator]bool{}, flights: map[string]flight{}, answering: map[string]string{}, buffers: map[string]*Recent{}}
	h.pairings = make(map[string]pairing)
	snap, e := s.Load()
	if e != nil {
		return nil, e
	}
	for _, m := range snap.Machines {
		h.machines[m.ID] = m
	}
	for _, v := range snap.Sessions {
		h.sessions[v.ID] = v
	}
	h.push = push.New(s, c.PushKeys, c.PushSubject)
	h.push.APNS = c.APNS
	return h, nil
}
func (h *Hub) Close() {
	h.mu.Lock()
	h.closing = true
	for _, a := range h.agents {
		a.peer.Close()
	}
	for o := range h.operators {
		o.peer.Close()
	}
	h.mu.Unlock()
	h.wg.Wait()
}
func (h *Hub) Run(ctx context.Context) {
	go h.push.Run(ctx)
	t := time.NewTicker(15 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			h.Close()
			return
		case now := <-t.C:
			h.maintain(now)
		}
	}
}
func (h *Hub) maintain(now time.Time) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for id, a := range h.agents {
		if now.Sub(a.lastSeen) > 75*time.Second || !h.store.Authenticate(id, a.token) {
			a.peer.Close()
		}
	}
	for o := range h.operators {
		if _, _, ok := h.store.OperatorLogin(o.token); now.After(o.expires) || !ok {
			o.peer.Close()
		}
	}
	for id, f := range h.flights {
		if now.Sub(f.created) > 30*time.Second {
			r := protocol.Failure(protocol.Command{ID: id, SessionID: f.session}, protocol.UnknownOutcome)
			f.operator.peer.Enqueue(protocol.Message{Type: "result", Result: &r})
			delete(h.flights, id) /* Keep approval reservation until resolution/reconnect: never reuse. */
		}
	}
	for id, b := range h.buffers {
		if now.Sub(b.Touched) > bufferTTL {
			delete(h.buffers, id)
		}
	}
	for _, m := range h.machines {
		if m.Status == protocol.Offline && now.Sub(m.LastSeen) > time.Minute && now.Sub(m.LastSeen) < 90*time.Second {
			h.push.Enqueue(push.Notice{Kind: "machine_offline", Key: "offline/" + m.ID + "/" + m.LastSeen.Format(time.RFC3339Nano), Machine: m.Name})
		}
	}
	for id, r := range h.requests {
		if now.After(r.ExpiresAt) {
			delete(h.requests, id)
			_ = h.store.ResolvePending(id)
			h.broadcast(protocol.Message{Type: "event", Event: &protocol.Event{Kind: "request_resolved", SessionID: r.SessionID, RequestID: id}}, "")
		}
	}
	if e := h.store.Prune(); e != nil {
		slog.Error("metadata maintenance failed")
	}
}
func (h *Hub) snapshot() protocol.Snapshot {
	snap := protocol.Snapshot{LiveActivities: map[string]protocol.LiveActivity{}, Machines: []protocol.Machine{}, Sessions: []protocol.Session{}, Requests: []protocol.PendingRequest{}}
	for id, activity := range h.liveActivities {
		snap.LiveActivities[id] = activity
	}
	for _, m := range h.machines {
		snap.Machines = append(snap.Machines, m)
	}
	for _, s := range h.sessions {
		if h.machines[s.MachineID].Status != protocol.Online {
			s.Capabilities = protocol.Capabilities{}
		}
		snap.Sessions = append(snap.Sessions, s)
	}
	for _, r := range h.requests {
		r.Payload = nil
		snap.Requests = append(snap.Requests, r)
	}
	sort.Slice(snap.Sessions, func(i, j int) bool { return snap.Sessions[i].UpdatedAt.After(snap.Sessions[j].UpdatedAt) })
	return snap
}
func (h *Hub) broadcast(m protocol.Message, session string) {
	for o := range h.operators {
		if session == "" || o.session == session {
			o.peer.Enqueue(m)
		}
	}
}
func samePending(a, b protocol.PendingRequest) bool {
	return a.ID == b.ID && a.MachineID == b.MachineID && a.SessionID == b.SessionID && a.Kind == b.Kind && a.TurnID == b.TurnID && a.CreatedAt.Equal(b.CreatedAt)
}

func (h *Hub) announce(id string, a *agentPeer, msg protocol.Message) error {
	if msg.Version != protocol.Version || msg.Machine == nil || msg.Machine.ID != id || len(msg.Sessions) > protocol.MaxSessions || len(msg.Requests) > 128 || msg.Epoch == "" {
		return errors.New("invalid announcement")
	}
	if len(h.machines) >= 16 {
		if _, known := h.machines[id]; !known {
			return errors.New("machine capacity reached")
		}
	}
	count := len(msg.Sessions)
	for _, s := range h.sessions {
		if s.MachineID != id {
			count++
		}
	}
	if count > 1024 {
		return errors.New("fleet session capacity reached")
	}
	for _, s := range msg.Sessions {
		if s.MachineID != id || s.ID != protocol.SessionID(id, s.ThreadID) || len(s.Cwd) > 1024 || len(s.Title) > 128 {
			return errors.New("invalid session")
		}
	}
	for _, r := range msg.Requests {
		if r.MachineID != id || r.SessionID != protocol.SessionID(id, r.ThreadID) || len(r.Payload) > 64<<10 {
			return errors.New("invalid request")
		}
	}
	if a.epoch == msg.Epoch && msg.Sequence < a.sequence {
		return nil
	}
	m := *msg.Machine
	m.ID = id
	m.LastSeen = time.Now().UTC()
	m.Name = protocol.Clip(m.Name, 64)
	if m.Account != nil {
		m.Account.Kind = protocol.Clip(m.Account.Kind, 32)
		m.Account.Email = protocol.Clip(m.Account.Email, 254)
		m.Account.Plan = protocol.Clip(m.Account.Plan, 64)
	}
	if m.Status != protocol.Degraded {
		m.Status = protocol.Online
	}
	if e := h.store.SaveMachine(m); e != nil {
		return e
	}
	if e := h.store.ReplaceSessions(id, msg.Sessions); e != nil {
		return e
	}
	if e := h.store.ClearPending(id); e != nil {
		return e
	}
	for sid, s := range h.sessions {
		if s.MachineID == id {
			delete(h.sessions, sid)
			if a.epoch != msg.Epoch {
				delete(h.liveActivities, sid)
			}
		}
	}
	incoming := make(map[string]protocol.PendingRequest, len(msg.Requests))
	for _, r := range msg.Requests {
		incoming[r.ID] = r
	}
	for rid, r := range h.requests {
		if r.MachineID == id {
			next, exists := incoming[rid]
			// Periodic announcements must not release an in-flight approval.
			if !exists || a.epoch != msg.Epoch || !samePending(r, next) {
				delete(h.answering, rid)
			}
			delete(h.requests, rid)
		}
	}
	h.machines[id] = m
	for _, s := range msg.Sessions {
		h.sessions[s.ID] = s
	}
	for sid := range h.liveActivities {
		if s, exists := h.sessions[sid]; !exists || (s.Status != protocol.Working && s.Status != protocol.NeedsYou) {
			delete(h.liveActivities, sid)
		}
	}
	for _, r := range msg.Requests {
		h.requests[r.ID] = r
		if e := h.store.SavePending(r); e != nil {
			return e
		}
		h.notifyRequest(r)
	}
	a.epoch = msg.Epoch
	a.sequence = msg.Sequence
	a.lastSeen = m.LastSeen
	snap := h.snapshot()
	h.broadcast(protocol.Message{Type: "snapshot", Snapshot: &snap}, "")
	return nil
}
func (h *Hub) event(id string, a *agentPeer, e protocol.Event) error {
	if e.MachineID != id || e.Epoch != a.epoch || e.ID == "" || e.SessionID == "" {
		return errors.New("invalid event identity")
	}
	if e.Sequence <= a.sequence {
		return nil
	}
	a.sequence = e.Sequence
	a.lastSeen = time.Now()
	s, ok := h.sessions[e.SessionID]
	if !ok {
		if e.Session == nil {
			return nil
		}
		if len(h.sessions) >= 1024 {
			return errors.New("session capacity reached")
		}
		s = *e.Session
	}
	if s.MachineID != id {
		return errors.New("cross-machine event")
	}
	if e.Session != nil {
		if e.Session.ID != e.SessionID || e.Session.MachineID != id || e.Session.ThreadID != s.ThreadID {
			return errors.New("invalid session update")
		}
		s = *e.Session
		h.sessions[s.ID] = s
		if err := h.store.SaveSession(s); err != nil {
			return err
		}
	}
	if e.Request != nil {
		r := *e.Request
		if r.MachineID != id || r.SessionID != s.ID || r.ThreadID != s.ThreadID || len(r.Payload) > 64<<10 || len(h.requests) >= 128 {
			return errors.New("invalid pending request")
		}
		h.requests[r.ID] = r
		if err := h.store.SavePending(r); err != nil {
			return err
		}
		h.notifyRequest(r)
	}
	if e.Kind == "request_resolved" {
		delete(h.requests, e.RequestID)
		delete(h.answering, e.RequestID)
		if err := h.store.ResolvePending(e.RequestID); err != nil {
			return err
		}
	}
	h.updateLiveActivity(e)
	if b := h.buffers[e.SessionID]; b != nil {
		b.Apply(e)
	}
	if e.Kind == "delta" || e.Kind == "activity" || e.Kind == "command_output" || e.Kind == "diff" || e.Kind == "follow_up_queue" {
		h.broadcast(protocol.Message{Type: "event", Event: &e}, e.SessionID)
	} else {
		// Full approval context is ephemeral and only delivered to operators viewing this session.
		full := e
		if e.Request != nil {
			r := *e.Request
			r.Payload = nil
			e.Request = &r
		}
		h.broadcast(protocol.Message{Type: "event", Event: &e}, "")
		if full.Request != nil {
			h.broadcast(protocol.Message{Type: "pending", Event: &full}, e.SessionID)
		}
	}
	if e.Kind == "turn_completed" || e.Kind == "failed" {
		h.push.Enqueue(push.Notice{Key: e.NotifyKey, Kind: e.Kind, SessionID: s.ID, Machine: h.machines[id].Name, Project: s.Project, Title: s.Title})
		if !h.watched(s.ID) {
			delete(h.buffers, s.ID)
		}
	}
	return nil
}
func (h *Hub) notifyRequest(r protocol.PendingRequest) {
	s := h.sessions[r.SessionID]
	key := r.SessionID + "/request/" + r.TurnID + "/" + r.Kind
	if r.NotifyKey != "" {
		key = r.NotifyKey
	} else {
		key += "/" + r.ID
	}
	h.push.Enqueue(push.Notice{Key: key, Kind: "request", SessionID: s.ID, Machine: h.machines[r.MachineID].Name, Project: s.Project, Title: s.Title})
}
func (h *Hub) watched(session string) bool {
	for o := range h.operators {
		if o.session == session {
			return true
		}
	}
	return false
}
func (h *Hub) offline(id string, a *agentPeer) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.agents[id] != a {
		return
	}
	delete(h.agents, id)
	m := h.machines[id]
	m.Status = protocol.Offline
	h.machines[id] = m
	_ = h.store.SaveMachine(m)
	for rid, r := range h.requests {
		if r.MachineID == id {
			delete(h.answering, rid)
		}
	}
	_ = h.store.ClearPending(id)
	for cid, f := range h.flights {
		if f.machine == id {
			r := protocol.Failure(protocol.Command{ID: cid, SessionID: f.session}, protocol.UnknownOutcome)
			f.operator.peer.Enqueue(protocol.Message{Type: "result", Result: &r})
			delete(h.flights, cid)
		}
	}
	snap := h.snapshot()
	h.broadcast(protocol.Message{Type: "snapshot", Snapshot: &snap}, "")
}
