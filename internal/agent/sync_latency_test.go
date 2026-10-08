package agent

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"github.com/mothx9/codex-relay/internal/codex"
	"github.com/mothx9/codex-relay/internal/protocol"
)

type delayedSnapshotBackend struct {
	refreshBackend
	count     atomic.Int32
	watermark atomic.Uint64
	blocked   chan struct{}
	release   chan struct{}
	blockAt   int32
}

func (b *delayedSnapshotBackend) Snapshot(ctx context.Context) ([]protocol.Session, []protocol.PendingRequest, error) {
	if b.count.Add(1) == b.blockAt {
		close(b.blocked)
		select {
		case <-ctx.Done():
			return nil, nil, ctx.Err()
		case <-b.release:
		}
	}
	return nil, nil, nil
}
func (b *delayedSnapshotBackend) Cursor() (string, uint64) { return "epoch", b.watermark.Load() }
func (b *delayedSnapshotBackend) Execute(_ context.Context, c protocol.Command) protocol.Result {
	return protocol.Result{ID: c.ID, OK: true}
}

func syncTestConnection(t *testing.T, b codex.Backend, cfg serveConfig) (<-chan protocol.Message, *protocol.Peer) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	messages := make(chan protocol.Message, 128)
	serverPeer := make(chan *protocol.Peer, 1)
	serverDone := make(chan struct{})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer close(serverDone)
		c, err := (&websocket.Upgrader{}).Upgrade(w, r, nil)
		if err != nil {
			return
		}
		p := protocol.NewPeer(c)
		defer p.Close()
		go p.WriteLoop(ctx)
		serverPeer <- p
		for {
			msg, err := p.Read()
			if err != nil {
				return
			}
			select {
			case messages <- msg:
			case <-ctx.Done():
				return
			}
		}
	}))
	c, _, err := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(srv.URL, "http"), nil)
	if err != nil {
		cancel()
		srv.Close()
		t.Fatal(err)
	}
	p := protocol.NewPeer(c)
	go p.WriteLoop(ctx)
	finished := make(chan error, 1)
	go func() {
		order := []string{}
		finished <- serveConfigured(ctx, p, b, protocol.Machine{ID: "m"}, map[string]protocol.Result{}, &order, cfg)
	}()
	other := <-serverPeer
	t.Cleanup(func() {
		cancel()
		p.Close()
		other.Close()
		select {
		case <-finished:
		case <-time.After(time.Second):
			t.Error("snapshot worker did not cancel")
		}
		<-serverDone
		srv.Close()
	})
	return messages, other
}

func nextSyncMessage(t *testing.T, messages <-chan protocol.Message, match func(protocol.Message) bool) protocol.Message {
	t.Helper()
	timer := time.NewTimer(time.Second)
	defer timer.Stop()
	for {
		select {
		case msg := <-messages:
			if match(msg) {
				return msg
			}
		case <-timer.C:
			t.Fatal("live message stalled behind synchronization")
			return protocol.Message{}
		}
	}
}

func TestSlowPeriodicSnapshotKeepsEventsHeartbeatAndControlLive(t *testing.T) {
	b := &delayedSnapshotBackend{refreshBackend: refreshBackend{make(chan protocol.Event, 16), make(chan struct{})}, blocked: make(chan struct{}), release: make(chan struct{}), blockAt: 2}
	b.watermark.Store(7)
	messages, server := syncTestConnection(t, b, serveConfig{20 * time.Millisecond, 10 * time.Millisecond, 3 * time.Second, time.Millisecond})
	nextSyncMessage(t, messages, func(m protocol.Message) bool { return m.Type == "announce" && m.Machine.Status == protocol.Online })
	select {
	case <-b.blocked:
	case <-time.After(time.Second):
		t.Fatal("refresh did not start")
	}
	b.events <- protocol.Event{ID: "epoch/8", Epoch: "epoch", Sequence: 8, MachineID: "m", SessionID: "m~t", Kind: "delta", Text: "live output"}
	server.Enqueue(protocol.Message{Type: "command", Command: &protocol.Command{ID: "steer", Kind: protocol.Steer}})
	seen := map[string]bool{}
	for len(seen) < 3 {
		msg := nextSyncMessage(t, messages, func(m protocol.Message) bool {
			return !seen[m.Type] && (m.Type == "event" || m.Type == "heartbeat" || m.Type == "result")
		})
		seen[msg.Type] = true
	}
	b.watermark.Store(8)
	close(b.release)
	nextSyncMessage(t, messages, func(m protocol.Message) bool { return m.Type == "announce" && m.Sequence == 8 })
}

func TestSnapshotTimeoutDegradesAndRecoversOnSameSocket(t *testing.T) {
	b := &delayedSnapshotBackend{refreshBackend: refreshBackend{make(chan protocol.Event, 16), make(chan struct{})}, blocked: make(chan struct{}), release: make(chan struct{}), blockAt: 1}
	messages, server := syncTestConnection(t, b, serveConfig{time.Hour, 10 * time.Millisecond, 40 * time.Millisecond, time.Millisecond})
	degraded := nextSyncMessage(t, messages, func(m protocol.Message) bool { return m.Type == "announce" && m.Machine.Status == protocol.Degraded })
	if degraded.Sequence != 0 {
		t.Fatal("incomplete snapshot fabricated admission")
	}
	online := nextSyncMessage(t, messages, func(m protocol.Message) bool { return m.Type == "announce" && m.Machine.Status == protocol.Online })
	if online.Epoch != degraded.Epoch {
		t.Fatal("retry changed the connection epoch")
	}
	select {
	case <-server.Done:
		t.Fatal("retry dropped the healthy Hub socket")
	default:
	}
}

func TestInitialSnapshotDrainsBurstWithoutLosingPostWatermarkEvents(t *testing.T) {
	b := &delayedSnapshotBackend{refreshBackend: refreshBackend{make(chan protocol.Event, 16), make(chan struct{})}, blocked: make(chan struct{}), release: make(chan struct{}), blockAt: 1}
	messages, _ := syncTestConnection(t, b, serveConfig{time.Hour, 10 * time.Millisecond, 3 * time.Second, time.Millisecond})
	<-b.blocked
	for n := uint64(1); n <= 600; n++ {
		select {
		case b.events <- protocol.Event{Epoch: "epoch", Sequence: n}:
		case <-time.After(time.Second):
			t.Fatal("initial synchronization stopped draining live events")
		}
	}
	b.watermark.Store(600)
	close(b.release)
	nextSyncMessage(t, messages, func(m protocol.Message) bool { return m.Type == "announce" && m.Sequence == 600 })
	b.events <- protocol.Event{ID: "epoch/601", Epoch: "epoch", Sequence: 601, Kind: "delta"}
	msg := nextSyncMessage(t, messages, func(m protocol.Message) bool { return m.Type == "event" })
	if msg.Event.Sequence != 601 {
		t.Fatal("covered burst was replayed or live event lost", msg)
	}
}
