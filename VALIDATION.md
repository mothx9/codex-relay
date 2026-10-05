# Validation record — v0.1.0-rc.1

Performed 2026-10-04 on Exon, Linux amd64, with Codex CLI/shared daemon **0.160.0**, Go **1.27.0-X:nodwarf5**, and system Chromium driven by temporary Playwright tooling outside the repository. CI uses stable Go 1.27.x and builds the three release targets. Neither the hub nor agent requires Node. These measurements are not Zima measurements.

## Real execution

Started the actual Go hub on localhost:8787, enrolled a distinct validation agent, connected to the already-running shared Codex daemon, and opened the embedded PWA in Chromium at desktop and 390×844 mobile sizes. Fleet enumeration returned 225 real threads. Only isolated validation threads received commands; no unrelated local work or networking configuration was changed.

| v0.1 acceptance flow | Evidence/status |
| --- | --- |
| 1–4: hub, connected agent, actual Codex, session in PWA | Passed against real daemon and browser. |
| 5: WORKING/READY/NEEDS_YOU | Passed: real chat, approval and structured-input turns. |
| 6–9: open, send, reach same thread, live response | Passed. Unique marker and a newly received completion event prevented prior history from satisfying the assertion. |
| 10: no transcript persistence | Passed store canary tests; own real conversation markers absent from DB, WAL, SHM and retained Relay test logs. Browser localStorage had zero entries; Service Worker cached no API responses. |
| 11–12: pending request and operator resolution | Passed real accept-once approval and Alpha/Beta structured input. A request declined from the other client disappeared from Relay. |
| 13–14: receive push on iPhone, tap into session | **Pending physical acceptance.** Real headless Chromium registration was denied by its push/permission environment. No fabricated subscription or delivery is claimed. |
| 15: agent restart | Passed. Fresh snapshot/control recovered in 230 ms in the recorded run. A message after recovery reached real Codex. |
| 16: hub restart | Passed. Agent reannounced, browser reconnected and its login survived. Recorded recovery: 1014 ms. |
| 17: tests | `go test ./...`, `go test -race ./...`, gofmt and `go vet ./...` pass. |
| 18: public updated repository | Public repository and incremental commits pushed; CI tests and all three builds pass. |

**This is a release candidate, not a declaration that the complete v0.1 definition of done has passed.** Physical iPhone notification delivery/tap is the remaining end-to-end acceptance gap.

Additional real controls: steering while Codex ran a harmless seven-second command; native queue add followed by automatic next turn and response; bounded context fetched from the true thread; shared-second-client pending replay/resolution. Optional discovery and real round-trip tests passed. The latter creates a fresh thread, primes its first rollout, attaches a second client, starts a small turn, observes streaming/completion, and archives that test thread.

Real daemon restart was deliberately not performed while it served unrelated work. Fake backend restart verifies a new connection epoch, re-enumeration, and removal of obsolete pending requests. Agent/Hub process restarts were real. Physical MacBook sleep/wake and ARM/macOS service execution have not been tested.

## Measured resources and latency

The measurement used `/proc/<pid>/status` VmRSS and process CPU tick deltas over a 30-second quiet window, with 225 session metadata records, one agent and no operator commands. RSS excludes Codex, browser, build/test tools and the OS page cache. CPU tick resolution was 10 ms; zero ticks is not a promise of literally zero CPU forever.

| Measurement | Observed |
| --- | --- |
| Hub RSS | 21,668 KiB = **21.16 MiB** |
| Agent RSS | 21,404 KiB = **20.90 MiB** |
| Hub/Agent quiet CPU | No additional CPU ticks in either process during 30 seconds. |
| SQLite main DB | 212,992 bytes |
| SQLite WAL / SHM | 869,352 / 32,768 bytes |
| DB+WAL+SHM growth in quiet window | **0 bytes** |
| Local live-event arrival | 15 events; timestamp-to-browser deltas −0.30…2.35 ms. Browser clock resolution is approximately 1 ms; the negative sub-ms sample is quantization. Treat this as ≤3 ms observed on loopback, not a network latency benchmark. |
| One unique no-tools reply | 3668 ms from UI send to observed completion, including Codex/model time. |

