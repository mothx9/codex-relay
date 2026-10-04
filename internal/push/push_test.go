package push

import (
	"context"
	"crypto/elliptic"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	webpush "github.com/SherClockHolmes/webpush-go"
	"github.com/mothx9/codex-relay/internal/store"
	"io"
	"net/http"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

type captureClient struct {
	mu       sync.Mutex
	requests []*http.Request
	status   int
}

func (c *captureClient) Do(r *http.Request) (*http.Response, error) {
	c.mu.Lock()
	c.requests = append(c.requests, r)
	c.mu.Unlock()
	return &http.Response{StatusCode: c.status, Body: io.NopCloser(strings.NewReader(""))}, nil
}
func TestPushEncryptedDedupeAndExpiry(t *testing.T) {
	s, e := store.Open(filepath.Join(t.TempDir(), "db"))
	if e != nil {
		t.Fatal(e)
	}
	defer s.Close()
	_, x, y, e := elliptic.GenerateKey(elliptic.P256(), rand.Reader)
	if e != nil {
		t.Fatal(e)
	}
	sub := webpush.Subscription{Endpoint: "https://web.push.apple.com/Q/test", Keys: webpush.Keys{P256dh: base64.RawURLEncoding.EncodeToString(elliptic.Marshal(elliptic.P256(), x, y)), Auth: base64.RawURLEncoding.EncodeToString(make([]byte, 16))}}
	raw, _ := json.Marshal(sub)
	if _, e = Validate(raw); e != nil {
		t.Fatal(e)
	}
	_ = s.Subscribe(store.PushSubscription{Endpoint: sub.Endpoint, JSON: raw, Privacy: true})
	k, e := Generate()
	if e != nil {
		t.Fatal(e)
	}
	w := New(s, k, "mailto:operator@example.com")
	client := &captureClient{status: 201}
	w.client = &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) { return client.Do(r) })}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { w.Run(ctx); close(done) }()
	n := Notice{Key: "request/item", Kind: "request", SessionID: "m~t", Machine: "SPARK", Project: "YVEX"}
	w.Enqueue(n)
	w.Enqueue(n)
	end := time.Now().Add(2 * time.Second)
	for time.Now().Before(end) {
		client.mu.Lock()
		count := len(client.requests)
		client.mu.Unlock()
		if count > 0 {
			break
		}
		time.Sleep(time.Millisecond)
	}
	cancel()
	<-done
	client.mu.Lock()
	if len(client.requests) != 1 {
		t.Fatalf("duplicate push: %d", len(client.requests))
	}
	r := client.requests[0]
	client.mu.Unlock()
	body, _ := io.ReadAll(r.Body)
	if strings.Contains(string(body), "Codex") || r.Header.Get("Content-Encoding") != "aes128gcm" || !strings.HasPrefix(r.Header.Get("Authorization"), "vapid ") {
		t.Fatal("unencrypted or unsigned push")
	}
	p := Payload(n, true)
	if strings.Contains(p["title"], "SPARK") || p["url"] != "/session/m~t" {
		t.Fatal("privacy or deep link")
	}
	client.status = 410
	done = make(chan struct{})
	ctx, cancel = context.WithCancel(context.Background())
	go func() { w.Run(ctx); close(done) }()
	w.Enqueue(Notice{Key: "expired", Kind: "test"})
	end = time.Now().Add(2 * time.Second)
	for time.Now().Before(end) {
		subs, _ := s.Subscriptions()
		if len(subs) == 0 {
			break
		}
		time.Sleep(time.Millisecond)
	}
	cancel()
	<-done
	subs, _ := s.Subscriptions()
	if len(subs) != 0 {
		t.Fatal("expired subscription retained")
	}
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func TestRejectPushSSRF(t *testing.T) {
	for _, endpoint := range []string{"http://web.push.apple.com/x", "https://127.0.0.1/x", "https://web.push.apple.com.evil/x", "https://web.push.apple.com:9443/x"} {
		raw, _ := json.Marshal(webpush.Subscription{Endpoint: endpoint})
		if _, e := Validate(raw); e == nil {
			t.Fatal(endpoint)
		}
	}
}
