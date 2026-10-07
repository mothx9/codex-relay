package push

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"github.com/mothx9/codex-relay/internal/protocol"
	"github.com/mothx9/codex-relay/internal/store"
	"io"
	"math/big"
	"net/http"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

type roundTrip func(*http.Request) (*http.Response, error)

func (f roundTrip) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func TestAPNSTokenAuthenticationPrivacyAndExpiry(t *testing.T) {
	key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	der, _ := x509.MarshalPKCS8PrivateKey(key)
	raw := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})
	a, err := NewAPNS(APNSConfig{TeamID: "AAAAAAAAAA", KeyID: "BBBBBBBBBB", Topic: "net.codex-relay.iphone"}, raw)
	if err != nil {
		t.Fatal(err)
	}
	count := 0
	a.client = &http.Client{Transport: roundTrip(func(r *http.Request) (*http.Response, error) {
		count++
		if r.URL.Host != "api.sandbox.push.apple.com" || r.Header.Get("apns-push-type") != "alert" || r.Header.Get("apns-topic") != "net.codex-relay.iphone" {
			t.Fatal("wrong APNs routing")
		}
		jwt := strings.TrimPrefix(r.Header.Get("authorization"), "bearer ")
		parts := strings.Split(jwt, ".")
		if len(parts) != 3 {
			t.Fatal("invalid JWT")
		}
		sig, _ := base64.RawURLEncoding.DecodeString(parts[2])
		digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
		if len(sig) != 64 || !ecdsa.Verify(&key.PublicKey, digest[:], new(big.Int).SetBytes(sig[:32]), new(big.Int).SetBytes(sig[32:])) {
			t.Fatal("invalid ES256 signature")
		}
		body, _ := io.ReadAll(r.Body)
		if strings.Contains(string(body), "PRIVATE_PROJECT") || strings.Contains(string(body), "PRIVATE_TITLE") {
			t.Fatal("lock screen privacy leak")
		}
		var payload map[string]any
		_ = json.Unmarshal(body, &payload)
		if payload["session_id"] != "m~t" {
			t.Fatal("deep link lost")
		}
		status := 200
		body = []byte(`{}`)
		if count == 2 {
			status = 410
			body = []byte(`{"reason":"Unregistered"}`)
		}
		return &http.Response{StatusCode: status, Body: io.NopCloser(strings.NewReader(string(body))), Header: http.Header{}}, nil
	})}
	sub := store.APNSSubscription{DeviceID: "phone", Token: strings.Repeat("ab", 32), Environment: "sandbox", Privacy: true}
	n := Notice{Key: "request/id", Kind: "request", SessionID: "m~t", Project: "PRIVATE_PROJECT", Title: "PRIVATE_TITLE"}
	if gone, err := a.Send(context.Background(), n, sub); err != nil || gone {
		t.Fatal(err, gone)
	}
	if gone, err := a.Send(context.Background(), n, sub); err != nil || !gone {
		t.Fatal("expired subscription not removed", err)
	}
	first, _ := a.bearer(time.Now())
	second, _ := a.bearer(time.Now().Add(time.Minute))
	if first != second {
		t.Fatal("JWT refreshed unnecessarily")
	}
}
func TestAPNSSubscriptionBoundToLiveDevice(t *testing.T) {
	s, err := store.Open(filepath.Join(t.TempDir(), "db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	sub := store.APNSSubscription{DeviceID: "phone", Token: strings.Repeat("ab", 32), Environment: "sandbox", Privacy: true}
	if s.SubscribeAPNS(sub) == nil {
		t.Fatal("unpaired device registered")
	}
	if err = s.AddDevice("phone", "phone", strings.Repeat("c", 64), time.Now().Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	if err = s.SubscribeAPNS(sub); err != nil {
		t.Fatal(err)
	}
	_ = s.RevokeDevice("phone")
	subs, err := s.APNSSubscriptions()
	if err != nil || len(subs) != 0 {
		t.Fatal("revoked device receives push")
	}
	_ = s.RemoveDevice("phone")
	var count int
	_ = s.DB.QueryRow(`SELECT count(*) FROM apns_subscriptions`).Scan(&count)
	if count != 0 {
		t.Fatal("removed device token retained")
	}
}

func TestNativePayloadRoutesMachineAndUsesCanonicalBadge(t *testing.T) {
	key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	der, _ := x509.MarshalPKCS8PrivateKey(key)
	a, err := NewAPNS(APNSConfig{TeamID: "AAAAAAAAAA", KeyID: "BBBBBBBBBB", Topic: "net.codex-relay.iphone"}, pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}))
	if err != nil {
		t.Fatal(err)
	}
	a.client = &http.Client{Transport: roundTrip(func(r *http.Request) (*http.Response, error) {
		var payload struct {
			APS struct {
				Badge int
				Alert map[string]string
			}
			Machine string `json:"machine_id"`
			Kind    string `json:"kind"`
		}
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatal(err)
		}
		if payload.APS.Badge != 3 || payload.Machine != "workstation" || payload.Kind != "machine_offline" {
			t.Fatalf("lost navigation/badge: %+v", payload)
		}
		if strings.Contains(payload.APS.Alert["title"], "PRIVATE") {
			t.Fatal("privacy leak")
		}
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader("{}")), Header: http.Header{}}, nil
	})}
	_, err = a.Send(context.Background(), Notice{Kind: "machine_offline", MachineID: "workstation", Machine: "PRIVATE_MACHINE", Badge: 3}, store.APNSSubscription{Token: strings.Repeat("ab", 32), Privacy: true})
	if err != nil {
		t.Fatal(err)
	}
}

