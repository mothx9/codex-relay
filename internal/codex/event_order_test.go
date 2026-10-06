package codex

import (
	"github.com/mothx9/codex-relay/internal/protocol"
	"sync"
	"testing"
)

func TestConcurrentEventsPreserveWireSequence(t *testing.T) {
	a := &Adapter{epoch: "test", events: make(chan protocol.Event, 1000), done: make(chan struct{})}
	var workers sync.WaitGroup
	for i := 0; i < 100; i++ {
		workers.Add(1)
		go func() {
			defer workers.Done()
			for j := 0; j < 10; j++ {
				a.emit(protocol.Event{Kind: "activity"})
			}
		}()
	}
	workers.Wait()
	for sequence := uint64(1); sequence <= 1000; sequence++ {
		e := <-a.events
		if e.Sequence != sequence {
			t.Fatalf("wire sequence %d arrived at position %d", e.Sequence, sequence)
		}
	}
}
