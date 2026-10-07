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

type queuedSubmission struct {
	ID       string            `json:"id"`
	ClientID string            `json:"clientUserMessageId"`
	Input    []json.RawMessage `json:"input"`
}

func queueRevision(input []json.RawMessage) string {
	// Normalize JSON formatting and key order before comparing the full input,
	// including images and text elements, rather than only its text preview.
	var normalized any
	raw, _ := json.Marshal(input)
	_ = json.Unmarshal(raw, &normalized)
	raw, _ = json.Marshal(normalized)
	return fmt.Sprintf("%x", sha256.Sum256(raw))
}

func (a *Adapter) readQueue(ctx context.Context, threadID string) ([]queuedSubmission, error) {
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
		Data []queuedSubmission `json:"data"`
	}
	if err := json.Unmarshal(raw, &result); err != nil {
		return nil, err
	}
	return result.Data, nil
}

func (a *Adapter) nativeQueue(ctx context.Context, threadID string) ([]protocol.FollowUp, error) {
	entries, err := a.readQueue(ctx, threadID)
	if err != nil {
		return nil, err
	}
	out := make([]protocol.FollowUp, 0, 50)
	bytes := 0
	for _, q := range entries {
		text := ""
		imageCount := 0
		editable := q.ClientID != "" && len(q.Input) == 1
		for _, raw := range q.Input {
			var input struct {
				Type     string            `json:"type"`
				Text     string            `json:"text"`
				Elements []json.RawMessage `json:"text_elements"`
			}
			if json.Unmarshal(raw, &input) != nil {
				editable = false
				continue
			}
			editable = editable && input.Type == "text" && len(input.Elements) == 0 && len(input.Text) <= protocol.MaxText
			if input.Type == "image" || input.Type == "localImage" {
				imageCount++
			}
			if input.Type == "text" {
				text += input.Text
			}
		}
		text = protocol.Clip(text, protocol.MaxText)
		if len(out) == 50 || bytes+len(text) > 128<<10 {
			break
		}
		bytes += len(text)
		out = append(out, protocol.FollowUp{ImageCount: imageCount, ID: q.ID, ClientID: q.ClientID, Text: text, Editable: editable, Revision: queueRevision(q.Input)})
	}
	return out, nil
}

// Promote exactly one canonical queued item. Deletion must be acknowledged before
// steering; reuse its original input and client ID. Never re-add or auto-retry.
// A turn change after removal returns a recoverable failure to the controller.
func (a *Adapter) steerQueue(ctx context.Context, c protocol.Command) protocol.Result {
	entries, err := a.readQueue(ctx, c.ThreadID)
	if err != nil {
		return protocol.Failure(c, a.errorCode(c, err))
	}
	var selected *queuedSubmission
	for i := range entries {
		q := &entries[i]
		if q.ID == c.QueueID && q.ClientID == c.QueueClientID && q.ClientID != "" && queueRevision(q.Input) == c.QueueRevision {
			selected = q
			break
		}
	}
	if selected == nil {
		return protocol.Failure(c, protocol.QueueChanged)
	}
	// Recheck metadata after the read, before touching the native queue.
	a.mu.Lock()
	s := a.sessions[c.ThreadID]
	a.mu.Unlock()
	if code := protocol.CheckControl(s, c); code != "" {
		return protocol.Failure(c, code)
	}
	raw, err := a.rpc(ctx, "thread/queue/delete", map[string]any{"threadId": c.ThreadID, "queuedSubmissionId": c.QueueID})
	if err != nil {
		return protocol.Failure(c, a.errorCode(c, err))
	}
	var deletion struct {
		Deleted bool `json:"deleted"`
	}
	if json.Unmarshal(raw, &deletion) != nil {
		return protocol.Failure(c, protocol.UnknownOutcome)
	}
	if !deletion.Deleted {
		return protocol.Failure(c, protocol.QueueChanged)
	}
	_, err = a.rpc(ctx, "turn/steer", map[string]any{"threadId": c.ThreadID, "expectedTurnId": c.TurnID, "clientUserMessageId": selected.ClientID, "input": selected.Input})
	result := protocol.Result{ID: c.ID, SessionID: c.SessionID, OK: true, QueueID: c.QueueID, QueueRemoved: true}
	if err != nil {
		steerCommand := c
		steerCommand.Kind = protocol.Steer
		result = protocol.Failure(c, a.errorCode(steerCommand, err))
		result.QueueRemoved = true
	}
	result.FollowUps, _ = a.nativeQueue(ctx, c.ThreadID)
	return result
}

// Queue notifications contain only threadId. One bounded worker reads the official
// queue in response, never from the RPC reader itself and never by rapid polling.
func (a *Adapter) queueLoop() {
	for {
		select {
		case <-a.done:
			return
		case id := <-a.queueSignals:
			a.mu.Lock()
			delete(a.queuePending, id)
			a.mu.Unlock()
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
