package codex

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"github.com/gorilla/websocket"
	"github.com/mothx9/codex-relay/internal/protocol"
)

func TestColdCataloguePagesDoNotReplaceLiveOrSubscribe(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		c, err := (&websocket.Upgrader{}).Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer c.Close()
		for {
			var m rpcMessage
			if c.ReadJSON(&m) != nil {
				return
			}
			if m.Method == "initialized" {
				continue
			}
			var p map[string]any
			_ = json.Unmarshal(m.Params, &p)
			result := any(map[string]any{})
			switch m.Method {
			case "thread/list":
				start, _ := strconv.Atoi(fmt.Sprint(p["cursor"]))
				page := []any{}
				for i := start; i < start+100 && i < 600; i++ {
					page = append(page, map[string]any{"id": fmt.Sprintf("cold-%d", i), "status": map[string]any{"type": "notLoaded"}})
				}
				next := ""
				if start+100 < 600 {
					next = strconv.Itoa(start + 100)
				}
				result = map[string]any{"data": page, "nextCursor": next}
			case "thread/read":
				result = map[string]any{"thread": map[string]any{"id": p["threadId"], "status": map[string]any{"type": "notLoaded"}}}
			case "thread/items/list", "thread/queue/list":
				result = map[string]any{"data": []any{}}
			case "thread/resume":
				t.Error("discovery resumed a thread")
			}
			if c.WriteJSON(map[string]any{"id": m.ID, "result": result}) != nil {
				return
			}
		}
	}))
	defer srv.Close()
	a, err := Open(context.Background(), Config{Endpoint: "ws" + strings.TrimPrefix(srv.URL, "http"), MachineID: "m"})
	if err != nil {
		t.Fatal(err)
	}
	defer a.Close()
	a.mu.Lock()
	a.sessions["hot"] = protocol.Session{ID: "m~hot", MachineID: "m", ThreadID: "hot", Status: protocol.NeedsYou}
	a.mu.Unlock()
	cursor := ""
	total := 0
	for {
		r := a.Execute(context.Background(), protocol.Command{ID: protocol.ID(), Kind: "catalogue", MachineID: "m", CatalogueCursor: cursor})
		if !r.OK {
			t.Fatal(r.ErrorCode)
		}
		total += len(r.Sessions)
		for _, s := range r.Sessions {
			if !s.ReadOnly || s.Capabilities.CanSend {
				t.Fatal("catalogue granted control")
			}
		}
		cursor = r.CatalogueCursor
		if cursor == "" {
			break
		}
	}
	a.mu.Lock()
	count, status, subs := len(a.sessions), a.sessions["hot"].Status, len(a.subscribed)
	a.mu.Unlock()
	if total != 600 || count != 1 || status != protocol.NeedsYou || subs != 0 {
		t.Fatalf("catalogue affected live state: total=%d live=%d status=%s subscriptions=%d", total, count, status, subs)
	}
	r := a.Execute(context.Background(), protocol.Command{ID: protocol.ID(), Kind: "history", SessionID: "m~cold-599", ThreadID: "cold-599"})
	if !r.OK {
		t.Fatal("cold history unavailable", r.ErrorCode)
	}
	a.mu.Lock()
	cold := a.sessions["cold-599"]
	subs = len(a.subscribed)
	a.mu.Unlock()
	if !cold.ReadOnly || subs != 0 {
		t.Fatal("cold history implicitly attached")
	}
	denied := a.Execute(context.Background(), protocol.Command{ID: protocol.ID(), Kind: protocol.NewTurn, ThreadID: "unknown", Text: "no"})
	if denied.OK {
		t.Fatal("unknown thread controlled")
	}
}
