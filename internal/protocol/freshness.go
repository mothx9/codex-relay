package protocol

import "time"

// Freshness is bounded control metadata. Times are observed on the Hub clock
// unless explicitly named Agent; it contains neither payloads nor credentials.
type Freshness struct {
	AgentToHub           TimingSummary `json:"agent_to_hub"`
	ConnectionID         string        `json:"connection_id,omitempty"`
	Epoch                string        `json:"epoch,omitempty"`
	ProtocolVersion      int           `json:"protocol_version,omitempty"`
	ConnectedAt          time.Time     `json:"connected_at,omitempty"`
	LastHeartbeat        time.Time     `json:"last_heartbeat,omitempty"`
	LastEvent            time.Time     `json:"last_event,omitempty"`
	LastSnapshot         time.Time     `json:"last_snapshot,omitempty"`
	Sequence             uint64        `json:"sequence"`
	SnapshotSequence     uint64        `json:"snapshot_sequence"`
	ReconnectCount       uint64        `json:"reconnect_count"`
	LastDisconnectReason string        `json:"last_disconnect_reason,omitempty"`
	SnapshotMS           float64       `json:"snapshot_ms"`
	SyncMS               float64       `json:"sync_ms"`
}

// TimingSummary aggregates a bounded number of samples without storing events.
// Cross-host measurements include clock offset and are diagnostic estimates.
type TimingSummary struct {
	Samples   uint64  `json:"samples"`
	LastMS    float64 `json:"last_ms"`
	MeanMS    float64 `json:"mean_ms"`
	MaxMS     float64 `json:"max_ms"`
	ClockSkew bool    `json:"clock_skew"`
}

func (s *TimingSummary) Observe(d time.Duration) {
	ms := float64(d.Microseconds()) / 1000
	if ms < 0 || ms > 300000 {
		s.ClockSkew = true
		return
	}
	s.LastMS = ms
	if s.Samples < 1024 {
		s.Samples++
	}
	s.MeanMS += (ms - s.MeanMS) / float64(s.Samples)
	if ms > s.MaxMS {
		s.MaxMS = ms
	}
}
