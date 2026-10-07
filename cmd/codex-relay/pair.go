package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Desktop creates a code; a new agent redeems it directly into a 0600 file.
func pairingCommand(ctx context.Context, args []string) error {
	fs := flags("pair")
	hubURL := fs.String("hub-url", "", "HTTPS Hub origin")
	data := fs.String("data-dir", ".relay/hub", "Hub private directory (code creation only)")
	kind := fs.String("kind", "operator", "operator or agent")
	name := fs.String("name", "iPhone", "device display name")
	machine := fs.String("machine", "", "machine ID for agent enrollment")
	code := fs.String("code", "", "redeem one-time code for an agent (use --code-file to avoid shell history)")
	codeStdin := fs.Bool("code-stdin", false, "read the one-time agent code from stdin, keeping it out of shell history")
	codeFile := fs.String("code-file", "", "0600 file containing the one-time agent pairing code")
	out := fs.String("out", "", "agent token destination, created exclusively with mode 0600")
	if err := fs.Parse(args); err != nil {
		return err
	}
	sources := 0
	if *code != "" {
		sources++
	}
	if *codeFile != "" {
		sources++
	}
	if *codeStdin {
		sources++
	}
	if sources > 1 {
		return errors.New("choose only one of --code, --code-file or --code-stdin")
	}
	if *codeStdin {
		fmt.Fprint(os.Stderr, "One-time agent pairing code: ")
		type input struct {
			value string
			err   error
		}
		result := make(chan input, 1)
		go func() { value, err := readPairingCode(os.Stdin); result <- input{value, err} }()
		select {
		case <-ctx.Done():
			return ctx.Err()
		case read := <-result:
			if read.err != nil {
				return read.err
			}
			*code = read.value
		}
	}
	u, err := url.Parse(*hubURL)
	if err != nil || u.Scheme != "https" || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || (u.Path != "" && u.Path != "/") {
		return errors.New("--hub-url requires an HTTPS origin")
	}
	origin := u.Scheme + "://" + u.Host
	jar, _ := cookiejar.New(nil)
	client := &http.Client{Timeout: 15 * time.Second, Jar: jar, CheckRedirect: func(*http.Request, []*http.Request) error { return errors.New("pairing redirects disabled") }}
	post := func(path string, value any, result any) error {
		body, _ := json.Marshal(value)
		req, err := http.NewRequestWithContext(ctx, "POST", origin+path, bytes.NewReader(body))
		if err != nil {
			return err
		}
		req.Header.Set("Origin", origin)
		req.Header.Set("X-Relay-CSRF", "1")
		req.Header.Set("Content-Type", "application/json")
		resp, err := client.Do(req)
		if err != nil {
			return errors.New("Hub unavailable; check HTTPS URL and connectivity")
		}
		defer resp.Body.Close()
		if resp.StatusCode != 200 {
			return fmt.Errorf("pairing rejected (HTTP %d)", resp.StatusCode)
		}
		return json.NewDecoder(io.LimitReader(resp.Body, 8192)).Decode(result)
	}
	if *codeFile != "" {
		b, err := secret(*codeFile)
		if err != nil {
			return err
		}
		*code = strings.TrimSpace(string(b))
	}
	if *code != "" {
		if *kind != "agent" || *out == "" {
			return errors.New("redemption requires --kind agent --out FILE")
		}
		normalized, err := readPairingCode(strings.NewReader(*code))
		if err != nil {
			return err
		}
		*code = normalized
		// Keep the exclusive file descriptor while consuming the one-shot code.
		// A path replacement cannot redirect the credential write to another file.
		if err = os.MkdirAll(filepath.Dir(*out), 0700); err != nil {
			return err
		}
		reserved, err := os.OpenFile(*out, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
		if err != nil {
			return err
		}
		defer reserved.Close()
		var response struct {
			ID    string `json:"id"`
			Token string `json:"token"`
		}
		if err = post("/api/pairing/exchange", map[string]string{"code": *code, "kind": "agent"}, &response); err != nil {
			_ = os.Remove(*out)
			return err
		}
		if *machine != "" && response.ID != *machine {
			_ = os.Remove(*out)
			return errors.New("pairing machine differs; credential was not activated locally")
		}
		if len(response.Token) < 32 {
			_ = os.Remove(*out)
			return errors.New("invalid enrollment credential")
		}
		if _, err = reserved.Write([]byte(response.Token)); err != nil {
			return err
		}
		if err = reserved.Sync(); err != nil {
			return err
		}
		fmt.Println("Agent enrolled:", response.ID, "credential saved securely to:", *out)
		return nil
	}
	admin, err := secret(filepath.Join(*data, "admin.token"))
	if err != nil {
		return err
	}
	var login map[string]bool
	if err = post("/api/login", map[string]string{"token": strings.TrimSpace(string(admin))}, &login); err != nil {
		return err
	}
	// The short-lived bootstrap session is not a controller enrollment.
	defer func() { var result map[string]bool; _ = post("/api/logout", map[string]string{}, &result) }()
	var response struct {
		Code      string    `json:"code"`
		ExpiresAt time.Time `json:"expires_at"`
	}
	if err = post("/api/pairing/code", map[string]string{"kind": *kind, "name": *name, "machine": *machine}, &response); err != nil {
		return err
	}
	if _, err := readPairingCode(strings.NewReader(response.Code)); err != nil || len(response.Code) != 8 {
		return errors.New("Hub returned an invalid pairing code")
	}
	fmt.Printf("Hub: %s\nOne-time code: %s %s\nExpires: %s\n", origin, response.Code[:4], response.Code[4:], response.ExpiresAt.Local().Format(time.RFC3339))
	if *kind == "operator" {
		fmt.Println("Open Codex Relay on iPhone and enter this Hub URL and code. Never enter the admin token.")
	} else {
		fmt.Println("On the new machine, run codex-relay pair --kind agent --hub-url URL --code-stdin --out FILE.")
	}
	return nil
}

func readPairingCode(reader io.Reader) (string, error) {
	line, err := bufio.NewReader(io.LimitReader(reader, 64)).ReadString('\n')
	if err != nil && !errors.Is(err, io.EOF) {
		return "", errors.New("could not read pairing code")
	}
	if len(line) >= 64 {
		return "", errors.New("pairing input is too long")
	}
	value := strings.ReplaceAll(strings.TrimSpace(line), " ", "")
	if len(value) != 8 {
		return "", errors.New("enter the 8-digit one-time pairing code")
	}
	for _, c := range value {
		if c < '0' || c > '9' {
			return "", errors.New("pairing code must contain 8 digits")
		}
	}
	return value, nil
}
