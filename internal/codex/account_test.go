package codex

import (
	"context"
	"encoding/json"
	"github.com/gorilla/websocket"
	"github.com/mothx9/codex-relay/internal/protocol"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestAccountViewExcludesAuthenticationAndRouting(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := (&websocket.Upgrader{}).Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer conn.Close()
		for {
			var msg rpcMessage
			if conn.ReadJSON(&msg) != nil {
				return
			}
			if msg.Method == "initialized" {
				continue
			}
			result := any(map[string]any{})
			if msg.Method == "account/read" {
				var params map[string]bool
				_ = json.Unmarshal(msg.Params, &params)
				if params["refreshToken"] {
					t.Error("account observation refreshes auth")
				}
				result = map[string]any{"account": map[string]string{"type": "chatgpt", "email": "fixture@example.invalid", "planType": "plus"}, "workspaceRouting": map[string]string{"chatgptAccountId": "PRIVATE_ROUTING_CANARY"}, "accessToken": "PRIVATE_AUTH_CANARY"}
			}
			if msg.Method == "account/rateLimits/read" {
				result = map[string]any{"accountId": "account-fixture", "ordinaryUsageAllowed": false, "rateLimits": map[string]any{"primary": map[string]any{"usedPercent": 61, "windowDurationMins": 300}}, "rateLimitsByLimitId": map[string]any{"codex": map[string]any{"limitId": "codex", "limitName": "Codex", "primary": map[string]any{"usedPercent": 61}}}, "rateLimitResetCredits": map[string]any{"availableCount": 2}, "accessToken": "PRIVATE_QUOTA_CANARY"}
			}
			if conn.WriteJSON(map[string]any{"id": msg.ID, "result": result}) != nil {
				return
			}
		}
	}))
	defer server.Close()
	adapter, err := Open(context.Background(), Config{Endpoint: "ws" + strings.TrimPrefix(server.URL, "http")})
	if err != nil {
		t.Fatal(err)
	}
	defer adapter.Close()
	view := adapter.Account(context.Background())
	if view == nil || view.Kind != "chatgpt" || view.Email != "fixture@example.invalid" {
		t.Fatal("account metadata missing")
	}
	if view.ID != "account-fixture" || view.OrdinaryUsageAllowed == nil || *view.OrdinaryUsageAllowed || view.ResetCredits.Available != 2 || len(view.Buckets) != 1 {
		t.Fatal("supported usage metadata missing")
	}
	raw, _ := json.Marshal(view)
	if strings.Contains(string(raw), "PRIVATE_") {
		t.Fatal("account authority data forwarded")
	}
}

func TestAccountEventsAllowlistAndSparseMerge(t *testing.T) {
	a := &Adapter{cfg: Config{MachineID: "m"}, events: make(chan protocol.Event, 8), done: make(chan struct{}), sessions: map[string]protocol.Session{}}
	a.handle(rpcMessage{Method: "account/updated", Params: json.RawMessage(`{"authMode":"chatgpt","planType":"pro","accessToken":"SECRET","refreshToken":"SECRET"}`)})
	a.handle(rpcMessage{Method: "account/rateLimits/updated", Params: json.RawMessage(`{"rateLimits":{"primary":{"usedPercent":10},"credits":{"hasCredits":true,"unlimited":false,"balance":"12"},"token":"SECRET"}}`)})
	a.handle(rpcMessage{Method: "account/rateLimits/updated", Params: json.RawMessage(`{"rateLimits":{"secondary":{"usedPercent":20}}}`)})
	var last protocol.Event
	for i := 0; i < 3; i++ {
		last = <-a.events
	}
	b, _ := json.Marshal(last)
	if strings.Contains(string(b), "SECRET") || last.Account.Plan != "pro" || last.Account.Limits.Primary.UsedPercent != 10 || last.Account.Limits.Secondary.UsedPercent != 20 || last.Account.Source == "" || last.Account.ObservedAt.IsZero() {
		t.Fatal("account update lost metadata or exposed secret", string(b))
	}
	a.handle(rpcMessage{Method: "account/updated", Params: json.RawMessage(`{"authMode":null,"planType":null}`)})
	if (<-a.events).Account.Limits != nil {
		t.Fatal("logout retained old account quotas")
	}
}
func TestTokenUsageIsAccountingOnly(t *testing.T) {
	a := &Adapter{cfg: Config{MachineID: "m"}, events: make(chan protocol.Event, 8), done: make(chan struct{}), sessions: map[string]protocol.Session{"t": {ID: "m~t", ThreadID: "t"}}}
	a.handle(rpcMessage{Method: "thread/tokenUsage/updated", Params: json.RawMessage(`{"threadId":"t","tokenUsage":{"total":{"totalTokens":100,"inputTokens":90,"outputTokens":10,"text":"PRIVATE"},"last":{"totalTokens":30}}}`)})
	ev := <-a.events
	b, _ := json.Marshal(ev)
	if strings.Contains(string(b), "PRIVATE") || ev.Session.TokenUsage.Total.Total != 100 {
		t.Fatal("unsafe or missing accounting")
	}
}

func TestAccountMultiBucketSparseUpdatePreservesOtherWindows(t *testing.T) {
	a := &Adapter{cfg: Config{MachineID: "m"}, events: make(chan protocol.Event, 8), done: make(chan struct{}), sessions: map[string]protocol.Session{}}
	for _, raw := range []string{`{"rateLimits":{"limitId":"codex","primary":{"usedPercent":10}}}`, `{"rateLimits":{"limitId":"fast","primary":{"usedPercent":20}}}`, `{"rateLimits":{"limitId":"codex","secondary":{"usedPercent":30}}}`} {
		a.handle(rpcMessage{Method: "account/rateLimits/updated", Params: json.RawMessage(raw)})
	}
	if a.account.Buckets["codex"].Primary.UsedPercent != 10 || a.account.Buckets["codex"].Secondary.UsedPercent != 30 || a.account.Buckets["fast"].Primary.UsedPercent != 20 {
		t.Fatal("bucket updates contaminated or lost prior windows")
	}
}
