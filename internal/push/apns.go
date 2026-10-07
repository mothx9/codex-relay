package push

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"github.com/mothx9/codex-relay/internal/store"
	"io"
	"net/http"
	"regexp"
	"sync"
	"time"
)

// APNSConfig references an owner-supplied Apple key; no Apple credential is shipped.
type APNSConfig struct {
	TeamID  string `json:"team_id"`
	KeyID   string `json:"key_id"`
	Topic   string `json:"topic"`
	KeyFile string `json:"key_file"`
}
type APNS struct {
	config APNSConfig
	key    *ecdsa.PrivateKey
	client *http.Client
	mu     sync.Mutex
	jwt    string
	issued time.Time
}

func NewAPNS(config APNSConfig, keyPEM []byte) (*APNS, error) {
	id := regexp.MustCompile(`^[A-Z0-9]{10}$`)
	if !id.MatchString(config.TeamID) || !id.MatchString(config.KeyID) || !regexp.MustCompile(`^[A-Za-z0-9.-]{3,200}$`).MatchString(config.Topic) {
		return nil, errors.New("invalid APNs identifiers")
	}
	block, _ := pem.Decode(keyPEM)
	if block == nil {
		return nil, errors.New("APNs key must be PKCS8 PEM")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, errors.New("invalid APNs private key")
	}
	key, ok := parsed.(*ecdsa.PrivateKey)
	if !ok || key.Curve != elliptic.P256() {
		return nil, errors.New("APNs requires an ES256 key")
	}
	return &APNS{config: config, key: key, client: &http.Client{Timeout: 10 * time.Second, Transport: &http.Transport{ForceAttemptHTTP2: true}, CheckRedirect: func(*http.Request, []*http.Request) error { return errors.New("APNs redirects disabled") }}}, nil
}
func (a *APNS) bearer(now time.Time) (string, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.jwt != "" && now.Sub(a.issued) < 50*time.Minute {
		return a.jwt, nil
	}
	enc := base64.RawURLEncoding.EncodeToString
	header, _ := json.Marshal(map[string]string{"alg": "ES256", "kid": a.config.KeyID})
	claims, _ := json.Marshal(map[string]any{"iss": a.config.TeamID, "iat": now.Unix()})
	unsigned := enc(header) + "." + enc(claims)
	digest := sha256.Sum256([]byte(unsigned))
	r, s, err := ecdsa.Sign(rand.Reader, a.key, digest[:])
	if err != nil {
		return "", err
	}
	signature := make([]byte, 64)
	r.FillBytes(signature[:32])
	s.FillBytes(signature[32:])
	a.jwt = unsigned + "." + enc(signature)
	a.issued = now
	return a.jwt, nil
}
func (a *APNS) Send(ctx context.Context, n Notice, sub store.APNSSubscription) (bool, error) {
	bearer, err := a.bearer(time.Now())
	if err != nil {
		return false, err
	}
	host := "https://api.push.apple.com"
	if sub.Environment == "sandbox" {
		host = "https://api.sandbox.push.apple.com"
	}
	view := Payload(n, sub.Privacy)
	payload, _ := json.Marshal(map[string]any{"aps": map[string]any{"alert": map[string]string{"title": view["title"], "subtitle": view["subtitle"], "body": view["body"]}, "sound": "default", "badge": n.Badge, "thread-id": n.SessionID}, "session_id": n.SessionID, "machine_id": n.MachineID, "kind": n.Kind, "request_id": n.RequestID, "notice_key": n.Key, "turn_id": n.TurnID})
	req, err := http.NewRequestWithContext(ctx, "POST", host+"/3/device/"+sub.Token, bytes.NewReader(payload))
	if err != nil {
		return false, err
	}
	req.Header.Set("authorization", "bearer "+bearer)
	req.Header.Set("apns-topic", a.config.Topic)
	req.Header.Set("apns-push-type", "alert")
	req.Header.Set("apns-priority", "10")
	req.Header.Set("apns-expiration", fmt.Sprint(time.Now().Add(5*time.Minute).Unix()))
	if n.Kind == "live_question" {
		req.Header.Set("apns-expiration", "0")
	}
	key := n.SessionID
	if key == "" {
		key = n.MachineID
		if key == "" {
			key = n.Machine
		}
	}
	hash := sha256.Sum256([]byte(key))
	req.Header.Set("apns-collapse-id", hex.EncodeToString(hash[:]))
	req.Header.Set("Content-Type", "application/json")
	resp, err := a.client.Do(req)
	if err != nil {
		return false, errors.New("APNs transport failed")
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	var result struct {
		Reason string `json:"reason"`
	}
	_ = json.Unmarshal(body, &result)
	if resp.StatusCode == 410 || (resp.StatusCode == 400 && result.Reason == "BadDeviceToken") {
		return true, nil
	}
	if resp.StatusCode != 200 {
		return false, fmt.Errorf("APNs rejected notification (HTTP %d)", resp.StatusCode)
	}
	return false, nil
}
