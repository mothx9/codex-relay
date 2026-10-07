package hub

import (
	"crypto/sha256"
	"encoding/hex"
	"github.com/mothx9/codex-relay/internal/protocol"
	"net/http"
	"sort"
	"strings"
	"time"
)

type accountEntry struct {
	ID            string           `json:"id"`
	IdentityBasis string           `json:"identity_basis"`
	Account       protocol.Account `json:"account"`
	Machines      []string         `json:"machines"`
	SourceMachine string           `json:"source_machine"`
	Fresh         bool             `json:"fresh"`
	UpdatedAt     time.Time        `json:"updated_at"`
}

// Derived from accepted machine state, never a second login or credential store.
// Receipt time on the Hub orders reports across workers without comparing clocks.
func accountRegistry(machines map[string]protocol.Machine, now time.Time) []accountEntry {
	entries := map[string]accountEntry{}
	ids := make([]string, 0, len(machines))
	for id := range machines {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	for _, id := range ids {
		m := machines[id]
		if m.Account == nil || m.Account.Kind == "" {
			continue
		}
		a := m.Account
		basis, identity := "machine", id
		if a.ID != "" {
			basis, identity = "account_id", a.ID
		} else if a.Kind == "chatgpt" && strings.TrimSpace(a.Email) != "" {
			// Explicitly weaker fallback: API-key/anonymous accounts never coalesce.
			basis, identity = "email", strings.ToLower(strings.TrimSpace(a.Email))
		}
		digest := sha256.Sum256([]byte(a.Kind + "/" + basis + "/" + identity))
		key := hex.EncodeToString(digest[:16])
		fresh := m.Status == protocol.Online && !a.HubObservedAt.IsZero() && !a.HubObservedAt.Before(m.Freshness.ConnectedAt) && now.Sub(a.HubObservedAt) <= 5*time.Minute
		old, exists := entries[key]
		sources := append(old.Machines, id)
		if !exists || (fresh && !old.Fresh) || (fresh == old.Fresh && a.HubObservedAt.After(old.UpdatedAt)) {
			old = accountEntry{ID: key, IdentityBasis: basis, Account: *a, SourceMachine: id, Fresh: fresh, UpdatedAt: a.HubObservedAt}
		}
		old.Machines = sources
		entries[key] = old
	}
	result := make([]accountEntry, 0, len(entries))
	for _, entry := range entries {
		result = append(result, entry)
	}
	sort.Slice(result, func(i, j int) bool { return result[i].ID < result[j].ID })
	return result
}
func (h *Hub) accounts(w http.ResponseWriter, r *http.Request) {
	if _, _, ok := h.auth(w, r); !ok {
		return
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	jsonResponse(w, map[string]any{"accounts": accountRegistry(h.machines, time.Now())})
}
