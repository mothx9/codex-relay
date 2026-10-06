package main

import (
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
	codeFile := fs.String("code-file", "", "0600 file containing the one-time agent pairing code")
	out := fs.String("out", "", "agent token destination, created exclusively with mode 0600")
	if err := fs.Parse(args); err != nil {
		return err
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
		// Reserve the file before consuming the one-shot code.
		if err = createSecret(*out, nil); err != nil {
			return err
		}
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
		if err = os.WriteFile(*out, []byte(response.Token), 0600); err != nil {
			return err
		}
		fmt.Println("Agent enrolled:", response.ID, "token file:", *out)
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
	var response struct {
		Code      string    `json:"code"`
		ExpiresAt time.Time `json:"expires_at"`
	}
	if err = post("/api/pairing/code", map[string]string{"kind": *kind, "name": *name, "machine": *machine}, &response); err != nil {
		return err
	}
	fmt.Printf("Hub: %s\nCodice monouso: %s %s\nScade: %s\n", origin, response.Code[:4], response.Code[4:], response.ExpiresAt.Local().Format(time.RFC3339))
	return nil
}
