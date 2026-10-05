package codex

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/gorilla/websocket"
	"github.com/mothx9/codex-relay/internal/protocol"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type rpcMessage struct {
	ID     json.RawMessage `json:"id,omitempty"`
	Method string          `json:"method,omitempty"`
	Params json.RawMessage `json:"params,omitempty"`
	Result json.RawMessage `json:"result,omitempty"`
	Error  *struct {
		Code    int    `json:"code"`
		Message string `json:"message"`
	} `json:"error,omitempty"`
}
type rpcError struct {
	Code    int
	Message string
}

func (e *rpcError) Error() string { return fmt.Sprintf("Codex RPC rejected request (%d)", e.Code) }

type transport interface {
	Read() (rpcMessage, error)
	Write(any) error
	Close() error
}
type wsTransport struct{ c *websocket.Conn }

func (w *wsTransport) Read() (rpcMessage, error) {
	var m rpcMessage
	e := w.c.ReadJSON(&m)
	return m, e
}
func (w *wsTransport) Write(v any) error {
	_ = w.c.SetWriteDeadline(time.Now().Add(10 * time.Second))
	return w.c.WriteJSON(v)
}
func (w *wsTransport) Close() error { return w.c.Close() }

type stdioTransport struct {
	cmd *exec.Cmd
	in  io.WriteCloser
	out *bufio.Scanner
}

func (s *stdioTransport) Read() (rpcMessage, error) {
	var m rpcMessage
	if !s.out.Scan() {
		if e := s.out.Err(); e != nil {
			return m, e
		}
		return m, io.EOF
	}
	e := json.Unmarshal(s.out.Bytes(), &m)
	return m, e
}
func (s *stdioTransport) Write(v any) error { return json.NewEncoder(s.in).Encode(v) }
func (s *stdioTransport) Close() error {
	_ = s.in.Close()
	if s.cmd.Process != nil {
		_ = s.cmd.Process.Kill()
	}
	return s.cmd.Wait()
}

type Adapter struct {
	cfg              Config
	t                transport
	mu               sync.Mutex
	writeMu          sync.Mutex
	calls            map[string]chan rpcMessage
	next             uint64
	events           chan protocol.Event
	done             chan struct{}
	once             sync.Once
	sessions         map[string]protocol.Session
	requests         map[string]pending
	items            map[string]protocol.Activity
	itemOrder        []string
	subscribed       map[string]bool
	epoch            string
	sequence         uint64
	snapshotSequence uint64
	queue            bool
	queueSignals     chan string
}
type pending struct {
	Request protocol.PendingRequest
	RawID   json.RawMessage
	Method  string
	Params  json.RawMessage
	Sent    bool
}

