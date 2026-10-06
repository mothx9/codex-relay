package codex

import (
	"context"
	"encoding/json"
	"github.com/gorilla/websocket"
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
	raw, _ := json.Marshal(view)
	if strings.Contains(string(raw), "PRIVATE_") {
		t.Fatal("account authority data forwarded")
	}
}
