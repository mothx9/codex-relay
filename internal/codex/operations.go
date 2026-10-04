package codex

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/mothx9/codex-relay/internal/protocol"
	"sort"
	"time"
)

func (a *Adapter) Snapshot(ctx context.Context) ([]protocol.Session, []protocol.PendingRequest, error) {
	var list struct {
		Data []thread `json:"data"`
	}
	raw, e := a.rpc(ctx, "thread/list", map[string]any{"limit": protocol.MaxSessions, "sortKey": "updated_at", "sourceKinds": []string{"cli", "vscode", "appServer", "exec"}, "useStateDbOnly": true})
	if e != nil {
		return nil, nil, e
	}
	if e = decode(raw, &list); e != nil {
		return nil, nil, e
	}
	var loaded struct {
		Data []string `json:"data"`
	}
	raw, e = a.rpc(ctx, "thread/loaded/list", map[string]any{"limit": protocol.MaxSessions})
	if e != nil {
		return nil, nil, e
	}
	if e = decode(raw, &loaded); e != nil {
		return nil, nil, e
	}
	threads := map[string]thread{}
	for _, t := range list.Data {
		threads[t.ID] = t
	}
	for _, id := range loaded.Data {
		a.mu.Lock()
		sub := a.subscribed[id]
		a.mu.Unlock()
		if !a.cfg.Private || sub {
			s, err := a.attach(ctx, id)
			if err != nil {
				continue
			}
			a.mu.Lock()
			a.sessions[id] = s
			a.mu.Unlock()
		} else {
			var r struct {
				Thread thread `json:"thread"`
			}
			raw, err := a.rpc(ctx, "thread/read", map[string]any{"threadId": id})
			if err == nil && decode(raw, &r) == nil {
				threads[id] = r.Thread
			}
		}
	}
	a.mu.Lock()
	for id, t := range threads {
		if !a.subscribed[id] {
			a.sessions[id] = a.session(t, false)
		}
	}
	// Keep bounded metadata. Live subscribed threads take precedence over old history.
	out := make([]protocol.Session, 0, len(a.sessions))
	for _, s := range a.sessions {
		out = append(out, s)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].ReadOnly != out[j].ReadOnly {
			return !out[i].ReadOnly
		}
		return out[i].UpdatedAt.After(out[j].UpdatedAt)
	})
	if len(out) > protocol.MaxSessions {
		for _, s := range out[protocol.MaxSessions:] {
			delete(a.sessions, s.ThreadID)
		}
		out = out[:protocol.MaxSessions]
	}
	requests := make([]protocol.PendingRequest, 0, len(a.requests))
	for _, p := range a.requests {
		requests = append(requests, p.Request)
	}
	a.snapshotSequence = a.sequence
	a.mu.Unlock()
	return out, requests, nil
}
func (a *Adapter) attach(ctx context.Context, id string) (protocol.Session, error) {
	a.mu.Lock()
	sub := a.subscribed[id]
	a.mu.Unlock()
	var r struct {
		Thread thread `json:"thread"`
	}
	method := "thread/read"
	params := map[string]any{"threadId": id, "includeTurns": false}
	if !sub {
		method = "thread/resume"
		params = map[string]any{"threadId": id, "excludeTurns": true}
	}
	raw, e := a.rpc(ctx, method, params)
	if e != nil {
		return protocol.Session{}, e
	}
	if e = decode(raw, &r); e != nil {
		return protocol.Session{}, e
	}
	a.mu.Lock()
	a.subscribed[id] = true
	s := a.session(r.Thread, true)
	a.mu.Unlock()
	var turns struct {
		Data []turn `json:"data"`
	}
	raw, e = a.rpc(ctx, "thread/turns/list", map[string]any{"threadId": id, "limit": 1, "sortDirection": "desc", "itemsView": "notLoaded"})
	if e == nil && decode(raw, &turns) == nil && len(turns.Data) > 0 && turns.Data[0].Status == "inProgress" {
		s.TurnID = turns.Data[0].ID
		if turns.Data[0].StartedAt != nil {
			s.TurnStarted = time.Unix(*turns.Data[0].StartedAt, 0).UTC()
		}
	}
	a.mu.Lock()
	a.sessions[id] = s
	a.mu.Unlock()
	return s, nil
}
func (a *Adapter) history(ctx context.Context, id string) ([]protocol.Activity, error) {
	var r struct {
		Data []struct {
			Item        json.RawMessage `json:"item"`
			TurnID      string          `json:"turnId"`
			StartedAtMs *int64          `json:"startedAtMs"`
		} `json:"data"`
	}
	raw, e := a.rpc(ctx, "thread/items/list", map[string]any{"threadId": id, "limit": 40, "sortDirection": "desc"})
	if e != nil {
		return nil, e
	}
	if e = decode(raw, &r); e != nil {
		return nil, e
	}
	out := make([]protocol.Activity, 0, 40)
	for i := len(r.Data) - 1; i >= 0; i-- {
		entry := r.Data[i]
		v := activity(entry.Item)
		if v.Text == "" {
			continue
		}
		v.TurnID = entry.TurnID
		if entry.StartedAtMs != nil {
			v.Timestamp = time.UnixMilli(*entry.StartedAtMs).UTC()
		}
		out = append(out, v)
	}
	return out, nil
}
func (a *Adapter) Execute(ctx context.Context, c protocol.Command) protocol.Result {
	result := protocol.Result{ID: c.ID, SessionID: c.SessionID}
	var err error
	a.mu.Lock()
	s, exists := a.sessions[c.ThreadID]
	a.mu.Unlock()
	if !exists {
		result.Error = "Session is not in the current Codex snapshot"
		return result
	}
	switch c.Kind {
	case "history":
		result.History, err = a.history(ctx, c.ThreadID)
	case "attach":
		var attached protocol.Session
		attached, err = a.attach(ctx, c.ThreadID)
		if err == nil {
			a.emit(protocol.Event{Kind: "session", SessionID: attached.ID, Session: &attached})
		}
	case "start", "steer", "queue", "interrupt":
		if s.ReadOnly {
			err = errors.New("Read-only session: attach it explicitly first")
			break
		}
		input := []map[string]any{{"type": "text", "text": c.Text, "text_elements": []any{}}}
		switch c.Kind {
		case "start":
			if s.Status == protocol.Working || s.Status == protocol.NeedsYou {
				err = errors.New("Turn is already working or waiting for input")
				break
			}
			_, err = a.rpc(ctx, "turn/start", map[string]any{"threadId": c.ThreadID, "input": input, "clientUserMessageId": c.ID})
		case "steer":
			if s.TurnID == "" || s.TurnID != c.TurnID {
				err = errors.New("Active turn changed: refresh before steering")
				break
			}
			_, err = a.rpc(ctx, "turn/steer", map[string]any{"threadId": c.ThreadID, "input": input, "expectedTurnId": c.TurnID, "clientUserMessageId": c.ID})
		case "queue":
			_, err = a.rpc(ctx, "thread/queue/add", map[string]any{"threadId": c.ThreadID, "input": input, "clientUserMessageId": c.ID})
		case "interrupt":
			if s.TurnID == "" || s.TurnID != c.TurnID {
				err = errors.New("Active turn changed")
				break
			}
			_, err = a.rpc(ctx, "turn/interrupt", map[string]any{"threadId": c.ThreadID, "turnId": c.TurnID})
		}
	case "respond":
		err = a.respond(c)
	default:
		err = fmt.Errorf("Unknown Relay command %q", c.Kind)
	}
	result.OK = err == nil
	if err != nil {
		result.Error = err.Error()
	}
	return result
}
func (a *Adapter) respond(c protocol.Command) error {
	a.mu.Lock()
	p, ok := a.requests[c.RequestID]
	if !ok || p.Sent || p.Request.ThreadID != c.ThreadID || time.Now().After(p.Request.ExpiresAt) {
		a.mu.Unlock()
		return errors.New("Request expired, resolved, or already answered")
	}
	if c.Decision != "approve" && c.Decision != "reject" {
		a.mu.Unlock()
		return errors.New("Invalid decision")
	}
	if c.Decision == "approve" && !p.Request.CanApprove {
		a.mu.Unlock()
		return errors.New("Approval unsupported for this request")
	}
	var result any
	switch p.Request.Kind {
	case "command_approval", "file_approval":
		decision := "decline"
		if c.Decision == "approve" {
			decision = "accept"
		}
		result = map[string]string{"decision": decision}
	case "permissions_approval":
		var params struct {
			Permissions json.RawMessage `json:"permissions"`
		}
		_ = json.Unmarshal(p.Params, &params)
		permissions := json.RawMessage(`{}`)
		if c.Decision == "approve" {
			permissions = params.Permissions
		}
		result = map[string]any{"permissions": permissions, "scope": "turn"}
	case "user_input":
		if c.Decision == "reject" {
			result = map[string]any{"answers": map[string]any{}}
		} else {
			answers := map[string]any{}
			for _, q := range p.Request.Questions {
				v, found := c.Answers[q.ID]
				if !found || len(v) != 1 || len(v[0]) > protocol.MaxText {
					a.mu.Unlock()
					return errors.New("Answer every question with one bounded answer")
				}
				answers[q.ID] = map[string]any{"answers": v}
			}
			result = map[string]any{"answers": answers}
		}
	case "mcp_elicitation":
		action := "decline"
		if c.Decision == "approve" {
			action = "accept"
		}
		result = map[string]any{"action": action, "content": json.RawMessage(`null`)}
		if action == "accept" {
			if !json.Valid(c.Content) {
				a.mu.Unlock()
				return errors.New("Structured MCP content required")
			}
			result = map[string]any{"action": action, "content": c.Content}
		}
	default:
		a.mu.Unlock()
		return errors.New("Unsupported request: resolve in local Codex")
	}
	p.Sent = true
	a.requests[c.RequestID] = p
	a.mu.Unlock()
	if err := a.write(map[string]any{"id": p.RawID, "result": result}); err != nil {
		return err
	}
	// Resolution is confirmed by serverRequest/resolved, never assumed on write.
	return nil
}
