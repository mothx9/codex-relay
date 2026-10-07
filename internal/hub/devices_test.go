package hub

import (
	"encoding/json"
	"github.com/mothx9/codex-relay/internal/protocol"
	"github.com/mothx9/codex-relay/internal/store"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func devicePost(t *testing.T, srv *httptest.Server, path, body, cookie, token string) (int, map[string]any) {
	t.Helper()
	req, _ := http.NewRequest("POST", srv.URL+path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Origin", "http://relay.test")
	req.Header.Set("X-Relay-CSRF", "1")
	if cookie != "" {
		req.Header.Set("Cookie", cookie)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var result map[string]any
	if resp.StatusCode == 200 {
		if err = json.NewDecoder(resp.Body).Decode(&result); err != nil {
			t.Fatal(err)
		}
	}
	return resp.StatusCode, result
}
func TestPairingAndImmediateDeviceRevocation(t *testing.T) {
	h, s, srv := testHub(t, filepath.Join(t.TempDir(), "db"))
	defer s.Close()
	defer srv.Close()
	defer h.Close()
	if code, _ := devicePost(t, srv, "/api/pairing/code", `{"kind":"operator","name":"phone"}`, "", ""); code != 401 {
		t.Fatal("anonymous pairing mint")
	}
	cookie := login(t, srv)
	status, issued := devicePost(t, srv, "/api/pairing/code", `{"kind":"operator","name":"phone"}`, cookie, "")
	if status != 200 {
		t.Fatal(status)
	}
	code := issued["code"].(string)
	if len(code) != 8 {
		t.Fatal("code length")
	}
	status, credential := devicePost(t, srv, "/api/pairing/exchange", `{"kind":"operator","code":"`+code+`"}`, "", "")
	if status != 200 {
		t.Fatal(status)
	}
	token := credential["token"].(string)
	id := credential["id"].(string)
	if status, _ = devicePost(t, srv, "/api/pairing/exchange", `{"kind":"operator","code":"`+code+`"}`, "", ""); status != 401 {
		t.Fatal("OTP reused")
	}
	ui := testWS(t, srv, http.Header{"Authorization": []string{"Bearer " + token}, "Origin": []string{"http://relay.test"}}, "/api/ui")
	defer ui.Close()
	readUntil(t, ui, func(m protocol.Message) bool { return m.Type == "snapshot" })
	if status, _ = devicePost(t, srv, "/api/devices/"+id+"/revoke", `{}`, cookie, ""); status != 200 {
		t.Fatal(status)
	}
	_ = ui.SetReadDeadline(time.Now().Add(time.Second))
	for {
		if _, _, err := ui.ReadMessage(); err != nil {
			break
		}
		t.Fatal("revoked socket received data")
	}
	if _, _, ok := s.DeviceLogin(token); ok {
		t.Fatal("revoked token remains valid")
	}
	if status, _ = devicePost(t, srv, "/api/pairing/code", `{"kind":"operator","name":"other"}`, "", token); status != 401 {
		t.Fatal("revoked token minted pairing")
	}
	var hash string
	if err := s.DB.QueryRow(`SELECT token_hash FROM operator_devices WHERE id=?`, id).Scan(&hash); err != nil || hash == token {
		t.Fatal("plaintext credential stored")
	}
}
func TestPairingExpiryWrongKindRateLimitAndConcurrentConsumption(t *testing.T) {
	h, s, srv := testHub(t, filepath.Join(t.TempDir(), "db"))
	defer s.Close()
	defer srv.Close()
	defer h.Close()
	cookie := login(t, srv)
	_, issued := devicePost(t, srv, "/api/pairing/code", `{"kind":"operator","name":"phone"}`, cookie, "")
	code := issued["code"].(string)
	if status, _ := devicePost(t, srv, "/api/pairing/exchange", `{"kind":"agent","code":"`+code+`"}`, "", ""); status != 401 {
		t.Fatal("cross-kind redemption")
	}
	h.pairMu.Lock()
	p := h.pairings[store.Hash(code)]
	p.Expires = time.Now().Add(-time.Second)
	h.pairings[store.Hash(code)] = p
	h.pairMu.Unlock()
	if status, _ := devicePost(t, srv, "/api/pairing/exchange", `{"kind":"operator","code":"`+code+`"}`, "", ""); status != 401 {
		t.Fatal("expired code")
	}
	_, issued = devicePost(t, srv, "/api/pairing/code", `{"kind":"operator","name":"phone"}`, cookie, "")
	code = issued["code"].(string)
	var wg sync.WaitGroup
	statuses := make(chan int, 2)
	for range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			status, _ := devicePost(t, srv, "/api/pairing/exchange", `{"kind":"operator","code":"`+code+`"}`, "", "")
			statuses <- status
		}()
	}
	wg.Wait()
	close(statuses)
	ok := 0
	for status := range statuses {
		if status == 200 {
			ok++
		}
	}
	if ok != 1 {
		t.Fatal("concurrent OTP replay", ok)
	}
	for range 20 {
		devicePost(t, srv, "/api/pairing/exchange", `{"kind":"operator","code":"xxxxxxxx"}`, "", "")
	}
	if status, _ := devicePost(t, srv, "/api/pairing/exchange", `{"kind":"operator","code":"xxxxxxxx"}`, "", ""); status != 429 {
		t.Fatal("unbounded guessing")
	}
}
func TestMachinePauseResumeAndRemoval(t *testing.T) {
	h, s, srv := testHub(t, filepath.Join(t.TempDir(), "db"))
	defer s.Close()
	defer srv.Close()
	defer h.Close()
	cookie := login(t, srv)
	s.Token("m", testToken)
	a := testWS(t, srv, http.Header{"X-Relay-Machine": []string{"m"}, "Authorization": []string{"Bearer " + testToken}}, "/api/agent")
	defer a.Close()
	_ = a.WriteJSON(protocol.Message{Version: 1, Type: "announce", Machine: &protocol.Machine{ID: "m", Name: "M"}, Sessions: []protocol.Session{{ID: "m~t", MachineID: "m", ThreadID: "t", Status: protocol.Ready}}, Epoch: "e"})
	ui := testWS(t, srv, http.Header{"Cookie": []string{cookie}, "Origin": []string{"http://relay.test"}}, "/api/ui")
	defer ui.Close()
	readUntil(t, ui, func(m protocol.Message) bool { return m.Type == "snapshot" && len(m.Snapshot.Machines) == 1 })
	for _, action := range []string{"pause", "resume", "remove"} {
		if status, _ := devicePost(t, srv, "/api/machines/m/"+action, `{}`, cookie, ""); status != 200 {
			t.Fatal(action, status)
		}
		if action == "pause" && s.Authenticate("m", testToken) {
			t.Fatal("paused agent authenticated")
		}
		if action == "resume" && !s.Authenticate("m", testToken) {
			t.Fatal("resume failed")
		}
	}
	if s.Authenticate("m", testToken) {
		t.Fatal("removed agent authenticated")
	}
	snap, err := s.Load()
	if err != nil || len(snap.Sessions) != 0 || len(snap.Machines) != 0 {
		t.Fatal("removed metadata retained")
	}
	if err = s.EnrollMachine("m", testToken+"new"); err != nil {
		t.Fatal("explicit re-enrollment", err)
	}
	if err = s.EnrollMachine("m", testToken+"replace"); err == nil {
		t.Fatal("silently replaced credential")
	}
}

func TestMachineAccessChangesPreserveUnresolvedRequestUntilEnrollmentRemoval(t *testing.T) {
	h, s, server := testHub(t, filepath.Join(t.TempDir(), "db"))
	defer s.Close()
	defer server.Close()
	defer h.Close()
	cookie := login(t, server)
	if err := s.Token("m", testToken); err != nil {
		t.Fatal(err)
	}
	machine := protocol.Machine{ID: "m", Status: protocol.Online}
	session := protocol.Session{ID: "m~t", MachineID: "m", ThreadID: "t", Status: protocol.NeedsYou}
	request := protocol.PendingRequest{ID: "pending", SessionID: session.ID, MachineID: "m", ThreadID: "t", Status: "pending"}
	h.mu.Lock()
	h.machines["m"] = machine
	h.sessions[session.ID] = session
	h.requests[request.ID] = request
	h.answering[request.ID] = "one-shot-reservation"
	h.mu.Unlock()
	if err := s.ReplaceMachineState(machine, []protocol.Session{session}, []protocol.PendingRequest{request}); err != nil {
		t.Fatal(err)
	}
	for _, action := range []string{"pause", "resume", "revoke"} {
		status, _ := devicePost(t, server, "/api/machines/m/"+action, `{}`, cookie, "")
		if status != 200 {
			t.Fatal(action, status)
		}
		h.mu.Lock()
		snap := h.snapshot()
		reserved := h.answering[request.ID]
		h.mu.Unlock()
		if len(snap.Requests) != 1 || len(snap.Sessions) != 1 || snap.Sessions[0].Status != protocol.NeedsYou || snap.Sessions[0].Fresh || reserved == "" {
			t.Fatal("access change invented request resolution or live state", action)
		}
		durable, err := s.Load()
		if err != nil || len(durable.Requests) != 1 {
			t.Fatal("lost durable routing", action, err)
		}
	}
	status, _ := devicePost(t, server, "/api/machines/m/remove", `{}`, cookie, "")
	if status != 200 {
		t.Fatal(status)
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	if len(h.requests) != 0 || len(h.answering) != 0 {
		t.Fatal("explicit removal retained routing")
	}
}
