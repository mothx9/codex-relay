package agent

import (
	"context"
	"testing"
	"time"
)

func TestBackoffBoundedAndCancelled(t *testing.T) {
	for i := 0; i < 100; i++ {
		d := backoff(i, time.Second)
		if d <= 0 || d > time.Minute {
			t.Fatal(d)
		}
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if wait(ctx, nil, time.Hour) == nil {
		t.Fatal("wait ignored cancellation")
	}
}
