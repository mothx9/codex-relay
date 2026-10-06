package main

import (
	"context"
	"crypto/tls"
	"database/sql"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"github.com/mothx9/codex-relay/internal/agent"
	"github.com/mothx9/codex-relay/internal/codex"
	"github.com/mothx9/codex-relay/internal/hub"
	"github.com/mothx9/codex-relay/internal/protocol"
	"github.com/mothx9/codex-relay/internal/push"
	"github.com/mothx9/codex-relay/internal/store"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"syscall"
	"time"
)

var version = "0.1.0-rc.4"

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	if e := run(ctx, os.Args[1:]); e != nil && !errors.Is(e, context.Canceled) {
		slog.Error(e.Error())
		os.Exit(1)
	}
}
func run(ctx context.Context, args []string) error {
	if len(args) == 0 {
		return errors.New("usage: codex-relay hub|agent|doctor|version|token|pair")
	}
	switch args[0] {
	case "version":
		fmt.Println("codex-relay", version, runtime.GOOS+"/"+runtime.GOARCH)
		return nil
	case "hub":
		return runHub(ctx, args[1:])
	case "agent":
		return runAgent(ctx, args[1:])
	case "doctor":
		return doctor(ctx, args[1:])
	case "token":
		return tokens(args[1:])
	case "pair":
		return pairingCommand(ctx, args[1:])
	case "help", "--help", "-h":
		fmt.Println("codex-relay hub|agent|doctor|version|token|pair\nUse <command> --help for options.")
		return nil
	default:
		return errors.New("unknown command")
	}
}
func flags(name string) *flag.FlagSet { return flag.NewFlagSet(name, flag.ContinueOnError) }
func secret(path string) ([]byte, error) {
	info, e := os.Lstat(path)
	if e != nil {
		return nil, e
	}
	if !info.Mode().IsRegular() || info.Mode().Perm()&0077 != 0 {
		return nil, fmt.Errorf("secret must be a regular file with mode 0600: %s", path)
	}
	return os.ReadFile(path)
}
func createSecret(path string, b []byte) error {
	if e := os.MkdirAll(filepath.Dir(path), 0700); e != nil {
		return e
	}
	f, e := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if e != nil {
		return e
	}
	_, e = f.Write(b)
	if e != nil {
		_ = f.Close()
		_ = os.Remove(path)
		return e
	}
	return f.Close()
}
func ensureSecret(path string, generate func() ([]byte, error)) ([]byte, error) {
	b, e := secret(path)
	if e == nil {
		return b, nil
	}
	if !os.IsNotExist(e) {
		return nil, e
	}
	b, e = generate()
	if e != nil {
		return nil, e
	}
	if e = createSecret(path, b); e != nil {
		return nil, e
	}
	return b, nil
}
func runHub(ctx context.Context, args []string) error {
	fs := flags("hub")
	listen := fs.String("listen", "127.0.0.1:8787", "listen address")
	public := fs.String("public-url", "http://127.0.0.1:8787", "browser-facing HTTP(S) origin")
	data := fs.String("data-dir", ".relay/hub", "private metadata/secrets directory")
	insecure := fs.Bool("insecure-http", false, "explicitly allow unencrypted HTTP beyond loopback (development only)")
	cert := fs.String("tls-cert", "", "TLS certificate file")
	key := fs.String("tls-key", "", "TLS private key file")
	subject := fs.String("push-subject", "", "VAPID contact: mailto:... or https://...")
	disablePush := fs.Bool("disable-push", false, "disable Web Push")
	apnsConfig := fs.String("apns-config", "", "0600 APNs JSON configuration for native iPhone push")
	if e := fs.Parse(args); e != nil {
		return e
	}
	host, _, e := net.SplitHostPort(*listen)
	if e != nil {
		return e
	}
	ip := net.ParseIP(host)
	loopback := host == "localhost" || (ip != nil && ip.IsLoopback())
	if (*cert == "") != (*key == "") {
		return errors.New("both TLS files are required")
	}
	if !loopback && *cert == "" && !*insecure {
		return errors.New("non-loopback HTTP requires --insecure-http or direct TLS; reverse proxies should use loopback")
	}
	u, e := url.Parse(*public)
	if e != nil {
		return e
	}
	publicIP := net.ParseIP(u.Hostname())
	publicLoopback := u.Hostname() == "localhost" || (publicIP != nil && publicIP.IsLoopback())
	if u.Scheme == "http" && !publicLoopback && !*insecure {
		return errors.New("production public URL requires HTTPS")
	}
	if *cert != "" && u.Scheme != "https" {
		return errors.New("TLS requires an HTTPS public URL")
	}
	var tlsConfig *tls.Config
	if *cert != "" {
		pair, err := tls.LoadX509KeyPair(*cert, *key)
		if err != nil {
			return err
		}
		tlsConfig = &tls.Config{Certificates: []tls.Certificate{pair}, MinVersion: tls.VersionTLS12}
	}
	// Reserve the listener before creating credentials or announcing readiness.
	listener, e := net.Listen("tcp", *listen)
	if e != nil {
		return fmt.Errorf("cannot listen on %s: %w", *listen, e)
	}
	defer listener.Close()
	admin, e := ensureSecret(filepath.Join(*data, "admin.token"), func() ([]byte, error) { return []byte(protocol.ID() + protocol.ID()), nil })
	if e != nil {
		return e
	}
	keys := push.Keys{}
	if !*disablePush {
		raw, e := ensureSecret(filepath.Join(*data, "vapid.secret"), func() ([]byte, error) {
			k, e := push.Generate()
			if e != nil {
				return nil, e
			}
			return json.Marshal(k)
		})
		if e != nil {
			return e
		}
		if e = json.Unmarshal(raw, &keys); e != nil {
			return e
		}
	}
	if *subject == "" {
		*subject = "https://github.com/mothx9/codex-relay"
	}
	var nativePush *push.APNS
	if *apnsConfig != "" {
		raw, err := secret(*apnsConfig)
		if err != nil {
			return err
		}
		var config push.APNSConfig
		if err = json.Unmarshal(raw, &config); err != nil {
			return errors.New("invalid APNs configuration")
		}
		if !filepath.IsAbs(config.KeyFile) {
			config.KeyFile = filepath.Join(filepath.Dir(*apnsConfig), config.KeyFile)
		}
		key, err := secret(config.KeyFile)
		if err != nil {
			return err
		}
		nativePush, err = push.NewAPNS(config, key)
		if err != nil {
			return err
		}
	}
	if !strings.HasPrefix(*subject, "mailto:") && !strings.HasPrefix(*subject, "https://") {
		return errors.New("VAPID subject must be mailto: or https://")
	}
	s, e := store.Open(filepath.Join(*data, "relay.db"))
	if e != nil {
		return e
	}
	defer s.Close()
	h, e := hub.New(s, hub.Config{PublicURL: *public, AdminToken: strings.TrimSpace(string(admin)), PushKeys: keys, PushSubject: *subject, APNS: nativePush})
	if e != nil {
		return e
	}
	defer h.Close()
	srv := &http.Server{Addr: *listen, TLSConfig: tlsConfig, Handler: h.Handler(), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second, WriteTimeout: 30 * time.Second, IdleTimeout: 90 * time.Second, MaxHeaderBytes: 16 << 10}
	ended := make(chan error, 1)
	go func() {
		if *cert != "" {
			ended <- srv.ServeTLS(listener, "", "")
		} else {
			ended <- srv.Serve(listener)
		}
	}()
	go h.Run(ctx)
	adminPath, _ := filepath.Abs(filepath.Join(*data, "admin.token"))
	slog.Info("hub ready", "listen", listener.Addr().String(), "public_url", *public, "admin_token_file", adminPath)
	select {
	case <-ctx.Done():
		stop, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = srv.Shutdown(stop)
		return ctx.Err()
	case e := <-ended:
		if e == http.ErrServerClosed {
			return nil
		}
		return e
	}
}
func codexFlags(fs *flag.FlagSet, c *codex.Config) {
	fs.StringVar(&c.Binary, "codex", "codex", "Codex executable path")
	fs.StringVar(&c.Socket, "codex-socket", "", "shared daemon Unix socket (default CODEX_HOME)")
	fs.StringVar(&c.Endpoint, "codex-url", "", "explicit local Codex WebSocket endpoint")
	fs.StringVar(&c.TokenFile, "codex-token-file", "", "local app-server bearer token; never forwarded")
	fs.BoolVar(&c.Private, "private-codex", false, "supervise a private stdio app-server; independent sessions remain read-only")
}
func runAgent(ctx context.Context, args []string) error {
	fs := flags("agent")
	host, _ := os.Hostname()
	c := agent.Config{Version: version}
	fs.StringVar(&c.HubURL, "hub-url", "", "Hub HTTP(S) URL")
	fs.StringVar(&c.MachineID, "machine", host, "registered machine ID")
	fs.StringVar(&c.Name, "name", host, "display name")
	fs.StringVar(&c.TokenFile, "token-file", "", "machine-specific Relay token file (0600)")
	fs.BoolVar(&c.Insecure, "insecure-http", false, "allow plaintext development Hub connection")
	codexFlags(fs, &c.Codex)
	if e := fs.Parse(args); e != nil {
		return e
	}
	if !regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}$`).MatchString(c.MachineID) {
		return errors.New("machine ID: 1-64 letters, digits, underscore or dash")
	}
	if _, e := secret(c.TokenFile); e != nil {
		return e
	}
	if c.Codex.TokenFile != "" {
		if _, e := secret(c.Codex.TokenFile); e != nil {
			return e
		}
	}
	return agent.Run(ctx, c)
}
func tokens(args []string) error {
	if len(args) == 0 {
		return errors.New("usage: token add|revoke --machine ID --data-dir DIR [--out FILE]")
	}
	fs := flags("token " + args[0])
	machine := fs.String("machine", "", "machine ID")
	data := fs.String("data-dir", ".relay/hub", "Hub data directory")
	out := fs.String("out", "", "new token output path, mode 0600")
	if e := fs.Parse(args[1:]); e != nil {
		return e
	}
	if !regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}$`).MatchString(*machine) {
		return errors.New("invalid machine ID")
	}
	s, e := store.Open(filepath.Join(*data, "relay.db"))
	if e != nil {
		return e
	}
	defer s.Close()
	switch args[0] {
	case "add":
		if *out == "" {
			return errors.New("--out required; tokens are never printed")
		}
		token := protocol.ID() + protocol.ID()
		if e = createSecret(*out, []byte(token)); e != nil {
			return e
		}
		if e = s.Token(*machine, token); e != nil {
			_ = os.Remove(*out)
			return e
		}
		fmt.Println("Machine token written to", *out)
	case "revoke":
		if e = s.Revoke(*machine); e != nil {
			return e
		}
		fmt.Println("Machine revoked:", *machine)
	default:
		return errors.New("unknown token action")
	}
	return nil
}
func doctor(ctx context.Context, args []string) error {
	fs := flags("doctor")
	hubURL := fs.String("hub-url", "", "optional Hub URL")
	insecure := fs.Bool("insecure-http", false, "explicitly allow plaintext diagnostics beyond loopback")
	data := fs.String("data-dir", ".relay/hub", "Hub metadata directory")
	tokenFile := fs.String("token-file", "", "optional Relay machine token")
	machine := fs.String("machine", "", "registered machine ID")
	c := codex.Config{MachineID: "doctor"}
	codexFlags(fs, &c)
	if e := fs.Parse(args); e != nil {
		return e
	}
	client := &http.Client{Timeout: 5 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error {
		return http.ErrUseLastResponse
	}}
	if *hubURL != "" {
		u, err := url.Parse(*hubURL)
		if err != nil || u.Host == "" || u.User != nil || (u.Path != "" && u.Path != "/") || u.RawQuery != "" || u.Fragment != "" || (u.Scheme != "http" && u.Scheme != "https") {
			return errors.New("doctor requires a valid HTTP(S) Hub origin without credentials or a subpath")
		}
		ip := net.ParseIP(u.Hostname())
		loopback := strings.EqualFold(u.Hostname(), "localhost") || (ip != nil && ip.IsLoopback())
		if u.Scheme == "http" && !loopback && !*insecure {
			return errors.New("non-loopback Hub diagnostics require HTTPS or explicit --insecure-http")
		}
	}
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	v, e := codex.Version(ctx, c.Binary)
	codexStatus := "unavailable"
	sessions := 0
	if e == nil && !c.Private {
		a, err := codex.Open(ctx, c)
		if err == nil {
			ss, _, err := a.Snapshot(ctx)
			if err == nil {
				codexStatus = "connected"
				sessions = len(ss)
			} else {
				codexStatus = "snapshot failed"
			}
			a.Close()
		}
	}
	dbStatus := "absent"
	dbBytes := int64(0)
	path := filepath.Join(*data, "relay.db")
	if info, e := os.Stat(path); e == nil {
		dbBytes = info.Size()
		abs, _ := filepath.Abs(path)
		uri := (&url.URL{Scheme: "file", Path: abs}).String() + "?mode=ro"
		db, e := sql.Open("sqlite", uri)
		if e == nil {
			var result string
			e = db.QueryRow("PRAGMA quick_check").Scan(&result)
			if e == nil {
				dbStatus = result
			} else {
				dbStatus = "error"
			}
			db.Close()
		}
	}
	pushStatus := "not configured"
	if _, e := os.Stat(filepath.Join(*data, "vapid.secret")); e == nil {
		pushStatus = "VAPID key file present"
	}
	reachability := "not checked"
	wsState := any("not checked")
	if *hubURL != "" {
		resp, e := client.Get(strings.TrimRight(*hubURL, "/") + "/healthz")
		if e == nil {
			reachability = resp.Status
			resp.Body.Close()
		} else {
			reachability = "unreachable"
		}
		if *tokenFile != "" && *machine != "" {
			b, e := secret(*tokenFile)
			if e != nil {
				return e
			}
			r, e := http.NewRequestWithContext(ctx, "GET", strings.TrimRight(*hubURL, "/")+"/api/agent/status", nil)
			if e != nil {
				return e
			}
			r.Header.Set("Authorization", "Bearer "+strings.TrimSpace(string(b)))
			r.Header.Set("X-Relay-Machine", *machine)
			resp, e := client.Do(r)
			if e == nil {
				if resp.StatusCode == 200 {
					var state any
					if json.NewDecoder(resp.Body).Decode(&state) == nil {
						wsState = state
					}
				} else {
					wsState = resp.Status
				}
				resp.Body.Close()
			}
		}
	}
	var mem runtime.MemStats
	runtime.ReadMemStats(&mem)
	return json.NewEncoder(os.Stdout).Encode(map[string]any{"version": version, "go": runtime.Version(), "platform": runtime.GOOS + "/" + runtime.GOARCH, "codex_version": v, "codex_adapter": codexStatus, "sessions": sessions, "hub": reachability, "websocket": wsState, "database": dbStatus, "database_bytes": dbBytes, "push": pushStatus, "doctor_heap_bytes": mem.HeapAlloc, "goroutines": runtime.NumGoroutine()})
}
