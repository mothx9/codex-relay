package codex

import (
	"context"
	"encoding/json"
	"errors"
	"github.com/mothx9/codex-relay/internal/protocol"
)

func (a *Adapter) disableQueue() {
	a.mu.Lock()
	a.queue = false
	var sessions []protocol.Session
	for id, s := range a.sessions {
		s = a.capabilities(s)
		a.sessions[id] = s
		sessions = append(sessions, s)
	}
	a.mu.Unlock()
	for _, s := range sessions {
		a.emit(protocol.Event{Kind: "session", SessionID: s.ID, Session: &s})
	}
}

func (a *Adapter) nativeQueue(ctx context.Context, threadID string) ([]protocol.FollowUp, error) {
	a.mu.Lock()
	supported := a.queue
	a.mu.Unlock()
	if !supported {
		return nil, errors.New("queue unavailable")
	}
	raw, err := a.rpc(ctx, "thread/queue/list", map[string]any{"threadId": threadID, "limit": 50})
	if err != nil {
		var rpc *rpcError
		if errors.As(err, &rpc) && rpc.Code == -32601 {
			a.disableQueue()
		}
		return nil, err
	}
	var result struct {
		Data []struct {
			ID       string `json:"id"`
			ClientID string `json:"clientUserMessageId"`
			Input    []struct {
				Type string `json:"type"`
				Text string `json:"text"`
			} `json:"input"`
		} `json:"data"`
	}
	if err := json.Unmarshal(raw, &result); err != nil {
		return nil, err
	}
	out := make([]protocol.FollowUp, 0, 50)
	bytes := 0
	for _, q := range result.Data {
		text := ""
		for _, input := range q.Input {
			if input.Type == "text" {
				text += input.Text
			}
		}
		text = protocol.Clip(text, protocol.MaxText)
		if len(out) == 50 || bytes+len(text) > 128<<10 {
			break
		}
		bytes += len(text)
		out = append(out, protocol.FollowUp{ID: q.ID, ClientID: q.ClientID, Text: text})
	}
	return out, nil
}

// Queue notifications contain only threadId. One bounded worker reads the official
// queue in response, never from the RPC reader itself and never by rapid polling.
func (a *Adapter) queueLoop() {
	for {
		select {
		case <-a.done:
			return
		case id := <-a.queueSignals:
			queue, err := a.nativeQueue(context.Background(), id)
			if err == nil {
				a.emit(protocol.Event{Kind: "follow_up_queue", SessionID: protocol.SessionID(a.cfg.MachineID, id), FollowUps: queue, RawEvent: "thread/queue/changed"})
			}
		}
	}
}
