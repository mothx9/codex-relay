package hub

import (
	"github.com/mothx9/codex-relay/internal/protocol"
	"time"
)

const bufferTTL = 5 * time.Minute

// Recent holds at most 50 items and 128 KiB. Hub allocates at most 64 such buffers.
type Recent struct {
	Items   []protocol.Activity
	Touched time.Time
}

func (r *Recent) Put(v protocol.Activity) {
	v.Text = protocol.Clip(v.Text, protocol.MaxText)
	r.Touched = time.Now()
	found := false
	for i := range r.Items {
		if r.Items[i].ID == v.ID {
			r.Items[i] = v
			found = true
			break
		}
	}
	if !found {
		r.Items = append(r.Items, v)
	}
	for len(r.Items) > 50 || r.bytes() > 128<<10 {
		r.Items = r.Items[1:]
	}
}
func (r *Recent) bytes() int {
	n := 0
	for _, v := range r.Items {
		n += len(v.Text)
	}
	return n
}
func (r *Recent) Apply(e protocol.Event) {
	if e.Activity != nil {
		r.Put(*e.Activity)
		return
	}
	if e.Kind != "delta" && e.Kind != "command_output" && e.Kind != "diff" {
		return
	}
	id := e.ItemID
	if id == "" {
		id = e.TurnID + "/" + e.Kind
	}
	v := protocol.Activity{ID: id, TurnID: e.TurnID, Kind: e.Kind, Timestamp: e.Timestamp}
	for _, old := range r.Items {
		if old.ID == id {
			v = old
			break
		}
	}
	if e.Kind == "diff" {
		v.Text = e.Text
	} else {
		v.Text += e.Text
	}
	r.Put(v)
}
