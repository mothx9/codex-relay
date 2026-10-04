package store

import (
	"github.com/mothx9/codex-relay/internal/protocol"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestMetadataAndNoTranscript(t *testing.T) {
	path := filepath.Join(t.TempDir(), "relay.db")
	s, e := Open(path)
	if e != nil {
		t.Fatal(e)
	}
	defer s.Close()
	v := protocol.Session{ID: "m~t", MachineID: "m", ThreadID: "t", Title: "title", Status: protocol.Working}
	if e = s.SaveSession(v); e != nil {
		t.Fatal(e)
	}
	secret := "CANARY_TRANSCRIPT_NOT_FOR_SQLITE"
	r := protocol.PendingRequest{ID: "r", MachineID: "m", SessionID: v.ID, ThreadID: "t", Description: secret, Operation: secret, Payload: []byte(`{"text":"` + secret + `"}`), CreatedAt: time.Now(), ExpiresAt: time.Now().Add(time.Hour), Status: "pending"}
	if e = s.SavePending(r); e != nil {
		t.Fatal(e)
	}
	_ = s.SaveMachine(protocol.Machine{ID: "m", Status: protocol.Online})
	snap, e := s.Load()
	if e != nil || len(snap.Sessions) != 1 || snap.Machines[0].Status != protocol.Offline || !snap.Sessions[0].ReadOnly {
		t.Fatalf("%+v %v", snap, e)
	}
	for _, p := range []string{path, path + "-wal"} {
		b, e := os.ReadFile(p)
		if e != nil {
			t.Fatal(e)
		}
		if strings.Contains(string(b), secret) {
			t.Fatal("transcript persisted")
		}
	}
	if e = s.Token("m", "a-secret-token"); e != nil {
		t.Fatal(e)
	}
	if !s.Authenticate("m", "a-secret-token") || s.Authenticate("x", "a-secret-token") || s.Authenticate("m", "wrong") {
		t.Fatal("token auth")
	}
	_ = s.Revoke("m")
	if s.Authenticate("m", "a-secret-token") {
		t.Fatal("revoked token accepted")
	}
	ok, e := s.NotifyOnce("turn")
	if !ok || e != nil {
		t.Fatal(e)
	}
	ok, e = s.NotifyOnce("turn")
	if ok || e != nil {
		t.Fatal("notification duplicate")
	}
	_ = s.NewLogin("operator", time.Now().Add(time.Hour))
	if _, ok := s.Login("operator"); !ok {
		t.Fatal("login")
	}
	_ = s.Logout("operator")
	if _, ok := s.Login("operator"); ok {
		t.Fatal("logout")
	}
	info, _ := os.Stat(path)
	if info.Mode().Perm() != 0600 {
		t.Fatal("db permissions")
	}
}
