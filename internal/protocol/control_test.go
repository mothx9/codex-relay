package protocol

import "testing"

func TestControlPreconditions(t *testing.T) {
	working := Session{Status: Working, TurnID: "active", Capabilities: Capabilities{CanFollowUp: true, CanSteer: true, CanInterrupt: true}}
	for _, tc := range []struct {
		name    string
		session Session
		command Command
		want    string
	}{
		{"working alone cannot steer", Session{Status: Working, TurnID: "active"}, Command{Kind: Steer, TurnID: "active"}, NotSteerable},
		{"steer requires active ID", Session{Status: Working, Capabilities: Capabilities{CanSteer: true}}, Command{Kind: Steer}, NotSteerable},
		{"stale ID", working, Command{Kind: Steer, TurnID: "previous"}, TurnChanged},
		{"valid steer", working, Command{Kind: Steer, TurnID: "active"}, ""},
		{"follow-up without turn ID", Session{Status: Working, Capabilities: Capabilities{CanFollowUp: true}}, Command{Kind: FollowUpCommand}, ""},
		{"follow-up unavailable", Session{Status: Working}, Command{Kind: FollowUpCommand}, FollowUpUnavailable},
		{"new turn ready", Session{Status: Ready, Capabilities: Capabilities{CanSend: true}}, Command{Kind: NewTurn}, ""},
		{"new turn working", working, Command{Kind: NewTurn}, TurnChanged},
		{"read only", Session{ReadOnly: true}, Command{Kind: NewTurn}, SessionReadOnly},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := CheckControl(tc.session, tc.command); got != tc.want {
				t.Fatalf("got %q want %q", got, tc.want)
			}
		})
	}
}
func TestCanonicalErrorsAreSafe(t *testing.T) {
	for _, code := range []string{TurnChanged, NotSteerable, FollowUpUnavailable, SessionReadOnly, MachineOffline, PendingRequestChanged, QueueChanged, CodexDisconnected, CodexRejected, UnknownOutcome} {
		r := Failure(Command{ID: "command", SessionID: "session"}, code)
		if r.OK || r.ID != "command" || r.SessionID != "session" || r.ErrorCode != code || r.Error == "" {
			t.Fatal(r)
		}
		if code == UnknownOutcome && r.Retryable {
			t.Fatal("unknown outcome must not auto-retry")
		}
	}
	if r := Failure(Command{}, "raw secret backend text"); r.ErrorCode != CodexRejected {
		t.Fatal(r)
	}
}
