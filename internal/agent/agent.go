// Package agent maintains outbound Hub connectivity and local Codex control.
package agent

import (
	"context"
	"errors"
	"github.com/gorilla/websocket"
	"github.com/mothx9/codex-relay/internal/codex"
	"github.com/mothx9/codex-relay/internal/protocol"
	"log/slog"
	"math/rand/v2"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

type Config struct {
	HubURL, TokenFile, MachineID, Name string
	Version                            string
	Insecure                           bool
	Codex                              codex.Config
	Open                               func(context.Context, codex.Config) (codex.Backend, error)
	RetryMin                           time.Duration
}

func backoff(attempt int, min time.Duration) time.Duration {
	if min == 0 {
		min = time.Second
	}
	if attempt > 6 {
		attempt = 6
	}
	d := min * time.Duration(1<<attempt)
	if d > 15*time.Second {
		d = 15 * time.Second
	}
	return d/2 + time.Duration(rand.Int64N(int64(d/2)+1))
}
func wait(ctx context.Context, b codex.Backend, d time.Duration) error {
	t := time.NewTimer(d)
	defer t.Stop()
	for {
		if b == nil {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-t.C:
				return nil
			}
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-b.Done():
			return errors.New("Codex disconnected")
		case <-b.Events(): // state is rehydrated before reconnect; ephemeral deltas can be discarded.
		case <-t.C:
			return nil
		}
	}
}
func Run(ctx context.Context, cfg Config) error {
	u, e := url.Parse(cfg.HubURL)
	if e != nil || u.Host == "" {
		return errors.New("invalid Hub URL")
	}
	if u.Scheme != "https" && u.Scheme != "wss" && !cfg.Insecure {
		return errors.New("Hub requires HTTPS/WSS; use --insecure-http for explicit development")
	}
	if u.Scheme == "https" {
		u.Scheme = "wss"
	}
	if u.Scheme == "http" {
		u.Scheme = "ws"
	}
	if u.Scheme != "ws" && u.Scheme != "wss" {
		return errors.New("unsupported Hub transport")
	}
	u.Path = "/api/agent"
	u.RawQuery = ""
	u.Fragment = ""
	b, e := os.ReadFile(cfg.TokenFile)
	if e != nil {
		return e
	}
	token := strings.TrimSpace(string(b))
	if len(token) < 32 {
		return errors.New("agent token too short")
	}
	if cfg.Open == nil {
		cfg.Open = func(ctx context.Context, c codex.Config) (codex.Backend, error) { return codex.Open(ctx, c) }
	}
	cfg.Codex.MachineID = cfg.MachineID
	version, err := codex.Version(ctx, cfg.Codex.Binary)
	if err != nil {
		version = "unavailable"
	}
	machine := protocol.Machine{ID: cfg.MachineID, Name: cfg.Name, Status: protocol.Online, AgentVersion: cfg.Version, CodexVersion: version, Adapter: "shared"}
	if cfg.Codex.Private {
		machine.Adapter = "private"
	}
	// Keep command outcomes across Hub reconnects. Message text and history are excluded.
	cache := map[string]protocol.Result{}
	order := []string{}
	var backend codex.Backend
	defer func() {
		if backend != nil {
			backend.Close()
		}
	}()
	attempt := 0
	for ctx.Err() == nil {
		if backend == nil {
			backend, err = cfg.Open(ctx, cfg.Codex)
			if err != nil {
				backend = nil
			}
		}
		hdr := http.Header{"Authorization": []string{"Bearer " + token}, "X-Relay-Machine": []string{cfg.MachineID}}
		conn, resp, dialErr := (&websocket.Dialer{HandshakeTimeout: 10 * time.Second}).DialContext(ctx, u.String(), hdr)
		if resp != nil && resp.Body != nil {
			_ = resp.Body.Close()
		}
		if dialErr == nil {
			connectedAt := time.Now()
			p := protocol.NewPeer(conn)
			go p.WriteLoop(ctx)
			if backend == nil {
				m := machine
				m.Status = protocol.Degraded
				m.LastSeen = time.Now().UTC()
				p.Enqueue(protocol.Message{Version: protocol.Version, Type: "announce", Machine: machineCopy(m), Epoch: protocol.ID()})
				_ = wait(ctx, nil, backoff(attempt, cfg.RetryMin))
				p.Close()
			}
			if backend != nil {
				err = serve(ctx, p, backend, machine, cache, &order)
				p.Close()
				select {
				case <-backend.Done():
					backend.Close()
					backend = nil
				default:
				}
				// A successful handshake is not a stable synchronized connection.
				if time.Since(connectedAt) >= protocol.PeerTimeout {
					attempt = 0
				}
			}
		}
		if ctx.Err() != nil {
			break
		}
		slog.Warn("agent reconnecting", "machine", cfg.MachineID, "codex_connected", backend != nil, "hub_connected", dialErr == nil)
		if wait(ctx, backend, backoff(attempt, cfg.RetryMin)) != nil && ctx.Err() == nil {
			backend.Close()
			backend = nil
		}
		attempt++
	}
	return ctx.Err()
}
func serve(ctx context.Context, p *protocol.Peer, b codex.Backend, m protocol.Machine, cache map[string]protocol.Result, order *[]string) error {
	return serveRefreshing(ctx, p, b, m, cache, order, 2*time.Minute)
}
func serveRefreshing(ctx context.Context, p *protocol.Peer, b codex.Backend, m protocol.Machine, cache map[string]protocol.Result, order *[]string, refreshEvery time.Duration) error {
	return serveConfigured(ctx, p, b, m, cache, order, serveConfig{refreshEvery, protocol.PingInterval, 15 * time.Second, time.Second})
}

