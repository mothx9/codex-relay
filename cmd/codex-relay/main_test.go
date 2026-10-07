package main

import (
	"context"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
)

func TestOccupiedPortDoesNotCreateCredentials(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	dir := filepath.Join(t.TempDir(), "unused-hub")
	err = runHub(context.Background(), []string{"--listen", listener.Addr().String(), "--data-dir", dir, "--disable-push"})
	if err == nil || !strings.Contains(err.Error(), "cannot listen") {
		t.Fatalf("expected bind failure, got %v", err)
	}
	if _, err = os.Stat(dir); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("failed hub created state: %v", err)
	}
}

func TestDoctorRejectsUnsafeOriginBeforeReadingToken(t *testing.T) {
	for _, origin := range []string{"http://192.0.2.60", "https://user:private@example.org", "https://example.org/path", "file:///tmp/local"} {
		err := doctor(context.Background(), []string{"--hub-url", origin, "--token-file", "/missing/token"})
		if err == nil || !strings.Contains(err.Error(), "Hub") || strings.Contains(err.Error(), "private") {
			t.Fatalf("unsafe origin accepted or leaked: %v", err)
		}
	}
}

func TestDoctorDoesNotForwardCredentialsOnRedirect(t *testing.T) {
	var received atomic.Int32
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		received.Add(1)
	}))
	defer target.Close()
	source := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, target.URL, http.StatusTemporaryRedirect)
	}))
	defer source.Close()
	dir := t.TempDir()
	token := filepath.Join(dir, "agent.token")
	if err := os.WriteFile(token, []byte("DIAGNOSTIC_TOKEN_CANARY"), 0600); err != nil {
		t.Fatal(err)
	}
	err := doctor(context.Background(), []string{"--hub-url", source.URL, "--data-dir", dir, "--machine", "test", "--token-file", token, "--codex", "/missing/codex"})
	if err != nil || received.Load() != 0 {
		t.Fatalf("diagnostics followed a credential redirect: %v, received=%d", err, received.Load())
	}
}
