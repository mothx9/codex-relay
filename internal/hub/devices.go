package hub

import (
	"crypto/rand"
	"fmt"
	"github.com/mothx9/codex-relay/internal/protocol"
	"github.com/mothx9/codex-relay/internal/store"
	"math/big"
	"net/http"
	"strings"
	"time"
)

type pairing struct {
	Kind, Machine, Name string
	Expires             time.Time
}

// Codes live only in Hub RAM, as hashes, for five minutes. A restart invalidates them.
func (h *Hub) createPairing(w http.ResponseWriter, r *http.Request) {
	if !h.mutation(w, r) {
		return
	}
	if _, _, ok := h.auth(w, r); !ok {
		return
	}
	var input struct {
		Kind    string `json:"kind"`
		Machine string `json:"machine"`
		Name    string `json:"name"`
	}
	if readJSON(w, r, &input) != nil || (input.Kind != "operator" && input.Kind != "agent") || len(strings.TrimSpace(input.Name)) == 0 || len(input.Name) > 64 || (input.Kind == "agent" && !machinePattern.MatchString(input.Machine)) {
		http.Error(w, "Invalid pairing", 400)
		return
	}
	if input.Kind == "agent" && h.store.MachineAccess(input.Machine) != "REVOKED" {
		http.Error(w, "Machine already enrolled; revoke it before re-enrollment", 409)
		return
	}
	h.pairMu.Lock()
	defer h.pairMu.Unlock()
	now := time.Now()
	for hash, p := range h.pairings {
		if now.After(p.Expires) {
			delete(h.pairings, hash)
		}
	}
	if len(h.pairings) >= 8 {
		http.Error(w, "Pairing limit reached", 429)
		return
	}
	var code string
	for {
		n, err := rand.Int(rand.Reader, big.NewInt(100000000))
		if err != nil {
			http.Error(w, "Pairing unavailable", 503)
			return
		}
		code = fmt.Sprintf("%08d", n)
		if _, exists := h.pairings[store.Hash(code)]; !exists {
			break
		}
	}
	expires := now.Add(5 * time.Minute)
	h.pairings[store.Hash(code)] = pairing{input.Kind, input.Machine, strings.TrimSpace(input.Name), expires}
	jsonResponse(w, map[string]any{"code": code, "expires_at": expires, "hub_url": h.origin, "kind": input.Kind, "machine": input.Machine})
}
func (h *Hub) exchangePairing(w http.ResponseWriter, r *http.Request) {
	if !h.mutation(w, r) {
		return
	}
	h.pairMu.Lock()
	defer h.pairMu.Unlock()
	now := time.Now()
	if now.Sub(h.pairWindow) > time.Minute {
		h.pairWindow = now
		h.pairAttempts = 0
	}
	h.pairAttempts++
	if h.pairAttempts > 20 {
		http.Error(w, "Too many pairing attempts; wait one minute", 429)
		return
	}
	var input struct {
		Code string `json:"code"`
		Kind string `json:"kind"`
	}
	if readJSON(w, r, &input) != nil {
		http.Error(w, "Invalid pairing", 400)
		return
	}
	code := strings.ReplaceAll(strings.TrimSpace(input.Code), " ", "")
	hash := store.Hash(code)
	p, ok := h.pairings[hash]
	if !ok || len(code) != 8 || now.After(p.Expires) || input.Kind != p.Kind {
		http.Error(w, "Pairing code invalid or expired", 401)
		return
	}
	// Consume before issuing the credential, including storage errors: never reuse an OTP.
	delete(h.pairings, hash)
	token := protocol.ID() + protocol.ID()
	id := protocol.ID()
	expires := now.Add(90 * 24 * time.Hour)
	if p.Kind == "agent" {
		if err := h.store.EnrollMachine(p.Machine, token); err != nil {
			http.Error(w, "Enrollment unavailable or machine already enrolled", 409)
			return
		}
		id = p.Machine
		machine := protocol.Machine{ID: id, Name: p.Name, Status: protocol.Offline, LastSeen: now.UTC()}
		if err := h.store.SaveMachine(machine); err != nil {
			http.Error(w, "Machine registry unavailable", 503)
			return
		}
		h.mu.Lock()
		h.machines[id] = machine
		snapshot := h.snapshot()
		h.broadcast(protocol.Message{Type: "snapshot", Snapshot: &snapshot}, "")
		h.mu.Unlock()
	} else if err := h.store.AddDevice(id, p.Name, token, expires); err != nil {
		http.Error(w, "Device enrollment unavailable", 503)
		return
	}
	h.mu.Lock()
	h.broadcast(protocol.Message{Type: "devices_changed"}, "")
	h.mu.Unlock()
	_ = h.store.Audit("device_enroll", p.Machine, "", id, p.Kind)
	if p.Kind == "operator" {
		http.SetCookie(w, &http.Cookie{Name: cookieName, Value: token, Path: "/", Expires: expires, MaxAge: 90 * 24 * 60 * 60, Secure: h.secure, HttpOnly: true, SameSite: http.SameSiteStrictMode})
	}
	jsonResponse(w, map[string]any{"id": id, "token": token, "kind": p.Kind, "expires_at": expires, "hub_url": h.origin})
}
func (h *Hub) devices(w http.ResponseWriter, r *http.Request) {
	token, _, ok := h.auth(w, r)
	if !ok {
		return
	}
	_ = h.store.TouchDevice(token)
	devices, err := h.store.Devices()
	if err != nil {
		http.Error(w, "Registry unavailable", 503)
		return
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	machines := []map[string]any{}
	for id, m := range h.machines {
		machines = append(machines, map[string]any{"machine": m, "access": h.store.MachineAccess(id)})
	}
	id, _, _ := h.store.DeviceLogin(token)
	jsonResponse(w, map[string]any{"operators": devices, "machines": machines, "current_device_id": id, "hub_url": h.origin, "chatgpt_device_management": false})
}
func (h *Hub) revokeDevice(w http.ResponseWriter, r *http.Request) {
	if !h.mutation(w, r) {
		return
	}
	if _, _, ok := h.auth(w, r); !ok {
		return
	}
	id := r.PathValue("id")
	if err := h.store.RevokeDevice(id); err != nil {
		http.Error(w, "Revocation unavailable", 503)
		return
	}
	h.mu.Lock()
	for o := range h.operators {
		if _, _, ok := h.store.OperatorLogin(o.token); !ok {
			o.peer.Close()
		}
	}
	h.broadcast(protocol.Message{Type: "devices_changed"}, "")
	h.mu.Unlock()
	_ = h.store.Audit("device_revoke", "", "", id, "ok")
	jsonResponse(w, map[string]bool{"ok": true})
}
func (h *Hub) removeDevice(w http.ResponseWriter, r *http.Request) {
	if !h.mutation(w, r) {
		return
	}
	if _, _, ok := h.auth(w, r); !ok {
		return
	}
	id := r.PathValue("id")
	if err := h.store.RemoveDevice(id); err != nil {
		http.Error(w, "Removal unavailable", 503)
		return
	}
	h.mu.Lock()
	for o := range h.operators {
		if _, _, ok := h.store.OperatorLogin(o.token); !ok {
			o.peer.Close()
		}
	}
	h.broadcast(protocol.Message{Type: "devices_changed"}, "")
	h.mu.Unlock()
	_ = h.store.Audit("device_remove", "", "", id, "ok")
	jsonResponse(w, map[string]bool{"ok": true})
}
func (h *Hub) manageMachine(w http.ResponseWriter, r *http.Request) {
	if !h.mutation(w, r) {
		return
	}
	if _, _, ok := h.auth(w, r); !ok {
		return
	}
	id, action := r.PathValue("id"), r.PathValue("action")
	if !machinePattern.MatchString(id) {
		http.Error(w, "Invalid machine", 400)
		return
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	if _, exists := h.machines[id]; !exists {
		http.Error(w, "Unknown machine", 404)
		return
	}
	var err error
	switch action {
	case "pause":
		err = h.store.SetPaused(id, true)
	case "resume":
		if h.store.MachineAccess(id) == "REVOKED" {
			http.Error(w, "Machine must be enrolled again", 409)
			return
		}
		err = h.store.SetPaused(id, false)
	case "revoke":
		err = h.store.Revoke(id)
	case "remove":
		err = h.store.RemoveMachine(id)
	default:
		http.Error(w, "Invalid action", 400)
		return
	}
	if err != nil {
		http.Error(w, "Registry update unavailable", 503)
		return
	}
	if action != "resume" {
		if a := h.agents[id]; a != nil {
			a.peer.Close()
			delete(h.agents, id)
		}
		m := h.machines[id]
		m.Status = protocol.Offline
		if action == "remove" {
			delete(h.machines, id)
		} else {
			h.machines[id] = m
			_ = h.store.SaveMachine(m)
		}
		for sid, s := range h.sessions {
			if s.MachineID == id {
				delete(h.buffers, sid)
				if action == "remove" {
					delete(h.sessions, sid)
				}
			}
		}
		// Pausing/revoking transport does not resolve Codex requests. Keep the
		// canonical last-known request and one-shot reservation until a fresh
		// epoch reconciles it. Explicit enrollment removal discards metadata.
		if action == "remove" {
			for rid, p := range h.requests {
				if p.MachineID == id {
					delete(h.requests, rid)
					delete(h.answering, rid)
				}
			}
		}
		for cid, f := range h.flights {
			if f.machine == id {
				res := protocol.Failure(protocol.Command{ID: cid, SessionID: f.session}, protocol.UnknownOutcome)
				f.operator.peer.Enqueue(protocol.Message{Type: "result", Result: &res})
				delete(h.flights, cid)
			}
		}
	}
	snap := h.snapshot()
	h.broadcast(protocol.Message{Type: "snapshot", Snapshot: &snap}, "")
	h.broadcast(protocol.Message{Type: "devices_changed"}, "")
	_ = h.store.Audit("machine_"+action, id, "", "", "ok")
	jsonResponse(w, map[string]bool{"ok": true})
}
