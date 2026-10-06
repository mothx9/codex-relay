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
	if d > time.Minute {
		d = time.Minute
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
	machine := protocol.Machine{ID: cfg.MachineID, Name: cfg.Name, Status: protocol.Online, CodexVersion: version, Adapter: "shared"}
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
			p := protocol.NewPeer(conn)
			go p.WriteLoop(ctx)
			if backend == nil {
				m := machine
				m.Status = protocol.Degraded
				m.LastSeen = time.Now().UTC()
				p.Enqueue(protocol.Message{Version: protocol.Version, Type: "announce", Machine: &m, Epoch: protocol.ID()})
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
				attempt = 0
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
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	sessions, requests, e := b.Snapshot(ctx)
	if e != nil {
		return e
	}
	epoch, watermark := b.Cursor()
	m.LastSeen = time.Now().UTC()
	if reader, ok := b.(interface {
		Account(context.Context) *protocol.Account
	}); ok {
		m.Account = reader.Account(ctx)
	}
	p.Enqueue(protocol.Message{Version: protocol.Version, Type: "announce", Machine: &m, Sessions: sessions, Requests: requests, Epoch: epoch, Sequence: watermark})
	commands := make(chan protocol.Command, 32)
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
			select {
			case commands <- *msg.Command:
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
				if cmd.Kind != "history" {
					cache[cmd.ID] = r
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
	heartbeat := time.NewTicker(25 * time.Second)
	defer heartbeat.Stop()
	refresh := time.NewTicker(2 * time.Minute)
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
			if ev.Epoch == epoch && ev.Sequence <= watermark {
				continue
			}
			p.Enqueue(protocol.Message{Type: "event", Event: &ev})
		case <-heartbeat.C:
			m.LastSeen = time.Now().UTC()
			p.Enqueue(protocol.Message{Type: "heartbeat", Machine: &m})
		case <-refresh.C:
			sessions, requests, e = b.Snapshot(ctx)
			if e != nil {
				return e
			}
			epoch, watermark = b.Cursor()
			p.Enqueue(protocol.Message{Type: "announce", Machine: &m, Sessions: sessions, Requests: requests, Epoch: epoch, Sequence: watermark})
		}
	}
}
