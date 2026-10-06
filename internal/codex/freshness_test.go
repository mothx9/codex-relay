package codex

import (
	"github.com/mothx9/codex-relay/internal/protocol"
	"testing"
)

func TestInstalledWaitingFlagsAndPendingOverride(t *testing.T) {
	for _, flag := range []string{"waitingOnApproval", "waitingOnUserInput", "waitingForApproval", "waitingForUserInput"} {
		if Normalize("active", []string{flag}) != protocol.NeedsYou {
			t.Fatalf("unrecognized waiting flag %s", flag)
		}
	}
	a := &Adapter{requests: map[string]pending{"r": {Request: protocol.PendingRequest{ThreadID: "t", Kind: "user_input"}}}}
	s := a.capabilities(protocol.Session{ThreadID: "t", Status: protocol.Working})
	if s.Status != protocol.NeedsYou || !s.Capabilities.CanAnswer {
		t.Fatal("status update obscured pending request")
	}
}