type serveConfig struct {
	refresh, heartbeat, snapshotTimeout, retryMin time.Duration
}

func serveConfigured(ctx context.Context, p *protocol.Peer, b codex.Backend, m protocol.Machine, cache map[string]protocol.Result, order *[]string, cfg serveConfig) error {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	// Snapshots may wait on disk or on many Codex reads. They must not stop
	// event forwarding, socket reads, or application heartbeats.
	type snapshotResult struct {
		sessions  []protocol.Session
		requests  []protocol.PendingRequest
		epoch     string
		watermark uint64
		ms        float64
		err       error
	}
	refreshRequests := make(chan struct{}, 1)
	refreshed := make(chan snapshotResult, 1)
	snapshotDone := make(chan struct{})
	defer func() { cancel(); <-snapshotDone }()
	go func() {
		defer close(snapshotDone)
		for {
			select {
			case <-ctx.Done():
				return
			case <-refreshRequests:
				started := time.Now()
				readCtx, stop := context.WithTimeout(ctx, cfg.snapshotTimeout)
				sessions, requests, err := b.Snapshot(readCtx)
				stop()
				epoch, watermark := b.Cursor()
				result := snapshotResult{sessions, requests, epoch, watermark, float64(time.Since(started).Microseconds()) / 1000, err}
				select {
				case refreshed <- result:
				case <-ctx.Done():
					return
				}
			}
		}
	}()
	busy := false
	requestSnapshot := func() {
		if !busy {
			busy = true
			refreshRequests <- struct{}{}
		}
	}
	revision := uint64(0)
	epoch, watermark := b.Cursor()
	requestSnapshot()
	forwarded := watermark
	announced := false
	var initialEvents []protocol.Event
	var droppedInitial uint64
	syncFailures := 0
	retry := time.NewTimer(time.Hour)
	if !retry.Stop() {
		<-retry.C
	}
	defer retry.Stop()
	commands := make(chan protocol.Command, 32)
	reads := make(chan protocol.Command, 8)
	readerDone := make(chan struct{})
	defer func() { p.Close(); <-readerDone }()
	go func() {
		defer close(readerDone)
		defer p.Close()
		for {
			msg, e := p.Read()
			if e != nil {
				return
			}
			if msg.Type != "command" || msg.Command == nil {
				return
			}
			destination := commands
			if msg.Command.Kind == "history" || msg.Command.Kind == "catalogue" {
				destination = reads
			}
			select {
			case destination <- *msg.Command:
			case <-ctx.Done():
				return
			default:
				return
			}
		}
	}()
	workerDone := make(chan struct{})
	defer func() { cancel(); <-workerDone }()
	go func() {
		defer close(workerDone)
		for {
			select {
			case <-ctx.Done():
				return
			case <-p.Done:
				return
			case cmd := <-commands:
				if r, ok := cache[cmd.ID]; ok {
					p.Enqueue(protocol.Message{Type: "result", Result: &r})
					continue
				}
				r := b.Execute(ctx, cmd)
				if cmd.Kind != "history" && cmd.Kind != "catalogue" {
					cached := r
					// Idempotency retains outcomes, never an old queue payload.
					cached.FollowUps = nil
					cache[cmd.ID] = cached
					*order = append(*order, cmd.ID)
					if len(*order) > 1024 {
						delete(cache, (*order)[0])
						*order = (*order)[1:]
					}
				}
				p.Enqueue(protocol.Message{Type: "result", Result: &r})
			}
		}
	}()
	// A paged read can wait on disk or Codex. Keep it out of the serialized
	// mutation lane so Steer, answers and Interrupt do not wait behind history.
	readDone := make(chan struct{})
	defer func() { cancel(); <-readDone }()
	go func() {
		defer close(readDone)
		for {
			select {
			case <-ctx.Done():
				return
			case <-p.Done:
				return
			case cmd := <-reads:
				r := b.Execute(ctx, cmd)
				p.Enqueue(protocol.Message{Type: "result", Result: &r})
			}
		}
	}()
	// Account/quota RPCs are optional diagnostics, never a prerequisite for
	// current execution state. A slow provider must not stall pending requests.
	accountRefresh := make(chan struct{}, 1)
	accountDone := make(chan struct{})
	defer func() { cancel(); <-accountDone }()
	go func() {
		defer close(accountDone)
		reader, ok := b.(interface {
			Account(context.Context) *protocol.Account
		})
		if !ok {
			return
		}
		for {
			select {
			case <-ctx.Done():
				return
			case <-p.Done:
				return
			case <-accountRefresh:
				reader.Account(ctx)
			}
		}
	}()
	accountRefresh <- struct{}{}
	heartbeat := time.NewTicker(cfg.heartbeat)
	defer heartbeat.Stop()
	refresh := time.NewTicker(cfg.refresh)
	defer refresh.Stop()
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-p.Done:
			return errors.New("Hub disconnected")
		case <-b.Done():
			return errors.New("Codex disconnected")
		case ev := <-b.Events():
			if !announced {
				// Only events newer than the first complete snapshot need replay.
				// Retain a bounded tail while continuously draining the adapter.
				if len(initialEvents) == 256 {
					droppedInitial = initialEvents[0].Sequence
					copy(initialEvents, initialEvents[1:])
					initialEvents = initialEvents[:255]
				}
				initialEvents = append(initialEvents, ev)
				continue
			}
			if ev.Epoch != epoch {
				return errors.New("Codex event epoch changed")
			}
			if ev.Sequence <= forwarded {
				continue
			}
			p.Enqueue(protocol.Message{Type: "event", Event: &ev})
			forwarded = ev.Sequence
		case <-heartbeat.C:
			m.LastSeen = time.Now().UTC()
			p.Enqueue(protocol.Message{Type: "heartbeat", Machine: machineCopy(m)})
		case <-refresh.C:
			requestSnapshot()
		case <-retry.C:
			requestSnapshot()
		case result := <-refreshed:
			busy = false
			m.Freshness.SnapshotMS = result.ms
			if result.epoch != epoch {
				return errors.New("Codex epoch changed")
			}
			if result.err != nil {
				if ctx.Err() != nil {
					return ctx.Err()
				}
				// Reachable Relay with incomplete Codex state is Degraded, not
				// Offline. Retain the socket and retry without a reconnect storm.
				m.Status = protocol.Degraded
				revision++
				p.Enqueue(protocol.Message{Version: protocol.Version, Type: "announce", SnapshotRevision: revision, Machine: machineCopy(m), Epoch: epoch, Sequence: forwarded})
				delay := backoff(syncFailures, cfg.retryMin)
				syncFailures++
				retry.Reset(delay)
				slog.Warn("Codex synchronization delayed", "machine", m.ID, "reason", codex.SnapshotFailureReason(result.err), "snapshot_ms", result.ms, "retry_ms", delay.Milliseconds())
				continue
			}
			if announced && result.watermark < forwarded {
				// Live events already advanced canonical state beyond this read.
				// Never publish older metadata over them; take a new snapshot.
				retry.Reset(50 * time.Millisecond)
				continue
			}
			if !announced && droppedInitial > result.watermark {
				return errors.New("initial event replay capacity exceeded")
			}
			// Flush all events covered by the snapshot before its watermark.
			// The adapter cursor promises these events have already been emitted.
			if announced {
				for forwarded < result.watermark {
					select {
					case ev := <-b.Events():
						if ev.Epoch != epoch {
							return errors.New("Codex event epoch changed")
						}
						if ev.Sequence <= forwarded {
							continue
						}
						p.Enqueue(protocol.Message{Type: "event", Event: &ev})
						forwarded = ev.Sequence
					case <-ctx.Done():
						return ctx.Err()
					case <-p.Done:
						return errors.New("Hub disconnected")
					case <-b.Done():
						return errors.New("Codex disconnected")
					}
				}
			}
			watermark = result.watermark
			m.Status = protocol.Online
			m.LastSeen = time.Now().UTC()
			revision++
			p.Enqueue(protocol.Message{Version: protocol.Version, Type: "announce", SnapshotRevision: revision, Machine: machineCopy(m), Sessions: result.sessions, Requests: result.requests, Epoch: epoch, Sequence: watermark})
			if !announced {
				forwarded = watermark
				for _, ev := range initialEvents {
					if ev.Epoch != epoch {
						return errors.New("Codex event epoch changed")
					}
					if ev.Sequence <= forwarded {
						continue
					}
					p.Enqueue(protocol.Message{Type: "event", Event: &ev})
					forwarded = ev.Sequence
				}
				initialEvents = nil
				announced = true
			}
			syncFailures = 0
			retry.Stop()
			select {
			case accountRefresh <- struct{}{}:
			default:
			}
		}
	}
}

// Queued messages own their metadata; the writer runs concurrently with refresh.
func machineCopy(m protocol.Machine) *protocol.Machine { return &m }
