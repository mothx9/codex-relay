package hub

import (
	"encoding/json"
	"github.com/mothx9/codex-relay/internal/store"
	"io"
	"net/http"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestNativePushStatusIsControllerScopedAndSecretFree(t *testing.T) {
	h, database, server := testHub(t, filepath.Join(t.TempDir(), "hub.db"))
	defer database.Close()
	defer server.Close()
	defer h.Close()
	for _, pair := range []struct{ id, token string }{{"phone", strings.Repeat("b", 64)}, {"other", strings.Repeat("c", 64)}} {
		if err := database.AddDevice(pair.id, pair.id, pair.token, time.Now().Add(time.Hour)); err != nil {
			t.Fatal(err)
		}
	}
	secret := strings.Repeat("ab", 32)
	if err := database.SubscribeAPNS(store.APNSSubscription{DeviceID: "phone", Token: secret, Environment: "sandbox", Privacy: true}); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		token      string
		status     int
		registered bool
	}{{"", 401, false}, {strings.Repeat("b", 64), 200, true}, {strings.Repeat("c", 64), 200, false}} {
		req, _ := http.NewRequest("GET", server.URL+"/api/native-push/status", nil)
		if tc.token != "" {
			req.Header.Set("Authorization", "Bearer "+tc.token)
		}
		response, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		body, _ := io.ReadAll(response.Body)
		response.Body.Close()
		if response.StatusCode != tc.status {
			t.Fatalf("status %d", response.StatusCode)
		}
		if strings.Contains(string(body), secret) || strings.Contains(string(body), "phone") {
			t.Fatal("device secret/identity leaked")
		}
		if tc.status == 200 {
			var state struct{ Configured, Registered bool }
			if json.Unmarshal(body, &state) != nil || state.Configured || state.Registered != tc.registered {
				t.Fatalf("incorrect registration %s", body)
			}
		}
	}
}
