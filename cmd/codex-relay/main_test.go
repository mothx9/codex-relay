package main

import (
	"context"
	"errors"
	"net"
	"os"
	"path/filepath"
	"strings"
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
