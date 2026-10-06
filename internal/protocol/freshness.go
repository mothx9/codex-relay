package protocol

import "time"

// Freshness is bounded control metadata. Times are observed on the Hub clock
// unless explicitly named Agent; it contains neither payloads nor credentials.
type Freshness struct {
	ConnectionID         string    `json:"connection_id,omitempty"`
	Epoch                string    `json:"epoch,omitempty"`
	ProtocolVersion      int       `json:"protocol_version,omitempty"`
	ConnectedAt          time.Time `json:"connected_at,omitempty"`
	LastHeartbeat        time.Time `json:"last_heartbeat,omitempty"`
	LastEvent            time.Time `json:"last_event,omitempty"`
	LastSnapshot         time.Time `json:"last_snapshot,omitempty"`
	Sequence             uint64    `json:"sequence"`
	SnapshotSequence     uint64    `json:"snapshot_sequence"`
	ReconnectCount       uint64    `json:"reconnect_count"`
	LastDisconnectReason string    `json:"last_disconnect_reason,omitempty"`
	SnapshotMS           float64   `json:"snapshot_ms"`
	SyncMS               float64   `json:"sync_ms"`
}
