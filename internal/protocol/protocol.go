// Package protocol defines Relay's wire model. It contains no Codex RPC names.
package protocol

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"time"
)

const Version = 1
const MaxMessage = 1 << 20
const MaxSessions = 256
const MaxText = 16384
const (
	Online       = "ONLINE"
	Syncing      = "SYNCING"
	Reconnecting = "RECONNECTING"
	Offline      = "OFFLINE"
	Degraded     = "DEGRADED"
	NeedsYou     = "NEEDS_YOU"
	Working      = "WORKING"
	Ready        = "READY"
	Inactive     = "INACTIVE"
	Failed       = "FAILED"
)

type Machine struct {
	AgentVersion string    `json:"agent_version,omitempty"`
	Freshness    Freshness `json:"freshness"`
	ID           string    `json:"id"`
	Name         string    `json:"name"`
	Status       string    `json:"status"`
	CodexVersion string    `json:"codex_version,omitempty"`
	Adapter      string    `json:"adapter,omitempty"`
	LastSeen     time.Time `json:"last_seen"`
	Account      *Account  `json:"account,omitempty"`
}

// Account contains public account metadata, never authentication material.
type Account struct {
	Kind  string `json:"kind"`
	Email string `json:"email,omitempty"`
	Plan  string `json:"plan,omitempty"`
}
type Session struct {
	Fresh          bool         `json:"fresh"`
	ObservedAt     time.Time    `json:"observed_at,omitempty"`
	AgentEpoch     string       `json:"agent_epoch,omitempty"`
	ID             string       `json:"id"`
	MachineID      string       `json:"machine_id"`
	ThreadID       string       `json:"thread_id"`
	Title          string       `json:"title"`
	Project        string       `json:"project"`
	Cwd            string       `json:"cwd"`
	Branch         string       `json:"branch,omitempty"`
	Status         string       `json:"status"`
	RawStatus      string       `json:"raw_status,omitempty"`
	UpdatedAt      time.Time    `json:"updated_at"`
	TurnID         string       `json:"turn_id,omitempty"`
	TurnStarted    time.Time    `json:"turn_started,omitempty"`
	ReadOnly       bool         `json:"read_only"`
	QueueSupported bool         `json:"queue_supported"`
	Capabilities   Capabilities `json:"capabilities"`
}
type Capabilities struct {
	CanEditQueue bool `json:"can_edit_queue"`
	CanSend      bool `json:"can_send"`
	CanFollowUp  bool `json:"can_follow_up"`
	CanSteer     bool `json:"can_steer"`
	CanInterrupt bool `json:"can_interrupt"`
	CanAnswer    bool `json:"can_answer"`
}
type FileChange struct {
	Path         string `json:"path"`
	Kind         string `json:"kind"`
	PreviousPath string `json:"previous_path,omitempty"`
	Patch        string `json:"patch,omitempty"`
}
type Activity struct {
	State      string          `json:"state,omitempty"`
	Command    string          `json:"command,omitempty"`
	ExitCode   *int            `json:"exit_code,omitempty"`
	DurationMS *int64          `json:"duration_ms,omitempty"`
	ToolName   string          `json:"tool_name,omitempty"`
	ToolServer string          `json:"tool_server,omitempty"`
	Files      []FileChange    `json:"files,omitempty"`
	Truncated  bool            `json:"truncated,omitempty"`
	ID         string          `json:"id"`
	TurnID     string          `json:"turn_id,omitempty"`
	Kind       string          `json:"kind"`
	Text       string          `json:"text"`
	Timestamp  time.Time       `json:"timestamp"`
	ClientID   string          `json:"client_id,omitempty"`
	Questions  []AsyncQuestion `json:"questions,omitempty"`
}

// ContextBytes counts retained user-visible content, including structured
// metadata. It deliberately excludes transport identity and scalar state.
func (a Activity) ContextBytes() int {
	n := len(a.Text) + len(a.Command) + len(a.ToolName) + len(a.ToolServer)
	for _, f := range a.Files {
		n += len(f.Path) + len(f.Kind) + len(f.PreviousPath) + len(f.Patch)
	}
	for _, q := range a.Questions {
		n += len(q.Title)
		for _, o := range q.Options {
			n += len(o)
		}
	}
	return n
}

// Canonical nonblocking questions carried by an app-server agentMessage. They
// are display context, not a pending server RPC or an approval capability.
type AsyncQuestion struct {
	Title   string   `json:"title"`
	Options []string `json:"options,omitempty"`
}

