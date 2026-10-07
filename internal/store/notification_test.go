package store

import (
	"github.com/mothx9/codex-relay/internal/protocol"
	"path/filepath"
	"testing"
)

func TestNotificationStateCountsCanonicalRequestsAndResolution(t *testing.T) {
	s, err := Open(filepath.Join(t.TempDir(), "db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	for _, id := range []string{"a", "b"} {
		if err := s.SavePending(protocol.PendingRequest{ID: id, MachineID: "machine", SessionID: "machine~thread", Status: "pending"}); err != nil {
			t.Fatal(err)
		}
	}
	count, pending, err := s.NotificationState("a")
	if err != nil || count != 2 || !pending {
		t.Fatal(count, pending, err)
	}
	if _, err = s.DB.Exec(`DELETE FROM pending_requests WHERE id='a'`); err != nil {
		t.Fatal(err)
	}
	count, pending, err = s.NotificationState("a")
	if err != nil || count != 1 || pending {
		t.Fatal("resolved request still notifiable", count, pending, err)
	}
}