A previous 30-second window overlapped UI activity: main DB+WAL+SHM grew from 801,992 to 876,152 bytes (+74,160). That is WAL/metadata/audit growth, not stored chat. Rows in the quiet-window DB: 1 machine, 225 sessions, 0 pending, 1 agent token hash, 13 operator sessions, 0 push subscriptions, 9 notification dedupe records and 51 audit records. SQL audit/dedupe retention, session limits and checkpointed WAL bound ongoing storage use; these short measurements do not prove months of unattended operation.

## Automated verification

Account-free tests use both a fake JSON-RPC app-server transport and a fake backend through the stable adapter interface:

- Canonical status normalization, ID/UTF-8 clipping, start/steer/queue/interrupt routing and bounded recent retrieval.
- Pending command/file/permissions/input/MCP response shapes, one-shot responses, missing-context rejection and resolution from another client.
- Agent reconnect, Hub restart with the same SQLite file/address, Codex-backend restart and snapshot rehydration.
- WebSocket subscribers, auth/origin failures, token revocation, duplicate/reordered events and reconnect watermarks.
- Bounded RAM buffers, TTL/drop behavior, SQLite tokens/metadata, absent transcript canary, audit and dedupe retention.
- Real Web Push AES128GCM payload encryption, VAPID JWT, privacy, deep-link/tag payload, notification dedupe, expired subscription removal and endpoint allowlisting through an injected transport. This verifies protocol generation, not delivery to Apple/iPhone.

Cross-builds pass for `linux/amd64`, `linux/arm64`, `darwin/arm64`, with CGO disabled. Linux release binary is executed locally. systemd user unit syntax and launchd plist XML were validated; the installer supports no-write dry runs. Target services have not been installed on remote machines.

## Reproduce

```sh
make check
make cross
RELAY_REAL_CODEX=1 go test ./internal/codex -run TestRealCodexDiscovery -v
RELAY_REAL_CODEX_TURN=1 go test ./internal/codex -run TestRealCodexRoundTrip -v
```

The optional turn test consumes two small Codex turns and needs a signed-in running shared daemon. Do not run it automatically in CI.

To complete physical push acceptance: deploy behind an existing HTTPS origin, install the PWA on an iPhone Home Screen, enable Web Push through the notification button, close the app, provoke a real request and tap its notification. Verify the session route and authenticated contextual decision. Follow [DEPLOYMENT.md](DEPLOYMENT.md).

The supplied Zima SSH alias timed out through both its configured Tailscale address and known LAN address; Tailscale reported the peer offline at the check. No Wi-Fi, routing, firewall, VPN or NetworkManager setting was changed. A current reachable SSH address and an iPhone-reachable HTTPS origin are needed for that remote acceptance step.

## 2026-10-05: startup/login correction — rc.2

A retained rc.1 validation hub occupied localhost:8787 while a new invocation created a different bootstrap token in `.relay/hub`. The new invocation failed to bind, but had already logged “hub ready”. The operator copied the new token while the browser reached the old process, causing a genuine authentication rejection. The retained test processes were stopped, the user's hub/data directory started, and its existing token verified with a real HTTP 200 login/logout. EXON authenticated and reannounced through WebSocket.

Startup now reserves the listening socket before creating state or announcing readiness, and validates a direct-TLS certificate before startup. A regression test verifies that an occupied port creates no credentials/state directory. Login accepts surrounding clipboard whitespace while a changed token remains rejected. The unauthenticated UI labels its state “Accesso richiesto” instead of claiming an offline reconnect. These corrections do not bypass authentication or rotate the user's credentials.
