// Package push delivers bounded, privacy-conscious Web Push. Agents know nothing about it.
package push

import (
	"context"
	"crypto/elliptic"
	"encoding/base64"
	"encoding/json"
	"errors"
	webpush "github.com/SherClockHolmes/webpush-go"
	"github.com/mothx9/codex-relay/internal/protocol"
	"github.com/mothx9/codex-relay/internal/store"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type Keys struct {
	Public  string `json:"public"`
	Private string `json:"private"`
}

func Generate() (Keys, error) { priv, pub, e := webpush.GenerateVAPIDKeys(); return Keys{pub, priv}, e }

type Notice struct {
	Key, Kind, SessionID, MachineID, Machine, Project, Title, RequestID, DeviceID string
	Badge                                                                         int
}
type Worker struct {
	store   *store.Store
	keys    Keys
	subject string
	queue   chan Notice
	client  *http.Client
	APNS    *APNS
}

func New(s *store.Store, k Keys, subject string) *Worker {
	return &Worker{store: s, keys: k, subject: subject, queue: make(chan Notice, 128), client: &http.Client{Timeout: 10 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return errors.New("push redirects disabled") }}}
}
func (w *Worker) PublicKey() string { return w.keys.Public }
func (w *Worker) Enqueue(n Notice) {
	if w.keys.Public == "" && w.APNS == nil {
		return
	}
	select {
	case w.queue <- n:
	default:
		slog.Warn("push queue full; notification dropped")
	}
}
func Validate(raw []byte) (webpush.Subscription, error) {
	var v webpush.Subscription
	if e := json.Unmarshal(raw, &v); e != nil {
		return v, e
	}
	u, e := url.Parse(v.Endpoint)
	if e != nil || u.Scheme != "https" || u.User != nil || u.Fragment != "" || (u.Port() != "" && u.Port() != "443") {
		return v, errors.New("invalid push endpoint")
	}
	host := u.Hostname()
	if strings.HasSuffix(host, ".push.apple.com") {
		host = "web.push.apple.com"
	}
	switch host {
	case "web.push.apple.com", "fcm.googleapis.com", "updates.push.services.mozilla.com":
	default:
		return v, errors.New("unsupported push service; allowlist covers Safari, Chrome, Firefox")
	}
	for key, n := range map[string]int{v.Keys.P256dh: 65, v.Keys.Auth: 16} {
		b, e := base64.RawURLEncoding.DecodeString(strings.TrimRight(key, "="))
		if e != nil || len(b) != n {
			return v, errors.New("invalid push encryption key")
		}
	}
	dh, _ := base64.RawURLEncoding.DecodeString(strings.TrimRight(v.Keys.P256dh, "="))
	if x, _ := elliptic.Unmarshal(elliptic.P256(), dh); x == nil {
		return v, errors.New("invalid P-256 encryption key")
	}
	return v, nil
}
func (w *Worker) Run(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case n := <-w.queue:
			// Compute the badge at delivery time. Do not alert a request that was
			// resolved while queued; clients still rehydrate before showing a form.
			count, pending, err := w.store.NotificationState(n.RequestID)
			if err != nil || (n.RequestID != "" && !pending) {
				continue
			}
			n.Badge = count
			subscriptions, e := w.store.Subscriptions()
			native, nativeErr := w.store.APNSSubscriptions()
			if e != nil || nativeErr != nil || (len(subscriptions) == 0 && (w.APNS == nil || len(native) == 0)) {
				continue
			}
			once, e := w.store.NotifyOnce(n.Key)
			if e != nil || !once {
				continue
			}
			if w.APNS != nil {
				for _, sub := range native {
					if n.DeviceID != "" && n.DeviceID != sub.DeviceID {
						continue
					}
					if ctx.Err() != nil {
						return
					}
					gone, err := w.APNS.Send(ctx, n, sub)
					if gone {
						_ = w.store.UnsubscribeAPNS(sub.DeviceID)
					}
					if err != nil {
						slog.Warn("native push delivery failed")
					}
				}
			}
			if w.keys.Public == "" || n.DeviceID != "" {
				continue
			}
			for _, sub := range subscriptions {
				if ctx.Err() != nil {
					return
				}
				var v webpush.Subscription
				if json.Unmarshal(sub.JSON, &v) != nil {
					continue
				}
				payload, _ := json.Marshal(Payload(n, sub.Privacy))
				resp, e := webpush.SendNotificationWithContext(ctx, payload, &v, &webpush.Options{Subscriber: w.subject, VAPIDPublicKey: w.keys.Public, VAPIDPrivateKey: w.keys.Private, TTL: 300, Urgency: webpush.UrgencyHigh, HTTPClient: w.client})
				if e != nil {
					slog.Warn("push delivery failed")
					continue
				}
				_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))
				_ = resp.Body.Close()
				if resp.StatusCode == 404 || resp.StatusCode == 410 {
					_ = w.store.Unsubscribe(sub.Endpoint)
				} else if resp.StatusCode >= 400 {
					slog.Warn("push service rejected delivery", "status", resp.StatusCode)
				}
			}
		}
	}
}
func Payload(n Notice, privacy bool) map[string]string {
	title := "Codex Relay"
	if !privacy {
		title = protocol.Clip(n.Machine+" · "+n.Project, 100)
	}
	body := "Codex needs your input."
	if privacy {
		body = "A session needs your input."
	}
	switch n.Kind {
	case "turn_completed":
		body = "Codex completed a turn."
	case "failed":
		body = "A Codex session needs attention."
	case "machine_offline":
		body = "A Relay machine is offline."
	case "test":
		body = "Relay notification test."
	}
	target := "/"
	if n.SessionID != "" {
		target = "/session/" + url.PathEscape(n.SessionID)
	}
	return map[string]string{"title": title, "body": body, "url": target, "tag": "relay-" + n.SessionID, "kind": n.Kind}
}