func TestNativeWorkerSuppressesResolvedRequestsAndTargetsTestController(t *testing.T) {
	s, err := store.Open(filepath.Join(t.TempDir(), "db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	for _, id := range []string{"phone", "tablet"} {
		if err := s.AddDevice(id, id, strings.Repeat(id, 16), time.Now().Add(time.Hour)); err != nil {
			t.Fatal(err)
		}
		token := strings.Repeat("ab", 32)
		if id == "tablet" {
			token = strings.Repeat("cd", 32)
		}
		if err := s.SubscribeAPNS(store.APNSSubscription{DeviceID: id, Token: token, Environment: "sandbox", Privacy: true}); err != nil {
			t.Fatal(err)
		}
	}
	if err := s.SavePending(protocol.PendingRequest{ID: "current", SessionID: "m~t", MachineID: "m", Status: "pending"}); err != nil {
		t.Fatal(err)
	}
	key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	der, _ := x509.MarshalPKCS8PrivateKey(key)
	a, err := NewAPNS(APNSConfig{TeamID: "AAAAAAAAAA", KeyID: "BBBBBBBBBB", Topic: "net.codex-relay.iphone"}, pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}))
	if err != nil {
		t.Fatal(err)
	}
	type delivery struct {
		path string
		body string
	}
	deliveries := make(chan delivery, 10)
	a.client = &http.Client{Transport: roundTrip(func(r *http.Request) (*http.Response, error) {
		raw, _ := io.ReadAll(r.Body)
		deliveries <- delivery{r.URL.Path, string(raw)}
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader("{}")), Header: http.Header{}}, nil
	})}
	w := New(s, Keys{}, "")
	w.APNS = a
	w.Enqueue(Notice{Kind: "request", Key: "resolved", RequestID: "resolved", SessionID: "m~t"})
	w.Enqueue(Notice{Kind: "request", Key: "current", RequestID: "current", SessionID: "m~t"})
	w.Enqueue(Notice{Kind: "request", Key: "current", RequestID: "current", SessionID: "m~t"})
	w.Enqueue(Notice{Kind: "test", Key: "test", DeviceID: "phone"})
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan struct{})
	go func() { defer close(done); w.Run(ctx) }()
	for i := 0; i < 3; i++ {
		select {
		case got := <-deliveries:
			if strings.Contains(got.body, "resolved") || !strings.Contains(got.body, `"badge":1`) {
				t.Errorf("incorrect canonical delivery: %s", got.body)
			}
			if strings.Contains(got.body, `"kind":"test"`) && !strings.HasSuffix(got.path, strings.Repeat("ab", 32)) {
				t.Error("test broadcast to another controller")
			}
		case <-time.After(3 * time.Second):
			t.Error("delivery missing")
			cancel()
			<-done
			return
		}
	}
	cancel()
	<-done
	if len(deliveries) != 0 {
		t.Fatal("duplicate or resolved notification delivered")
	}
}
