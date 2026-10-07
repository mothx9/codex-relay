package hub

import (
	"github.com/mothx9/codex-relay/internal/protocol"
	"net/http"
	"sort"
	"time"
)

// Explicit allowlist: no credentials, request payloads, transcript or account identity.
type machineDiagnostics struct {
	ID            string             `json:"id"`
	State         string             `json:"state"`
	AgentVersion  string             `json:"agent_version"`
	CodexVersion  string             `json:"codex_version"`
	Adapter       string             `json:"adapter"`
	LastSeen      time.Time          `json:"last_seen"`
	SnapshotAgeMS *int64             `json:"snapshot_age_ms,omitempty"`
	Freshness     protocol.Freshness `json:"freshness"`
	Sessions      int                `json:"sessions"`
	Hot           int                `json:"hot"`
	Pending       int                `json:"pending"`
}

func (h *Hub) diagnosticMachines(now time.Time) []machineDiagnostics {
	out := make([]machineDiagnostics, 0, len(h.machines))
	for _, m := range h.machines {
		d := machineDiagnostics{ID: m.ID, State: m.Status, AgentVersion: m.AgentVersion, CodexVersion: m.CodexVersion, Adapter: m.Adapter, LastSeen: m.LastSeen, Freshness: m.Freshness}
		if !m.Freshness.LastSnapshot.IsZero() {
			age := now.Sub(m.Freshness.LastSnapshot).Milliseconds()
			d.SnapshotAgeMS = &age
		}
		for _, s := range h.sessions {
			if s.MachineID == m.ID {
				d.Sessions++
				if s.Status == protocol.Working || s.Status == protocol.NeedsYou || !s.ReadOnly {
					d.Hot++
				}
			}
		}
		for _, r := range h.requests {
			if r.MachineID == m.ID {
				d.Pending++
			}
		}
		out = append(out, d)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out
}
func (h *Hub) diagnostics(w http.ResponseWriter, r *http.Request) {
	if _, _, ok := h.auth(w, r); !ok {
		return
	}
	h.mu.Lock()
	machines := h.diagnosticMachines(time.Now())
	h.mu.Unlock()
	database := "unavailable"
	var one int
	if err := h.store.DB.QueryRow(`SELECT 1`).Scan(&one); err == nil && one == 1 {
		database = "reachable"
	}
	jsonResponse(w, map[string]any{"database": database, "hub_version": h.config.Version, "protocol_version": protocol.Version, "machines": machines, "transport": "unspecified", "clock_note": "cross-host timing includes clock offset"})
}
