package codex

import (
	"context"
	"errors"
	"fmt"
	"testing"
)

func TestSnapshotFailureDiagnosticsContainOnlyStageAndFailureClass(t *testing.T) {
	for _, tc := range []struct {
		err  error
		want string
	}{
		{context.DeadlineExceeded, "snapshot_timeout"},
		{&snapshotFailure{"loaded_threads", fmt.Errorf("private upstream content: %w", context.DeadlineExceeded)}, "loaded_threads_timeout"},
		{&snapshotFailure{"subscription", &rpcError{Code: -32600, Message: "private thread and token"}}, "subscription_rpc_-32600"},
		{errors.New("private provider details"), "snapshot_failed"},
	} {
		if got := SnapshotFailureReason(tc.err); got != tc.want {
			t.Fatalf("unsafe or ambiguous diagnostic: %q", got)
		}
	}
}
