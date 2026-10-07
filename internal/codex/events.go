package codex

import (
	"encoding/json"
	"fmt"
	"github.com/mothx9/codex-relay/internal/protocol"
	"strings"
	"time"
	"unicode/utf8"
)

func activity(raw json.RawMessage) protocol.Activity {
	var item struct {
		Result *struct {
			Content []struct {
				Type string `json:"type"`
				Text string `json:"text"`
			} `json:"content"`
		} `json:"result"`
		Error *struct {
			Message string `json:"message"`
		} `json:"error"`
		Status     string                   `json:"status"`
		ExitCode   *int                     `json:"exitCode"`
		DurationMS *int64                   `json:"durationMs"`
		Tool       string                   `json:"tool"`
		Server     string                   `json:"server"`
		ID         string                   `json:"id"`
		ClientID   string                   `json:"clientId"`
		Type       string                   `json:"type"`
		Text       string                   `json:"text"`
		Command    string                   `json:"command"`
		Output     string                   `json:"aggregatedOutput"`
		Questions  []protocol.AsyncQuestion `json:"questions"`
		Changes    []struct {
			Path string          `json:"path"`
			Kind json.RawMessage `json:"kind"`
			Diff string          `json:"diff"`
		} `json:"changes"`
		Content []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"content"`
	}
	_ = json.Unmarshal(raw, &item)
	v := protocol.Activity{ID: item.ID, ClientID: item.ClientID, Kind: item.Type, Timestamp: time.Now().UTC(), ExitCode: item.ExitCode, DurationMS: item.DurationMS}
	switch item.Status {
	case "inProgress":
		v.State = "running"
	case "completed", "failed", "declined":
		v.State = item.Status
	}
	switch item.Type {
	case "contextCompaction":
		v.Kind = "context_compaction"
		v.Text = "Context compacted"
	case "agentMessage":
		v.Text = item.Text
		v.Questions, v.Truncated = clipAsyncQuestions(item.Questions)
		if strings.TrimSpace(v.Text) == "" && len(v.Questions) > 0 {
			var titles []string
			for _, q := range v.Questions {
				titles = append(titles, q.Title)
			}
			v.Text = strings.Join(titles, "\n\n")
		}
	case "userMessage":
		for _, c := range item.Content {
			if c.Type == "text" {
				v.Text += c.Text
			}
		}
	case "commandExecution":
		v.Command = protocol.Clip(item.Command, 1024)
		v.Truncated = len(v.Command) < len(item.Command)
		v.Text = v.Command
		if item.Output != "" {
			v.Text += "\n" + item.Output
		}
	case "fileChange":
		v.Text = "File changes"
		budget := protocol.MaxText / 2
		for _, change := range item.Changes {
			if len(v.Files) >= 16 || budget <= 0 {
				v.Truncated = true
				break
			}
			var kind struct {
				Type     string `json:"type"`
				MovePath string `json:"move_path"`
			}
			_ = json.Unmarshal(change.Kind, &kind)
			f := protocol.FileChange{Path: protocol.Clip(change.Path, min(1024, budget)), Kind: protocol.Clip(kind.Type, 32)}
			budget -= len(f.Path) + len(f.Kind)
			if kind.MovePath != "" && budget > 0 {
				f.PreviousPath = f.Path
				f.Path = protocol.Clip(kind.MovePath, min(1024, budget))
				f.Kind = "rename"
				budget -= len(f.Path) + 6
			}
			if budget > 0 {
				f.Patch = protocol.Clip(change.Diff, budget)
				budget -= len(f.Patch)
			}
			v.Truncated = v.Truncated || len(f.Patch) < len(change.Diff)
			v.Files = append(v.Files, f)
			v.Text += "\n" + f.Path + " " + f.Kind + "\n" + f.Patch
		}
	case "mcpToolCall":
		v.ToolName = protocol.Clip(item.Tool, 160)
		v.ToolServer = protocol.Clip(item.Server, 128)
		// Only user-visible text results cross the boundary: never MCP _meta,
		// embedded resources, binary payloads, arbitrary arguments or auth data.
		if item.Result != nil {
			for _, content := range item.Result.Content {
				if content.Type != "text" || content.Text == "" {
					continue
				}
				remaining := 4096 - len(v.ResultSummary)
				if remaining <= 0 {
					v.Truncated = true
					break
				}
				if v.ResultSummary != "" {
					v.ResultSummary += "\n"
					remaining--
				}
				v.ResultSummary += protocol.Clip(content.Text, remaining)
				v.Truncated = v.Truncated || len(content.Text) > remaining
			}
		}
		if item.Error != nil {
			v.ResultSummary = protocol.Clip(item.Error.Message, 4096)
		}
		v.Text = v.ToolName
		if v.Text == "" {
			v.Text = "MCP"
		}
	default:
		return v
	}
	textBudget := max(0, protocol.MaxText-(v.ContextBytes()-len(v.Text)))
	v.Truncated = v.Truncated || len(v.Text) > textBudget
	v.Text = protocol.Clip(v.Text, textBudget)
	return v
}

func clipAsyncQuestions(in []protocol.AsyncQuestion) ([]protocol.AsyncQuestion, bool) {
	var out []protocol.AsyncQuestion
	// Leave room for canonical assistant text (or fallback question titles),
	// keeping the combined activity context within the existing byte limit.
	budget, truncated := protocol.MaxText/2, false
	clip := func(text string, max int) string {
		if max > budget {
			max = budget
		}
		v := text
		if len(v) > max {
			v = v[:max]
			for !utf8.ValidString(v) {
				v = v[:len(v)-1]
			}
		}
		truncated = truncated || len(v) < len(text)
		budget -= len(v)
		return v
	}
	for i, q := range in {
		if i >= 8 || budget == 0 {
			truncated = true
			break
		}
		v := protocol.AsyncQuestion{Title: clip(q.Title, 2048)}
		for j, option := range q.Options {
			if j >= 16 || budget == 0 {
				truncated = true
				break
			}
			v.Options = append(v.Options, clip(option, 512))
		}
		out = append(out, v)
	}
	return out, truncated
}
func (a *Adapter) handle(m rpcMessage) {
	if a.accountEvent(m) {
		return
	}
	var p struct {
		ThreadID  string          `json:"threadId"`
		TurnID    string          `json:"turnId"`
		ItemID    string          `json:"itemId"`
		Delta     string          `json:"delta"`
		Message   string          `json:"message"`
		Changes   json.RawMessage `json:"changes"`
		Diff      string          `json:"diff"`
		RequestID json.RawMessage `json:"requestId"`
		Status    status          `json:"status"`
		Thread    thread          `json:"thread"`
		Turn      turn            `json:"turn"`
		Item      json.RawMessage `json:"item"`
	}
	if json.Unmarshal(m.Params, &p) != nil {
		return
	}
	if len(m.ID) > 0 {
		a.handleRequest(m, p.ThreadID, p.TurnID)
		return
	}
	id := p.ThreadID
	if id == "" {
		id = p.Thread.ID
	}
	if id == "" {
		return
	}
	if m.Method == "thread/started" || m.Method == "thread/unarchived" || m.Method == "turn/started" {
		a.mu.Lock()
		subscribed := a.subscribed[id]
		a.mu.Unlock()
		if !subscribed && a.subscribeSignals != nil {
			select {
			case a.subscribeSignals <- id:
			case <-a.done:
			default:
				a.Close()
			}
		}
	}
	a.mu.Lock()
	s, known := a.sessions[id]
	if m.Method == "thread/started" {
		s = a.session(p.Thread, a.subscribed[id])
		known = true
	}
	if !known {
		a.mu.Unlock()
		return
	}
	ev := protocol.Event{SessionID: s.ID, RawEvent: m.Method, TurnID: p.TurnID, ItemID: p.ItemID}
	switch m.Method {
	case "thread/tokenUsage/updated":
		var value struct {
			Usage protocol.TokenUsage `json:"tokenUsage"`
		}
		if json.Unmarshal(m.Params, &value) != nil {
			a.mu.Unlock()
			return
		}
		value.Usage.ObservedAt = time.Now().UTC()
		value.Usage.Source = "codex/thread/tokenUsage/updated"
		s.TokenUsage = &value.Usage
		ev.Kind = "session"
	case "thread/started":
		ev.Kind = "session"
	case "thread/status/changed":
		s.Status = Normalize(p.Status.Type, p.Status.Flags)
		s.RawStatus = p.Status.Type
		ev.Kind = "session"
	case "thread/name/updated":
		var v struct {
			Name string `json:"threadName"`
		}
		_ = json.Unmarshal(m.Params, &v)
		if v.Name != "" {
			s.Title = protocol.Clip(v.Name, 128)
		}
		ev.Kind = "session"
	case "thread/queue/changed":
		// Collapse duplicate invalidations, not queue contents. The worker reads
		// canonical state once; a change during its RPC schedules another read.
		if a.queuePending == nil {
			a.queuePending = make(map[string]bool)
		}
		if a.queuePending[id] {
			a.mu.Unlock()
			return
		}
		a.queuePending[id] = true
		a.mu.Unlock()
		select {
		case a.queueSignals <- id:
		case <-a.done:
		default:
			a.Close()
		}
		return
	case "thread/closed", "thread/archived", "thread/deleted":
		s.Status = protocol.Inactive
		s.ReadOnly = true
		delete(a.subscribed, id)
		ev.Kind = "session"
	case "turn/started":
		s.Status = protocol.Working
		s.TurnID = p.Turn.ID
		s.TurnStarted = time.Now().UTC()
		ev.Kind = "turn_started"
		ev.TurnID = p.Turn.ID
		for _, raw := range p.Turn.Items {
			if v := activity(raw); v.Kind == "userMessage" && v.ClientID != "" {
				ev.ClientID = v.ClientID
				break
			}
		}
	case "turn/completed":
		s.TurnID = ""
		s.TurnStarted = time.Time{}
		s.Status = protocol.Ready
		ev.Kind = "turn_completed"
		ev.TurnID = p.Turn.ID
		if p.Turn.Status == "failed" {
			s.Status = protocol.Failed
			ev.Kind = "failed"
		}
		ev.NotifyKey = s.ID + "/turn/" + p.Turn.ID
	case "serverRequest/resolved":
		rid := a.requestID(p.RequestID)
		delete(a.requests, rid)
		s.Status = Normalize(s.RawStatus, nil)
		ev.Kind = "request_resolved"
		ev.RequestID = rid
	case "item/agentMessage/delta":
		ev.Kind = "delta"
		ev.Text = protocol.Clip(p.Delta, protocol.MaxText)
	case "item/commandExecution/outputDelta":
		ev.Kind = "command_output"
		ev.Text = protocol.Clip(p.Delta, protocol.MaxText)
	case "item/mcpToolCall/progress", "item/commandExecution/terminalInteraction":
		if p.ItemID == "" {
			a.mu.Unlock()
			return
		}
		if prior, exists := a.items[id+"/"+p.ItemID]; exists &&
			((prior.TurnID != "" && prior.TurnID != p.TurnID) || prior.State != "running") {
			a.mu.Unlock()
			return
		}
		ev.Kind = "tool_progress"
		ev.Text = protocol.Clip(p.Message, 1024)
		if m.Method == "item/commandExecution/terminalInteraction" {
			ev.Kind = "terminal_interaction"
			// stdin can be a credential. Only the occurrence is user-visible.
			ev.Text = "Input sent to command"
		}
	case "item/fileChange/patchUpdated":
		if p.ItemID == "" || len(p.Changes) == 0 {
			a.mu.Unlock()
			return
		}
		prior, exists := a.items[id+"/"+p.ItemID]
		if exists && ((prior.TurnID != "" && prior.TurnID != p.TurnID) || prior.State != "running") {
			a.mu.Unlock()
			return
		}
		raw, _ := json.Marshal(map[string]any{"id": p.ItemID, "type": "fileChange", "status": "inProgress", "changes": p.Changes})
		v := activity(raw)
		v.TurnID = p.TurnID
		if exists {
			v.Timestamp = prior.Timestamp
		}
		a.rememberItem(id, v)
		ev.Kind, ev.Activity = "activity", &v
	case "turn/diff/updated":
		ev.Kind = "diff"
		ev.Text = protocol.Clip(p.Diff, protocol.MaxText)
	case "item/started", "item/completed":
		v := activity(p.Item)
		if v.State == "" {
			if m.Method == "item/started" {
				v.State = "running"
			} else {
				v.State = "completed"
			}
		}
		if v.Text == "" && len(v.Questions) == 0 && v.Kind != "agentMessage" {
			a.mu.Unlock()
			return
		}
		v.TurnID = p.TurnID
		if v.Kind == "commandExecution" || v.Kind == "fileChange" || v.Kind == "mcpToolCall" {
			a.rememberItem(id, v)
		}
		ev.Kind = "activity"
		ev.Activity = &v
	default:
		a.mu.Unlock()
		return
	}
	switch ev.Kind {
	case "session", "turn_started", "turn_completed", "failed", "request_resolved":
		s.UpdatedAt = time.Now().UTC()
		s = a.capabilities(s)
		a.sessions[id] = s
		ev.Session = &s
	}
	a.mu.Unlock()
	if m.Method == "item/started" && ev.Activity != nil && ev.Activity.Kind == "userMessage" && ev.Activity.ClientID != "" {
		// 0.160.0 emits the canonical user item after turn/started (whose items
		// array is empty). Its clientId confirms dispatch without FIFO guessing.
		a.emit(protocol.Event{Kind: "message_dispatched", SessionID: s.ID, TurnID: p.TurnID, ClientID: ev.Activity.ClientID, RawEvent: m.Method})
	}
	a.emit(ev)
	if m.Method == "turn/started" {
		for _, raw := range p.Turn.Items {
			v := activity(raw)
			if v.Kind != "userMessage" || v.Text == "" {
				continue
			}
			v.TurnID = p.Turn.ID
			a.emit(protocol.Event{Kind: "activity", SessionID: s.ID, TurnID: p.Turn.ID, Activity: &v, RawEvent: m.Method})
		}
	}
}

// Caller holds a.mu. This cache only supplies bounded operation metadata.
func (a *Adapter) rememberItem(threadID string, value protocol.Activity) {
	if a.items == nil {
		a.items = make(map[string]protocol.Activity)
	}
	key := threadID + "/" + value.ID
	if _, exists := a.items[key]; !exists {
		a.itemOrder = append(a.itemOrder, key)
	}
	a.items[key] = value
	if len(a.itemOrder) > 128 {
		delete(a.items, a.itemOrder[0])
		a.itemOrder = a.itemOrder[1:]
	}
}

func (a *Adapter) requestID(raw json.RawMessage) string {
	var s string
	if json.Unmarshal(raw, &s) != nil {
		s = string(raw)
	}
	return protocol.SessionID(a.cfg.MachineID, "request-"+s)
}
func (a *Adapter) handleRequest(m rpcMessage, threadID, turnID string) {
	var p struct {
		Reason    string            `json:"reason"`
		Command   string            `json:"command"`
		Cwd       string            `json:"cwd"`
		ItemID    string            `json:"itemId"`
		GrantRoot string            `json:"grantRoot"`
		Available []json.RawMessage `json:"availableDecisions"`
		Questions []struct {
			ID       string            `json:"id"`
			Header   string            `json:"header"`
			Question string            `json:"question"`
			Options  []protocol.Option `json:"options"`
			Secret   bool              `json:"isSecret"`
		} `json:"questions"`
		Message     string          `json:"message"`
		Mode        string          `json:"mode"`
		StartedAtMs int64           `json:"startedAtMs"`
		Network     json.RawMessage `json:"networkApprovalContext"`
		Permissions json.RawMessage `json:"permissions"`
		Schema      json.RawMessage `json:"requestedSchema"`
	}
	if json.Unmarshal(m.Params, &p) != nil || threadID == "" {
		return
	}
	now := time.Now().UTC()
	r := protocol.PendingRequest{ID: a.requestID(m.ID), MachineID: a.cfg.MachineID, SessionID: protocol.SessionID(a.cfg.MachineID, threadID), ThreadID: threadID, TurnID: turnID, Description: protocol.Clip(p.Reason, 2048), Operation: protocol.Clip(p.Command, protocol.MaxText), Cwd: p.Cwd, Payload: nil, CreatedAt: now, ExpiresAt: now.Add(24 * time.Hour), Status: "pending", CanApprove: true}
	a.mu.Lock()
	item, hasItem := a.items[threadID+"/"+p.ItemID]
	a.mu.Unlock()
	if r.Cwd == "" {
		a.mu.Lock()
		r.Cwd = a.sessions[threadID].Cwd
		a.mu.Unlock()
	}
	if p.StartedAtMs > 0 {
		r.CreatedAt = time.UnixMilli(p.StartedAtMs).UTC()
	}
	r.ExpiresAt = r.CreatedAt.Add(24 * time.Hour)
	switch m.Method {
	case "item/commandExecution/requestApproval":
		r.Kind = "command_approval"
		if r.Operation == "" && hasItem {
			r.Operation = item.Text
			if item.Truncated {
				r.CanApprove = false
			}
		}
		if len(p.Available) > 0 {
			r.CanApprove = false
			for _, d := range p.Available {
				if string(d) == `"accept"` {
					r.CanApprove = true
				}
			}
		}
		if r.Operation == "" && len(p.Network) > 0 {
			r.Operation = "Network access: " + string(p.Network)
		}
	case "item/fileChange/requestApproval":
		r.Kind = "file_approval"
		r.Operation = "Apply proposed file changes"
		if hasItem && !item.Truncated {
			r.Operation = item.Text
		} else {
			r.CanApprove = false
			r.Description = "Proposed files unavailable: review and resolve in local Codex"
		}
		if p.GrantRoot != "" {
			r.Operation += " under " + p.GrantRoot
		}
	case "item/permissions/requestApproval":
		r.Kind = "permissions_approval"
		r.Operation = "Grant requested permissions for this turn"
	case "item/tool/requestUserInput":
		r.Kind = "user_input"
		r.Description = "Codex requests your input"
		for _, q := range p.Questions {
			r.Questions = append(r.Questions, protocol.Question{ID: q.ID, Header: q.Header, Question: q.Question, Options: q.Options, Secret: q.Secret})
		}
	case "mcpServer/elicitation/request":
		r.Kind = "mcp_elicitation"
		r.Description = protocol.Clip(p.Message, 2048)
		r.Operation = "MCP elicitation (" + p.Mode + ")"
		if p.Mode == "url" {
			r.CanApprove = false
		}
	default:
		r.Kind = "unsupported"
		r.CanApprove = false
		r.Description = "Questa operazione richiede una risposta dal client Codex locale."
	}
	r.NotifyKey = fmt.Sprintf("%s/request/%s/%s/%s", r.SessionID, r.TurnID, r.Kind, p.ItemID)
	if p.ItemID == "" {
		r.NotifyKey += "/" + r.ID
	}
	// Only canonical display context crosses the adapter boundary. RPC response shape stays local.
	contextFields := map[string]json.RawMessage{}
	if len(p.Permissions) > 0 {
		contextFields["permissions"] = p.Permissions
	}
	if len(p.Schema) > 0 {
		contextFields["input_schema"] = p.Schema
	}
	if len(contextFields) > 0 {
		r.Payload, _ = json.Marshal(contextFields)
	}
	if len(m.Params) > 64<<10 || len(p.Command) > protocol.MaxText || len(r.Operation) > protocol.MaxText || len(r.Payload) > 64<<10 {
		r.CanApprove = false
		r.Description = "Contesto troppo grande: approva soltanto dal client Codex locale."
		r.Payload = nil
	}
	r.Operation = protocol.Clip(r.Operation, protocol.MaxText)
	if r.Description == "" {
		r.Description = strings.ReplaceAll(r.Kind, "_", " ")
	}
	a.mu.Lock()
	if prior, exists := a.requests[r.ID]; exists && prior.Method == m.Method && prior.Request.ThreadID == threadID && prior.Request.TurnID == turnID {
		// Replayed unresolved RPCs keep their incarnation and one-shot reservation.
		// A duplicate must never blink the native form or permit a second answer.
		a.mu.Unlock()
		return
	}
	if len(a.requests) >= 128 {
		a.mu.Unlock()
		a.Close()
		return
	}
	params := m.Params
	if len(params) > 64<<10 {
		params = nil
	}
	a.requests[r.ID] = pending{Request: r, RawID: m.ID, Method: m.Method, Params: params}
	s, ok := a.sessions[threadID]
	if !ok {
		s = protocol.Session{ID: r.SessionID, MachineID: a.cfg.MachineID, ThreadID: threadID, Cwd: p.Cwd, Title: "Thread " + protocol.Clip(threadID, 8), ReadOnly: true}
	}
	s.Status = protocol.NeedsYou
	s.UpdatedAt = now
	s = a.capabilities(s)
	a.sessions[threadID] = s
	a.mu.Unlock()
	a.emit(protocol.Event{Kind: "request", SessionID: r.SessionID, Session: &s, Request: &r, RawEvent: m.Method, NotifyKey: fmt.Sprintf("%s/request/%s/%s", r.SessionID, r.TurnID, p.ItemID)})
}
