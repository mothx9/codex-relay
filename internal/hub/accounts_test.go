package hub

import (
	"github.com/mothx9/codex-relay/internal/protocol"
	"net/http"
	"path/filepath"
	"testing"
	"time"
)

func TestAccountRegistryIdentityFreshnessAndClockIsolation(t *testing.T) {
	now := time.Now().UTC()
	machine := func(id, account string, offset time.Duration, state string) protocol.Machine {
		return protocol.Machine{ID: id, Status: state, Freshness: protocol.Freshness{ConnectedAt: now.Add(-time.Minute)}, Account: &protocol.Account{ID: account, Kind: "chatgpt", Email: "same@example.invalid", Plan: id, HubObservedAt: now.Add(offset), ObservedAt: now.Add(24 * time.Hour)}}
	}
	fleet := map[string]protocol.Machine{"a": machine("a", "one", -10*time.Second, protocol.Online), "b": machine("b", "one", -time.Second, protocol.Offline), "c": machine("c", "two", 0, protocol.Online)}
	entries := accountRegistry(fleet, now)
	if len(entries) != 2 {
		t.Fatal("distinct account IDs merged by email")
	}
	for _, e := range entries {
		if e.Account.ID == "one" && (e.SourceMachine != "a" || !e.Fresh || len(e.Machines) != 2) {
			t.Fatal("offline source won over current source", e)
		}
	}
	b := fleet["b"]
	b.Status = protocol.Online
	fleet["b"] = b
	for _, e := range accountRegistry(fleet, now) {
		if e.Account.ID == "one" && e.SourceMachine != "b" {
			t.Fatal("newest Hub receipt did not win")
		}
	}
	for _, e := range accountRegistry(fleet, now.Add(6*time.Minute)) {
		if e.Fresh {
			t.Fatal("aged account advertised current")
		}
	}
	// No current-connection account read yet: cached identity remains visible but stale.
	a := fleet["a"]
	a.Freshness.ConnectedAt = now
	fleet["a"] = a
	delete(fleet, "b")
	for _, e := range accountRegistry(fleet, now) {
		if e.Account.ID == "one" && e.Fresh {
			t.Fatal("old connection account advertised current")
		}
	}
}
func TestAccountRegistryFallbackDoesNotMergeAnonymousCredentials(t *testing.T) {
	fleet := map[string]protocol.Machine{}
	for _, id := range []string{"a", "b"} {
		fleet[id] = protocol.Machine{ID: id, Account: &protocol.Account{Kind: "apiKey"}}
	}
	if len(accountRegistry(fleet, time.Now())) != 2 {
		t.Fatal("unrelated API credentials merged")
	}
	for id, m := range fleet {
		m.Account = &protocol.Account{Kind: "chatgpt", Email: "same@example.invalid"}
		fleet[id] = m
	}
	got := accountRegistry(fleet, time.Now())
	if len(got) != 1 || got[0].IdentityBasis != "email" || got[0].Fresh {
		t.Fatal("fallback identity or unavailable freshness hidden")
	}
}

func TestAccountRegistryRequiresControllerAuthentication(t *testing.T) {
	_, store, server := testHub(t, filepath.Join(t.TempDir(), "hub.db"))
	defer store.Close()
	defer server.Close()
	response, err := http.Get(server.URL + "/api/accounts")
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusUnauthorized {
		t.Fatal("unauthenticated account metadata exposed", response.StatusCode)
	}
}