// FollowUp is an ephemeral view of the queue owned by the backend.
type FollowUp struct {
	Editable bool   `json:"editable,omitempty"`
	Revision string `json:"revision,omitempty"`
	ID       string `json:"id"`
	ClientID string `json:"client_id"`
	Text     string `json:"text,omitempty"`
}
type Question struct {
	ID       string   `json:"id"`
	Header   string   `json:"header"`
	Question string   `json:"question"`
	Options  []Option `json:"options,omitempty"`
	Secret   bool     `json:"secret,omitempty"`
}
type Option struct {
	Label       string `json:"label"`
	Description string `json:"description"`
}
type PendingRequest struct {
	ID          string          `json:"request_id"`
	MachineID   string          `json:"machine_id"`
	SessionID   string          `json:"session_id"`
	ThreadID    string          `json:"thread_id"`
	TurnID      string          `json:"turn_id,omitempty"`
	Kind        string          `json:"kind"`
	Description string          `json:"description"`
	Operation   string          `json:"operation,omitempty"`
	Cwd         string          `json:"cwd,omitempty"`
	Payload     json.RawMessage `json:"payload,omitempty"`
	Questions   []Question      `json:"questions,omitempty"`
	CreatedAt   time.Time       `json:"created_at"`
	ExpiresAt   time.Time       `json:"expires_at"`
	Status      string          `json:"status"`
	NotifyKey   string          `json:"notify_key,omitempty"`
	CanApprove  bool            `json:"can_approve"`
}

// LiveActivity is a bounded, ephemeral operational summary for Fleet. It
// contains no transcript, terminal output, arguments or model reasoning.
type LiveActivity struct {
	ItemID    string    `json:"item_id"`
	Kind      string    `json:"kind"`
	Label     string    `json:"label"`
	State     string    `json:"state"`
	Timestamp time.Time `json:"timestamp"`
}
type Event struct {
	LiveActivity *LiveActivity   `json:"live_activity,omitempty"`
	ID           string          `json:"event_id"`
	MachineID    string          `json:"machine_id"`
	SessionID    string          `json:"session_id"`
	Timestamp    time.Time       `json:"timestamp"`
	Kind         string          `json:"kind"`
	Sequence     uint64          `json:"sequence"`
	Epoch        string          `json:"epoch"`
	RawEvent     string          `json:"raw_event,omitempty"`
	Session      *Session        `json:"session,omitempty"`
	Request      *PendingRequest `json:"request,omitempty"`
	RequestID    string          `json:"request_id,omitempty"`
	Activity     *Activity       `json:"activity,omitempty"`
	TurnID       string          `json:"turn_id,omitempty"`
	ItemID       string          `json:"item_id,omitempty"`
	Text         string          `json:"text,omitempty"`
	NotifyKey    string          `json:"notify_key,omitempty"`
	FollowUps    []FollowUp      `json:"follow_ups,omitempty"`
	ClientID     string          `json:"client_id,omitempty"`
}
type Command struct {
	QueueID       string              `json:"queue_id,omitempty"`
	QueueClientID string              `json:"queue_client_id,omitempty"`
	QueueRevision string              `json:"queue_revision,omitempty"`
	HistoryCursor string              `json:"history_cursor,omitempty"`
	ID            string              `json:"id"`
	Kind          string              `json:"kind"`
	SessionID     string              `json:"session_id"`
	ThreadID      string              `json:"thread_id,omitempty"`
	Text          string              `json:"text,omitempty"`
	TurnID        string              `json:"turn_id,omitempty"`
	RequestID     string              `json:"request_id,omitempty"`
	Decision      string              `json:"decision,omitempty"`
	Answers       map[string][]string `json:"answers,omitempty"`
	Content       json.RawMessage     `json:"content,omitempty"`
}
type Result struct {
	HistoryCursor string     `json:"history_cursor,omitempty"`
	ID            string     `json:"id"`
	OK            bool       `json:"ok"`
	Error         string     `json:"error,omitempty"`
	History       []Activity `json:"history,omitempty"`
	SessionID     string     `json:"session_id,omitempty"`
	ErrorCode     string     `json:"error_code,omitempty"`
	Retryable     bool       `json:"retryable"`
	QueueID       string     `json:"queue_id,omitempty"`
	FollowUps     []FollowUp `json:"follow_ups,omitempty"`
}
type Snapshot struct {
	LiveActivities map[string]LiveActivity `json:"live_activities,omitempty"`
	Machines       []Machine               `json:"machines"`
	Sessions       []Session               `json:"sessions"`
	Requests       []PendingRequest        `json:"requests"`
}
type Message struct {
	HistoryRequestID string           `json:"history_request_id,omitempty"`
	Version          int              `json:"version,omitempty"`
	Type             string           `json:"type"`
	Machine          *Machine         `json:"machine,omitempty"`
	Sessions         []Session        `json:"sessions,omitempty"`
	Requests         []PendingRequest `json:"requests,omitempty"`
	Snapshot         *Snapshot        `json:"snapshot,omitempty"`
	Event            *Event           `json:"event,omitempty"`
	Command          *Command         `json:"command,omitempty"`
	Result           *Result          `json:"result,omitempty"`
	Epoch            string           `json:"epoch,omitempty"`
	Sequence         uint64           `json:"sequence,omitempty"`
	SessionID        string           `json:"session_id,omitempty"`
}

func ID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b[:])
}
func SessionID(machine, thread string) string { return machine + "~" + thread }
func Clip(s string, n int) string {
	if len(s) > n {
		s = s[:n]
		for len(s) > 0 && s[len(s)-1] >= 0x80 {
			s = s[:len(s)-1]
		}
	}
	return s
}
