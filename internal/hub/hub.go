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
	Version               string
	PushKeys              push.Keys
	PushSubject           string
	APNS                  *push.APNS
}
type agentPeer struct {
	peer             *protocol.Peer
	epoch            string
	sequence         uint64
	snapshotRevision uint64
	seen             map[string]bool
	seenOrder        []string
	lastSeen         time.Time
	token            string
	connectedAt      time.Time
	connectionID     string
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
	mu                  sync.Mutex
	wg                  sync.WaitGroup
	closing             bool
	store               *store.Store
	config              Config
	origin              string
	secure              bool
	machines            map[string]protocol.Machine
	sessions            map[string]protocol.Session
	requests            map[string]protocol.PendingRequest
	agents              map[string]*agentPeer
	operators           map[*operator]bool
	flights             map[string]flight
	answering           map[string]string
	buffers             map[string]*Recent
	liveActivities      map[string]protocol.LiveActivity
	liveQuestionNotices map[string]liveQuestionNotice
	push                *push.Worker
	loginMu             sync.Mutex
	loginWindow         time.Time
	loginAttempts       int
	pairMu              sync.Mutex
	pairings            map[string]pairing
	pairWindow          time.Time
	pairAttempts        int
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
	for _, r := range snap.Requests {
		h.requests[r.ID] = r
		h.ensurePendingSession(r, "", time.Time{})
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
			h.push.Enqueue(push.Notice{Kind: "machine_offline", Key: "offline/" + m.ID + "/" + m.LastSeen.Format(time.RFC3339Nano), Machine: m.Name, MachineID: m.ID})
		}
	}
	// Only Codex resolution or a complete new-epoch reconciliation retires a request.
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
		snap.Sessions = append(snap.Sessions, h.visibleSession(s))
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
	if current := h.agents[id]; current != nil && current != a {
		return errors.New("stale connection")
	}
	if a.epoch != "" && a.epoch != msg.Epoch {
		return errors.New("epoch changed within connection")
	}
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
		if prior, exists := h.requests[r.ID]; exists && prior.MachineID != id {
			return errors.New("cross-machine request identity")
		}
		if r.ID == "" || r.MachineID != id || r.SessionID != protocol.SessionID(id, r.ThreadID) || len(r.Payload) > 64<<10 {
			return errors.New("invalid request")
		}
	}
	if a.epoch == msg.Epoch && (msg.Sequence < a.sequence || (msg.SnapshotRevision != 0 && msg.SnapshotRevision <= a.snapshotRevision)) {
		return nil
	}
	// A reachable Agent with unavailable Codex must retain last-known state.
	if msg.Machine.Status == protocol.Degraded {
		m := h.machines[id]
		m.ID, m.Name, m.Status = id, protocol.Clip(msg.Machine.Name, 64), protocol.Degraded
		m.AgentVersion, m.CodexVersion, m.Adapter = msg.Machine.AgentVersion, msg.Machine.CodexVersion, msg.Machine.Adapter
		m.LastSeen = time.Now().UTC()
		h.machines[id] = m
		a.epoch, a.lastSeen = msg.Epoch, m.LastSeen
		snap := h.snapshot()
		h.broadcast(protocol.Message{Type: "snapshot", Snapshot: &snap}, "")
		return h.store.SaveMachine(m)
	}
	m := *msg.Machine
	if m.Account == nil {
		m.Account = h.machines[id].Account
	}
	m.Freshness = h.machines[id].Freshness
	m.Freshness.ConnectionID = a.connectionID
	m.Freshness.Epoch, m.Freshness.ProtocolVersion = msg.Epoch, msg.Version
	m.Freshness.LastSnapshot = time.Now().UTC()
	m.Freshness.Sequence, m.Freshness.SnapshotSequence = msg.Sequence, msg.Sequence
	m.Freshness.SnapshotMS = msg.Machine.Freshness.SnapshotMS
	if !a.connectedAt.IsZero() && h.machines[id].Status != protocol.Online {
		m.Freshness.SyncMS = float64(time.Since(a.connectedAt).Microseconds()) / 1000
	}
	m.ID = id
	m.LastSeen = time.Now().UTC()
	m.Name = protocol.Clip(m.Name, 64)
	if m.Account != nil {
		account := *m.Account
		previous := h.machines[id].Account
		if msg.Machine.Account != nil && (previous == nil || previous.ObservedAt != account.ObservedAt) {
			account.HubObservedAt = time.Now().UTC()
		} else if previous != nil {
			account.HubObservedAt = previous.HubObservedAt
		}
		m.Account = &account
		m.Account.Kind = protocol.Clip(m.Account.Kind, 32)
		m.Account.Email = protocol.Clip(m.Account.Email, 254)
		m.Account.Plan = protocol.Clip(m.Account.Plan, 64)
	}
	if m.Status != protocol.Degraded {
		m.Status = protocol.Online
	}
	incoming := make(map[string]protocol.PendingRequest, len(msg.Requests))
	for _, r := range msg.Requests {
		incoming[r.ID] = r
	}
	if a.epoch == msg.Epoch {
		for rid, r := range h.requests {
			if r.MachineID == id {
				if _, exists := incoming[rid]; !exists {
					incoming[rid] = r
				}
			}
		}
	}
	knownSessions := map[string]bool{}
	for i := range msg.Sessions {
		msg.Sessions[i].ObservedAt = m.LastSeen
		msg.Sessions[i].AgentEpoch = msg.Epoch
		knownSessions[msg.Sessions[i].ID] = true
	}
	pending := make([]protocol.PendingRequest, 0, len(incoming))
	for _, r := range incoming {
		pending = append(pending, r)
		if !knownSessions[r.SessionID] {
			s, ok := h.sessions[r.SessionID]
			if !ok {
				s = protocol.Session{ID: r.SessionID, MachineID: id, ThreadID: r.ThreadID, Title: "Thread " + protocol.Clip(r.ThreadID, 8), Cwd: r.Cwd, Status: protocol.NeedsYou, ReadOnly: true}
			}
			s.AgentEpoch, s.ObservedAt = msg.Epoch, m.LastSeen
			msg.Sessions = append(msg.Sessions, s)
			knownSessions[s.ID] = true
		}
	}
	if err := h.store.ReplaceMachineState(m, msg.Sessions, pending); err != nil {
		return err
	}
	for sid, s := range h.sessions {
		if s.MachineID == id {
			delete(h.sessions, sid)
			if a.epoch != msg.Epoch {
				delete(h.liveActivities, sid)
			}
		}
	}
	for rid, r := range h.requests {
		if r.MachineID == id {
			next, exists := incoming[rid]
			if !exists && a.epoch == msg.Epoch {
				incoming[rid] = r
				continue
			}
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
	for _, r := range incoming {
		h.requests[r.ID] = r
		h.notifyRequest(r)
	}
	a.snapshotRevision = msg.SnapshotRevision
	a.epoch = msg.Epoch
	a.sequence = msg.Sequence
	a.lastSeen = m.LastSeen
	snap := h.snapshot()
	h.broadcast(protocol.Message{Type: "snapshot", Snapshot: &snap}, "")
	return nil
}
func (h *Hub) event(id string, a *agentPeer, e protocol.Event) error {
	if current := h.agents[id]; current != nil && current != a {
		return errors.New("stale connection")
	}
	if e.MachineID != id || e.Epoch != a.epoch || e.ID == "" || (e.SessionID == "" && e.Kind != "account") {
		return errors.New("invalid event identity")
	}
	if e.Request != nil {
		r := e.Request
		if r.ID == "" || r.MachineID != id || r.SessionID != e.SessionID || r.SessionID != protocol.SessionID(id, r.ThreadID) || len(r.Payload) > 64<<10 {
			return errors.New("invalid pending request identity")
		}
		if prior, exists := h.requests[r.ID]; exists && (prior.MachineID != id || prior.SessionID != r.SessionID) {
			return errors.New("cross-session request identity")
		}
		if _, exists := h.requests[r.ID]; !exists && len(h.requests) >= 128 {
			return errors.New("pending capacity reached")
		}
	}
	if r, exists := h.requests[e.RequestID]; e.Kind == "request_resolved" && exists && (r.MachineID != id || r.SessionID != e.SessionID) {
		return errors.New("cross-session resolution")
	}
	if e.Sequence <= a.sequence || a.seen[e.ID] {
		return nil
	}
	if a.seen == nil {
		a.seen = map[string]bool{}
	}
	a.seen[e.ID] = true
	a.seenOrder = append(a.seenOrder, e.ID)
	if len(a.seenOrder) > 2048 {
		delete(a.seen, a.seenOrder[0])
		a.seenOrder = a.seenOrder[1:]
	}
	a.sequence = e.Sequence
	a.lastSeen = time.Now()
	m := h.machines[id]
	m.LastSeen = a.lastSeen
	m.Freshness.LastEvent, m.Freshness.Sequence = a.lastSeen, e.Sequence
	e.HubObservedAt = a.lastSeen.UTC()
	if !e.Timestamp.IsZero() {
		m.Freshness.AgentToHub.Observe(a.lastSeen.Sub(e.Timestamp))
	}
	h.machines[id] = m
	if e.Kind == "account" {
		if e.Account != nil {
			account := *e.Account
			account.HubObservedAt = time.Now().UTC()
			m.Account = &account
			h.machines[id] = m
		}
		snap := h.snapshot()
		h.broadcast(protocol.Message{Type: "snapshot", Snapshot: &snap}, "")
		return nil
	}
	if e.Request != nil && e.Request.MachineID == id && e.Request.SessionID == e.SessionID && e.Request.SessionID == protocol.SessionID(id, e.Request.ThreadID) {
		h.ensurePendingSession(*e.Request, a.epoch, a.lastSeen)
	}
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
		s.ObservedAt, s.AgentEpoch = a.lastSeen, a.epoch
		h.sessions[s.ID] = s
		if err := h.store.SaveSession(s); err != nil {
			return err
		}
	}
	if e.Request != nil {
		r := *e.Request
		if r.MachineID != id || r.SessionID != s.ID || r.ThreadID != s.ThreadID || len(r.Payload) > 64<<10 {
			return errors.New("invalid pending request")
		}
		h.requests[r.ID] = r
		h.ensurePendingSession(r, a.epoch, a.lastSeen)
		s = h.sessions[r.SessionID]
		e.Session = &s
		if err := h.store.SaveSession(s); err != nil {
			return err
		}
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
	if e.Session != nil {
		visible := h.visibleSession(*e.Session)
		e.Session = &visible
	}
	h.updateLiveActivity(e)
	h.attention(e)
	if b := h.buffers[e.SessionID]; b != nil {
		b.Apply(e)
	}
	if e.Kind == "delta" || e.Kind == "activity" || e.Kind == "command_output" || e.Kind == "diff" || e.Kind == "follow_up_queue" || e.Kind == "tool_progress" || e.Kind == "terminal_interaction" {
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
		h.push.Enqueue(push.Notice{Key: e.NotifyKey, Kind: e.Kind, TurnID: e.TurnID, SessionID: s.ID, MachineID: id, Machine: h.machines[id].Name, Project: s.Project, Title: s.Title})
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
	h.push.Enqueue(push.Notice{Key: key, Kind: "request", TurnID: r.TurnID, SessionID: s.ID, MachineID: r.MachineID, RequestID: r.ID, Machine: h.machines[r.MachineID].Name, Project: s.Project, Title: s.Title})
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
	m.Freshness.LastDisconnectReason = "transport_closed"
	h.machines[id] = m
	_ = h.store.SaveMachine(m)
	for rid, r := range h.requests {
		if r.MachineID == id {
			delete(h.answering, rid)
		}
	}
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

// Pending state has priority over catalogue pagination and session snapshots.
func (h *Hub) ensurePendingSession(r protocol.PendingRequest, epoch string, observed time.Time) {
	s, known := h.sessions[r.SessionID]
	if !known {
		s = protocol.Session{ID: r.SessionID, MachineID: r.MachineID, ThreadID: r.ThreadID, Title: "Thread " + protocol.Clip(r.ThreadID, 8), Cwd: r.Cwd, ReadOnly: true}
	}
	if !known {
		s.Status = protocol.NeedsYou
	}
	if !observed.IsZero() {
		s.AgentEpoch, s.ObservedAt = epoch, observed
	}
	h.sessions[s.ID] = s
}

// Transport acceptance immediately invalidates the previous live freshness.
func (h *Hub) syncing(id string, a *agentPeer) {
	now := time.Now().UTC()
	a.connectedAt, a.connectionID = now, protocol.ID()
	m := h.machines[id]
	m.ID = id
	if m.Name == "" {
		m.Name = id
	}
	if !m.Freshness.ConnectedAt.IsZero() {
		m.Freshness.ReconnectCount++
	}
	m.Status = protocol.Syncing
	m.Freshness.ConnectedAt, m.Freshness.ConnectionID = now, a.connectionID
	h.machines[id] = m
	snap := h.snapshot()
	h.broadcast(protocol.Message{Type: "snapshot", Snapshot: &snap}, "")
}

func (h *Hub) visibleSession(s protocol.Session) protocol.Session {
	s.Fresh = h.machines[s.MachineID].Status == protocol.Online
	for _, r := range h.requests {
		if r.SessionID == s.ID {
			s.Status = protocol.NeedsYou
		}
	}
	if !s.Fresh {
		s.Capabilities = protocol.Capabilities{}
	}
	return s
}
