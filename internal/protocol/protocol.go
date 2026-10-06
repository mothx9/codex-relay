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
	Online   = "ONLINE"
	Offline  = "OFFLINE"
	Degraded = "DEGRADED"
	NeedsYou = "NEEDS_YOU"
	Working  = "WORKING"
	Ready    = "READY"
	Inactive = "INACTIVE"
	Failed   = "FAILED"
)

type Machine struct {
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
	CanSend      bool `json:"can_send"`
	CanFollowUp  bool `json:"can_follow_up"`
	CanSteer     bool `json:"can_steer"`
	CanInterrupt bool `json:"can_interrupt"`
	CanAnswer    bool `json:"can_answer"`
}
type Activity struct {
	Truncated bool      `json:"truncated,omitempty"`
	ID        string    `json:"id"`
	TurnID    string    `json:"turn_id,omitempty"`
	Kind      string    `json:"kind"`
	Text      string    `json:"text"`
	Timestamp time.Time `json:"timestamp"`
	ClientID  string    `json:"client_id,omitempty"`
}

// FollowUp is an ephemeral view of the queue owned by the backend.
type FollowUp struct {
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
type Event struct {
	ID        string          `json:"event_id"`
	MachineID string          `json:"machine_id"`
	SessionID string          `json:"session_id"`
	Timestamp time.Time       `json:"timestamp"`
	Kind      string          `json:"kind"`
	Sequence  uint64          `json:"sequence"`
	Epoch     string          `json:"epoch"`
	RawEvent  string          `json:"raw_event,omitempty"`
	Session   *Session        `json:"session,omitempty"`
	Request   *PendingRequest `json:"request,omitempty"`
	RequestID string          `json:"request_id,omitempty"`
	Activity  *Activity       `json:"activity,omitempty"`
	TurnID    string          `json:"turn_id,omitempty"`
	ItemID    string          `json:"item_id,omitempty"`
	Text      string          `json:"text,omitempty"`
	NotifyKey string          `json:"notify_key,omitempty"`
	FollowUps []FollowUp      `json:"follow_ups,omitempty"`
	ClientID  string          `json:"client_id,omitempty"`
}
type Command struct {
	ID        string              `json:"id"`
	Kind      string              `json:"kind"`
	SessionID string              `json:"session_id"`
	ThreadID  string              `json:"thread_id,omitempty"`
	Text      string              `json:"text,omitempty"`
	TurnID    string              `json:"turn_id,omitempty"`
	RequestID string              `json:"request_id,omitempty"`
	Decision  string              `json:"decision,omitempty"`
	Answers   map[string][]string `json:"answers,omitempty"`
	Content   json.RawMessage     `json:"content,omitempty"`
}
type Result struct {
	ID        string     `json:"id"`
	OK        bool       `json:"ok"`
	Error     string     `json:"error,omitempty"`
	History   []Activity `json:"history,omitempty"`
	SessionID string     `json:"session_id,omitempty"`
	ErrorCode string     `json:"error_code,omitempty"`
	Retryable bool       `json:"retryable"`
	QueueID   string     `json:"queue_id,omitempty"`
	FollowUps []FollowUp `json:"follow_ups,omitempty"`
}
type Snapshot struct {
	Machines []Machine        `json:"machines"`
	Sessions []Session        `json:"sessions"`
	Requests []PendingRequest `json:"requests"`
}
type Message struct {
	Version   int              `json:"version,omitempty"`
	Type      string           `json:"type"`
	Machine   *Machine         `json:"machine,omitempty"`
	Sessions  []Session        `json:"sessions,omitempty"`
	Requests  []PendingRequest `json:"requests,omitempty"`
	Snapshot  *Snapshot        `json:"snapshot,omitempty"`
	Event     *Event           `json:"event,omitempty"`
	Command   *Command         `json:"command,omitempty"`
	Result    *Result          `json:"result,omitempty"`
	Epoch     string           `json:"epoch,omitempty"`
	Sequence  uint64           `json:"sequence,omitempty"`
	SessionID string           `json:"session_id,omitempty"`
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
