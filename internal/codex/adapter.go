// Package codex is the sole boundary for the evolving Codex app-server protocol.
package codex

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/mothx9/codex-relay/internal/protocol"
	"path/filepath"
	"strings"
	"time"
)

// Snapshot failures expose only a fixed stage and class, never thread IDs or
// arbitrary upstream error text. The original cause remains available to tests.
type snapshotFailure struct {
	stage string
	cause error
}

func (e *snapshotFailure) Error() string { return "Codex snapshot failed: " + e.stage }
func (e *snapshotFailure) Unwrap() error { return e.cause }
func SnapshotFailureReason(err error) string {
	stage := "snapshot"
	var failure *snapshotFailure
	if errors.As(err, &failure) {
		stage = failure.stage
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return stage + "_timeout"
	}
	var rejection *rpcError
	if errors.As(err, &rejection) {
		return fmt.Sprintf("%s_rpc_%d", stage, rejection.Code)
	}
	return stage + "_failed"
}

type Backend interface {
	Snapshot(context.Context) ([]protocol.Session, []protocol.PendingRequest, error)
	Execute(context.Context, protocol.Command) protocol.Result
	Cursor() (string, uint64)
	Events() <-chan protocol.Event
	Done() <-chan struct{}
	Close()
}
type Config struct {
	Binary, Socket, Endpoint, TokenFile, MachineID string
	Private                                        bool
}

type thread struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Cwd       string `json:"cwd"`
	UpdatedAt int64  `json:"updatedAt"`
	Status    status `json:"status"`
	CanInput  *bool  `json:"canAcceptDirectInput"`
	GitInfo   *struct {
		Branch string `json:"branch"`
	} `json:"gitInfo"`
	Turns []turn `json:"turns"`
}
type status struct {
	Type  string   `json:"type"`
	Flags []string `json:"activeFlags"`
}
type turn struct {
	ID          string            `json:"id"`
	Status      string            `json:"status"`
	StartedAt   *int64            `json:"startedAt"`
	CompletedAt *int64            `json:"completedAt"`
	Error       *turnError        `json:"error"`
	Items       []json.RawMessage `json:"items"`
}

type turnError struct {
	Message        string          `json:"message"`
	CodexErrorInfo json.RawMessage `json:"codexErrorInfo"`
}

// Only fixed categories become durable fleet metadata. The upstream message
// stays in the selected conversation and is never saved in Relay's database.
func failureReason(err *turnError) string {
	if err == nil {
		return "execution"
	}
	var category string
	_ = json.Unmarshal(err.CodexErrorInfo, &category)
	switch category {
	case "serverOverloaded", "flexUnavailable":
		return "capacity"
	case "usageLimitExceeded", "sessionBudgetExceeded":
		return "usage_limit"
	case "rateLimitExceeded":
		return "rate_limit"
	case "unauthorized":
		return "authentication"
	case "contextWindowExceeded":
		return "context_limit"
	case "internalServerError":
		return "service"
	}
	var details map[string]json.RawMessage
	if json.Unmarshal(err.CodexErrorInfo, &details) == nil {
		if details["httpConnectionFailed"] != nil || details["responseStreamConnectionFailed"] != nil || details["responseStreamDisconnected"] != nil {
			return "connection"
		}
	}
	message := strings.ToLower(err.Message)
	if strings.Contains(message, "at capacity") || strings.Contains(message, "overloaded") {
		return "capacity"
	}
	return "execution"
}

func turnErrorActivity(value turn) protocol.Activity {
	message := "Codex stopped this turn. Send a message to retry."
	if value.Error != nil && value.Error.Message != "" {
		message = protocol.Clip(value.Error.Message, 2048)
	}
	item := protocol.Activity{ID: "turn-error-" + value.ID, TurnID: value.ID, Kind: "turnError", State: "failed", Text: message, Timestamp: time.Now().UTC()}
	if value.CompletedAt != nil {
		item.Timestamp = time.Unix(*value.CompletedAt, 0).UTC()
	}
	return item
}

func Normalize(raw string, flags []string) string {
	switch raw {
	case "active":
		for _, f := range flags {
			if f == "waitingForApproval" || f == "waitingForUserInput" || f == "waitingOnApproval" || f == "waitingOnUserInput" {
				return protocol.NeedsYou
			}
		}
		return protocol.Working
	case "idle":
		return protocol.Ready
	case "systemError":
		return protocol.Failed
	default:
		return protocol.Inactive
	}
}
func (a *Adapter) session(t thread, subscribed bool) protocol.Session {
	s := protocol.Session{ID: protocol.SessionID(a.cfg.MachineID, t.ID), MachineID: a.cfg.MachineID, ThreadID: t.ID, Title: protocol.Clip(t.Name, 128), Cwd: t.Cwd, Project: filepath.Base(t.Cwd), Status: Normalize(t.Status.Type, t.Status.Flags), RawStatus: t.Status.Type, UpdatedAt: time.Unix(t.UpdatedAt, 0).UTC(), ReadOnly: !subscribed, QueueSupported: a.queue}
	if s.Title == "" {
		s.Title = "Thread " + protocol.Clip(t.ID, 8)
	}
	if t.GitInfo != nil {
		s.Branch = t.GitInfo.Branch
	}
	if t.CanInput == nil || !*t.CanInput {
		s.ReadOnly = true
	}
	for _, v := range t.Turns {
		if v.Status == "inProgress" {
			s.TurnID = v.ID
			if v.StartedAt != nil {
				s.TurnStarted = time.Unix(*v.StartedAt, 0).UTC()
			}
		}
	}
	// thread/read orders turns oldest to newest. An earlier failure must not
	// reclassify a later successful or running turn.
	if len(t.Turns) > 0 {
		latest := t.Turns[len(t.Turns)-1]
		if latest.Status == "failed" && s.Status != protocol.Working && s.Status != protocol.NeedsYou {
			s.Status = protocol.Failed
			s.FailureReason = failureReason(latest.Error)
		}
	}
	return a.capabilities(s)
}

// Called while adapter metadata is locked. Machine connectivity is gated by Hub/PWA.
func (a *Adapter) capabilities(s protocol.Session) protocol.Session {
	s.QueueSupported = a.queue
	s.Capabilities = protocol.Capabilities{}
	// Direct-input permission does not revoke a server request addressed to us.
	for _, p := range a.requests {
		if p.Request.ThreadID == s.ThreadID {
			s.Status = protocol.NeedsYou
			if p.Request.Kind != "unsupported" && !p.Sent {
				s.Capabilities.CanAnswer = true
			}
		}
	}
	if s.ReadOnly {
		return s
	}
	s.Capabilities.CanSendImages = true
	s.Capabilities.CanEditQueue = a.queue
	s.Capabilities.CanSend = s.Status == protocol.Ready || s.Status == protocol.Failed
	s.Capabilities.CanFollowUp = s.Status == protocol.Working && a.queue
	s.Capabilities.CanSteer = s.Status == protocol.Working && s.TurnID != ""
	s.Capabilities.CanSteerQueue = a.queue && s.Capabilities.CanSteer
	s.Capabilities.CanInterrupt = (s.Status == protocol.Working || s.Status == protocol.NeedsYou) && s.TurnID != ""
	return s
}
func decode(raw json.RawMessage, v any) error {
	if len(raw) == 0 {
		return errors.New("empty RPC result")
	}
	return json.Unmarshal(raw, v)
}
