package hub

import (
	"encoding/json"
	"github.com/mothx9/codex-relay/internal/protocol"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestDiagnosticsBoundedAndSecretFree(t *testing.T) {
	var timing protocol.TimingSummary
	for i := 0; i < 100000; i++ {
		timing.Observe(2 * time.Millisecond)
	}
	if timing.Samples != 1024 || timing.MeanMS != 2 || timing.LastMS != 2 {
		t.Fatal("unbounded/incorrect aggregation", timing)
	}
	timing.Observe(-time.Second)
	if !timing.ClockSkew {
		t.Fatal("negative clock delta treated as latency")
	}
	h, db, srv := testHub(t, filepath.Join(t.TempDir(), "db"))
	defer srv.Close()
	defer db.Close()
	h.machines["m"] = protocol.Machine{ID: "m", Account: &protocol.Account{Email: "PRIVATE_EMAIL"}, Freshness: protocol.Freshness{AgentToHub: timing}}
	h.requests["r"] = protocol.PendingRequest{ID: "r", MachineID: "m", Payload: json.RawMessage(`{"token":"PRIVATE_TOKEN"}`), Operation: "PRIVATE_COMMAND"}
	b, err := json.Marshal(h.diagnosticMachines(time.Now()))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(b), "PRIVATE_") {
		t.Fatal("diagnostics leaked sensitive content")
	}
	if len(b) > 2048 {
		t.Fatal("diagnostics unexpectedly large")
	}
}
