package hub

import (
	"github.com/mothx9/codex-relay/internal/store"
	"net/http"
)

func (h *Hub) subscribeAPNS(w http.ResponseWriter, r *http.Request) {
	if !h.mutation(w, r) {
		return
	}
	token, _, ok := h.auth(w, r)
	if !ok {
		return
	}
	if h.push.APNS == nil {
		http.Error(w, "Native push requires Hub APNs configuration", 503)
		return
	}
	id, _, ok := h.store.DeviceLogin(token)
	if !ok {
		http.Error(w, "Pair this operator device first", 403)
		return
	}
	var input struct {
		Token       string `json:"token"`
		Environment string `json:"environment"`
		Privacy     bool   `json:"privacy"`
	}
	if readJSON(w, r, &input) != nil {
		http.Error(w, "Invalid APNs registration", 400)
		return
	}
	if h.store.SubscribeAPNS(store.APNSSubscription{DeviceID: id, Token: input.Token, Environment: input.Environment, Privacy: input.Privacy}) != nil {
		http.Error(w, "APNs registration rejected", 400)
		return
	}
	jsonResponse(w, map[string]bool{"ok": true})
}
func (h *Hub) unsubscribeAPNS(w http.ResponseWriter, r *http.Request) {
	if !h.mutation(w, r) {
		return
	}
	token, _, ok := h.auth(w, r)
	if !ok {
		return
	}
	id, _, ok := h.store.DeviceLogin(token)
	if !ok {
		http.Error(w, "Paired device required", 403)
		return
	}
	if h.store.UnsubscribeAPNS(id) != nil {
		http.Error(w, "Push removal unavailable", 503)
		return
	}
	jsonResponse(w, map[string]bool{"ok": true})
}
