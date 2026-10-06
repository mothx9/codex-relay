package codex

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
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
				Type     string            `json:"type"`
				Text     string            `json:"text"`
				Elements []json.RawMessage `json:"text_elements"`
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
		editable := q.ClientID != "" && len(q.Input) == 1 && q.Input[0].Type == "text" && len(q.Input[0].Elements) == 0 && len(q.Input[0].Text) <= protocol.MaxText
		out = append(out, protocol.FollowUp{ID: q.ID, ClientID: q.ClientID, Text: text, Editable: editable, Revision: fmt.Sprintf("%x", sha256.Sum256([]byte(text)))})
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

// Edit the canonical submission in place; never remove and re-add it. Validate
// identity and observed content before invoking the backend's own queue update.
func (a *Adapter) editQueue(ctx context.Context, c protocol.Command) protocol.Result {
	queue, err := a.nativeQueue(ctx, c.ThreadID)
	if err != nil {
		return protocol.Failure(c, a.errorCode(c, err))
	}
	found := false
	for _, entry := range queue {
		if entry.ID == c.QueueID && entry.ClientID == c.QueueClientID && entry.Revision == c.QueueRevision && entry.Editable {
			found = true
			break
		}
	}
	if !found {
		return protocol.Failure(c, protocol.QueueChanged)
	}
	raw, err := a.rpc(ctx, "thread/queue/update", map[string]any{"threadId": c.ThreadID, "queuedSubmissionId": c.QueueID, "input": []map[string]any{{"type": "text", "text": c.Text, "text_elements": []any{}}}})
	if err != nil {
		return protocol.Failure(c, a.errorCode(c, err))
	}
	var response struct {
		QueuedSubmission struct {
			ID       string `json:"id"`
			ClientID string `json:"clientUserMessageId"`
		} `json:"queuedSubmission"`
	}
	if json.Unmarshal(raw, &response) != nil || response.QueuedSubmission.ID != c.QueueID || response.QueuedSubmission.ClientID != c.QueueClientID {
		return protocol.Failure(c, protocol.UnknownOutcome)
	}
	queue, _ = a.nativeQueue(ctx, c.ThreadID)
	return protocol.Result{ID: c.ID, SessionID: c.SessionID, OK: true, QueueID: c.QueueID, FollowUps: queue}
}