func Version(ctx context.Context, binary string) (string, error) {
	if binary == "" {
		binary = "codex"
	}
	b, e := exec.CommandContext(ctx, binary, "--version").Output()
	return strings.TrimSpace(string(b)), e
}
func Open(ctx context.Context, cfg Config) (*Adapter, error) {
	if cfg.Private && (cfg.Endpoint != "" || cfg.Socket != "") {
		return nil, errors.New("private app-server cannot be combined with a shared endpoint")
	}
	if cfg.Endpoint != "" {
		u, e := url.Parse(cfg.Endpoint)
		if e != nil || u.User != nil || (u.Scheme != "ws" && u.Scheme != "wss") {
			return nil, errors.New("invalid Codex WebSocket URL")
		}
		ip := net.ParseIP(u.Hostname())
		if u.Hostname() != "localhost" && (ip == nil || !ip.IsLoopback()) {
			return nil, errors.New("Codex TCP endpoint must be local loopback; use the Unix socket for the shared daemon")
		}
	}
	if cfg.Binary == "" {
		cfg.Binary = "codex"
	}
	var t transport
	if cfg.Private {
		cmd := exec.CommandContext(ctx, cfg.Binary, "app-server", "--listen", "stdio://")
		in, e := cmd.StdinPipe()
		if e != nil {
			return nil, e
		}
		out, e := cmd.StdoutPipe()
		if e != nil {
			return nil, e
		}
		// stderr may contain local sensitive context; it is deliberately not forwarded.
		if e = cmd.Start(); e != nil {
			return nil, e
		}
		scan := bufio.NewScanner(out)
		scan.Buffer(make([]byte, 4096), protocol.MaxMessage)
		t = &stdioTransport{cmd, in, scan}
	} else {
		d := websocket.Dialer{HandshakeTimeout: 10 * time.Second}
		endpoint := cfg.Endpoint
		if endpoint == "" {
			socket := cfg.Socket
			if socket == "" {
				home := os.Getenv("CODEX_HOME")
				if home == "" {
					u, e := os.UserHomeDir()
					if e != nil {
						return nil, e
					}
					home = filepath.Join(u, ".codex")
				}
				socket = filepath.Join(home, "app-server-control", "app-server-control.sock")
			}
			d.NetDialContext = func(ctx context.Context, _, _ string) (net.Conn, error) {
				return (&net.Dialer{}).DialContext(ctx, "unix", socket)
			}
			endpoint = "ws://localhost/"
		}
		h := http.Header{}
		if cfg.TokenFile != "" {
			b, e := os.ReadFile(cfg.TokenFile)
			if e != nil {
				return nil, e
			}
			h.Set("Authorization", "Bearer "+strings.TrimSpace(string(b)))
		}
		c, resp, e := d.DialContext(ctx, endpoint, h)
		if resp != nil && resp.Body != nil {
			_ = resp.Body.Close()
		}
		if e != nil {
			return nil, fmt.Errorf("Codex connection unavailable: %w", e)
		}
		c.SetReadLimit(protocol.MaxMessage)
		t = &wsTransport{c}
	}
	a := &Adapter{cfg: cfg, t: t, calls: map[string]chan rpcMessage{}, events: make(chan protocol.Event, 256), done: make(chan struct{}), sessions: map[string]protocol.Session{}, requests: map[string]pending{}, items: map[string]protocol.Activity{}, subscribed: map[string]bool{}, epoch: protocol.ID(), queue: true, queueSignals: make(chan string, 64)}
	go a.readLoop()
	if _, e := a.rpc(ctx, "initialize", map[string]any{"clientInfo": map[string]string{"name": "codex_relay", "title": "Codex Relay", "version": "0.1.0"}, "capabilities": map[string]any{"experimentalApi": true, "optOutNotificationMethods": []string{"item/reasoning/textDelta", "item/reasoning/summaryTextDelta", "thread/tokenUsage/updated"}}}); e != nil {
		a.Close()
		return nil, e
	}
	if e := a.write(map[string]any{"method": "initialized"}); e != nil {
		a.Close()
		return nil, e
	}
	go a.queueLoop()
	return a, nil
}
func (a *Adapter) Close()                { a.once.Do(func() { close(a.done); _ = a.t.Close() }) }
func (a *Adapter) Done() <-chan struct{} { return a.done }
func (a *Adapter) Cursor() (string, uint64) {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.epoch, a.snapshotSequence
}
func (a *Adapter) Events() <-chan protocol.Event { return a.events }
func (a *Adapter) write(v any) error             { a.writeMu.Lock(); defer a.writeMu.Unlock(); return a.t.Write(v) }
func (a *Adapter) rpc(ctx context.Context, method string, params any) (json.RawMessage, error) {
	ctx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()
	a.mu.Lock()
	a.next++
	id := fmt.Sprint(a.next)
	ch := make(chan rpcMessage, 1)
	a.calls[id] = ch
	a.mu.Unlock()
	defer func() { a.mu.Lock(); delete(a.calls, id); a.mu.Unlock() }()
	if e := a.write(map[string]any{"id": a.nextID(id), "method": method, "params": params}); e != nil {
		return nil, e
	}
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-a.done:
		return nil, errors.New("Codex disconnected")
	case m := <-ch:
		if m.Error != nil {
			return nil, &rpcError{Code: m.Error.Code, Message: m.Error.Message}
		}
		return m.Result, nil
	}
}
func (a *Adapter) nextID(id string) json.RawMessage { return json.RawMessage(id) }
func (a *Adapter) readLoop() {
	defer a.Close()
	for {
		m, e := a.t.Read()
		if e != nil {
			return
		}
		if m.Method == "" {
			a.mu.Lock()
			ch := a.calls[string(m.ID)]
			a.mu.Unlock()
			if ch != nil {
				ch <- m
			}
			continue
		}
		a.handle(m)
	}
}
func (a *Adapter) emit(e protocol.Event) {
	a.mu.Lock()
	a.sequence++
	e.Sequence = a.sequence
	e.Epoch = a.epoch
	e.ID = a.epoch + "/" + fmt.Sprint(a.sequence)
	a.mu.Unlock()
	e.MachineID = a.cfg.MachineID
	if e.Timestamp.IsZero() {
		e.Timestamp = time.Now().UTC()
	}
	select {
	case a.events <- e:
	case <-a.done:
	default:
		a.Close()
	} // loss of control events forces snapshot recovery.
}
