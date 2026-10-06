package hub

import (
	"github.com/mothx9/codex-relay/internal/protocol"
	"testing"
)

func TestColdDiscoveryCannotGrantCanonicalState(t *testing.T) {
	h := &Hub{machines: map[string]protocol.Machine{"m": {ID: "m"}}, sessions: map[string]protocol.Session{"m~hot": {ID: "m~hot", MachineID: "m", ThreadID: "hot", Status: protocol.NeedsYou}}}
	s, ok := h.discoverySession("m~cold")
	if !ok || !s.ReadOnly || s.Capabilities.CanSend || len(h.sessions) != 1 {
		t.Fatal("discovery mutated state or granted control")
	}
	for _, id := range []string{"unknown~cold", "m~", "m~cold~other", "m~bad\n"} {
		if _, ok := h.discoverySession(id); ok {
			t.Fatal("accepted invalid identity", id)
		}
	}
	page := protocol.Result{MachineID: "m", Sessions: []protocol.Session{{ID: "m~cold", MachineID: "m", ThreadID: "cold"}}}
	if !validCatalogue("m", page) {
		t.Fatal("valid page rejected")
	}
	page.Sessions[0].MachineID = "other"
	if validCatalogue("m", page) {
		t.Fatal("cross-machine page accepted")
	}
	page.Sessions[0].MachineID = "m"
	page.Sessions = append(page.Sessions, page.Sessions[0])
	if validCatalogue("m", page) {
		t.Fatal("duplicate page identity accepted")
	}
	if h.sessions["m~hot"].Status != protocol.NeedsYou {
		t.Fatal("discovery replaced pending")
	}
}
