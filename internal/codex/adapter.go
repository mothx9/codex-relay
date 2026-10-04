// Package codex is the sole boundary for the evolving Codex app-server protocol.
package codex

import (
	"context"
	"encoding/json"
	"errors"
	"github.com/mothx9/codex-relay/internal/protocol"
	"path/filepath"
	"time"
)

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
	ID        string `json:"id"`
	Status    string `json:"status"`
	StartedAt *int64 `json:"startedAt"`
}

func Normalize(raw string, flags []string) string {
	switch raw {
	case "active":
		for _, f := range flags {
			if f == "waitingForApproval" || f == "waitingForUserInput" {
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
	if t.CanInput != nil && !*t.CanInput {
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
	return s
}
func decode(raw json.RawMessage, v any) error {
	if len(raw) == 0 {
		return errors.New("empty RPC result")
	}
	return json.Unmarshal(raw, v)
}
