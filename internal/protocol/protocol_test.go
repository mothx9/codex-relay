package protocol

import (
	"encoding/json"
	"testing"
	"unicode/utf8"
)

func TestClipValidUTF8AndCanonicalIdentity(t *testing.T) {
	for n := 0; n < 20; n++ {
		v := Clip("message è già pronto ✓", n)
		if len(v) > n || !utf8.ValidString(v) {
			t.Fatal(v, n)
		}
	}
	e := Event{ID: "e", MachineID: "m", SessionID: SessionID("m", "t"), Kind: "delta", Sequence: 7}
	raw, _ := json.Marshal(e)
	var v map[string]any
	_ = json.Unmarshal(raw, &v)
	for _, k := range []string{"event_id", "machine_id", "session_id", "timestamp", "kind", "sequence"} {
		if _, ok := v[k]; !ok {
			t.Fatal(k)
		}
	}
}
