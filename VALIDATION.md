# Validation record

## Current deployment checkpoint — 2026-10-05

Trusted Zima SSH is restored. Debian 12 (bookworm), Linux amd64, kernel 6.1.0-37-amd64 now reports `running` with zero failed units. A missing optional HDD was blocking boot; its fstab entry now has `nofail` and a bounded device timeout. Only the invalid legacy NFS entry was disabled. Existing root/data filesystems were not reformatted or repaired destructively; original configuration backups remain private on Zima.

The old Zima bridge/DHCP setup was announcing a conflicting LAN subnet. Both networkd DHCP and dnsmasq are now disabled, the old bridge/address/routes are absent, and there is no UDP 67 listener. NetworkManager owns Zima's ordinary DHCP client interfaces. These recovery changes were made on Zima only; Exon's network configuration was not modified during this recovery.

Actual Alfa: USB `0bda:0811`, AWUS036ACS / RTL8811AU. An initial rtw88 backport associated but produced firmware TX-report errors, packet loss and HTTPS timeouts. The alternative recommended in [Alfa's Linux support](https://docs.alfa.com.tw/Support/Linux/RTL8811AU/) was built from `morrownr/8821au-20210708` commit `1a819991f5b75e64dfcf922b96a6681f367cbba0`, installed as DKMS `rtl8821au/5.12.5.2`, and limited to 20 MHz with power saving disabled. The unused rtw88 backport was removed to avoid driver contention; its sources/configuration remain available for rollback on Zima. The profile and credentials are private, autoconnect is enabled, and Wi-Fi has primary route preference with Ethernet retained as fallback.

| Zima recovery check | Observed |
| --- | --- |
| Fresh SSH through Alfa Wi-Fi | Passed, trusted existing host key. |
| Wi-Fi → router, 20 packets | 20/20, zero loss; RTT min/avg/max 3.080 / 3.765 / 5.304 ms. |
| Wi-Fi → Exon, 20 packets | 20/20, zero loss; RTT min/avg/max 4.074 / 27.276 / 95.021 ms. |
| Wi-Fi DNS + HTTPS | HTTP 200; measured connect 58.740 ms, total 795.497 ms to GitHub in this sample. This is not Relay event latency. |
| Tailscale | Existing installation running, no health warnings in the latest check. |
| Hub artifact | rc.3 Linux amd64 executed; SHA256 matched the published artifact. |
| Persistent hub | Unit syntax verified; **inactive/disabled**, no bootstrap token/database generated. Linger enabled. |
| HTTPS ingress | Previously empty Serve mapping prepared persistently for the sole Zima loopback hub. Application/TLS acceptance awaits hub activation. |
| Ethernet unplug / reboot survival | Pending physical Ethernet removal and subsequent checks. |

This short Wi-Fi sample does not prove unattended stability. No Zima hub RAM/CPU, three-agent latency or iPhone push measurements are claimed yet. Spark currently responds through Tailscale; MacBook timed out on the latest SSH check. Canonical agent enrollment/control, hub recovery and physical iPhone push/tap remain pending. **The release remains rc.3.** Historical access-blocker entries below are superseded by this checkpoint.

## Historical MVP acceptance — v0.1.0-rc.1

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

**This historical MVP run was a release candidate, not complete v0.1 acceptance.** Its iPhone delivery/tap was not verified. The canonical multi-machine wave below adds further deployment acceptance requirements; this older local run does not satisfy them.

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

The rc.2 CI binaries were subsequently executed on the actual Linux ARM64 Spark and macOS ARM64 MacBook. `doctor` connected to each existing shared Codex 0.160.0 daemon and enumerated 78 and 85 sessions respectively. systemd/launchd installation dry runs succeeded on those real OS targets. This verifies native execution and adapter discovery, not yet their persistent connection to the fleet hub. Their distinct tokens and service installers were staged over authenticated SSH; service activation awaits an explicitly approved HTTPS ingress. No secret or machine-specific network configuration was committed.

## 2026-10-05: agent installation prerequisites

A copied Spark deployment command used a documentation URL and referenced an agent token that had only been staged, not transferred to its final path. The installer stopped before creating a systemd unit. This explains both the missing-token error and the subsequent missing-unit error; `linger` was already enabled and does not perform enrollment.

Deployment commands now require the real hub URL through `RELAY_HUB_URL` and explain the hub/token/transfer/install order. The installer rejects reserved documentation domains before modifying files, reports the missing token path and enrollment prerequisite, and offers Linux `--no-start` to install files without enabling or starting a unit.

Checked shell syntax, Linux unit rendering, three placeholder-domain failures and a missing-token failure. On the real Spark, installed the verified rc.2 ARM64 binary, copied its existing enrolled token to its final private path, and installed the unit with `--no-start`. `systemd-analyze --user verify` passed; systemd reported `loaded`, `inactive`, `disabled`. Token contents matched the current hub enrollment without displaying them. The installed binary's doctor, given the same absolute Codex path as the unit, connected to Codex 0.160.0 and found 78 actual sessions. This is a prepared installation, not a claim that Spark has connected to the hub; HTTPS activation remains pending.

## 2026-10-05: canonical controls and cutover acceptance

Installed Codex CLI/shared daemon **0.160.0**. Fresh schema inspection and isolated real queue experiments confirmed `clientUserMessageId` → queuedSubmission identity → canonical userMessage `clientId`, both in live item events and a later independent `thread/items/list` read. The observed `turn/started` had no items. See [DISCOVERY.md](DISCOVERY.md) for the exact protocol boundary.

Ran the actual embedded PWA in system Chromium through temporary Playwright tooling outside the repository, at **390×844**. The same authenticated local Exon validation hub/data directory was restarted during a queued native follow-up; bootstrap token remained stable. No Codex daemon or unrelated workload was restarted.

| Canonical control/recovery check | Observed result |
| --- | --- |
| READY submit → NEW TURN | Real `new_turn` command, daemon turn and live response. |
| WORKING default → FOLLOW-UP | Real `follow_up` command; native Codex queue accepted it. No primary Adesso/Dopo controls. |
| Optimistic lifecycle | INVIO appeared immediately, then IN CODA while the first turn worked. RPC ACK did not complete that turn. |
| Browser disconnect + Hub restart while queued | Reconnected to the same hub state; one follow-up wire submission, one canonical user bubble, exact client ID match. Codex executed its own queued instruction independently. |
| Explicit STEER | Separate advanced control sent `steer` during a harmless command window; the requested unique marker arrived live. |
| Turn changes while composing Steer | Draft and explicit Steer intent remained; send was disabled at READY. A subsequent current turn did not replace the captured expectedTurnId. Sending then returned TURN_CHANGED, retained text, and emitted no follow-up. |
| Explicit INTERRUPT | PWA targeted the actual current turn. The other official client observed `turn/completed` with `interrupted`; UI returned to READY independently of command ACK. |
| NEEDS_YOU → ANSWER → READY | Real plan-mode Alpha/Beta input. Normal composer hidden, `answer` command observed, structured Alpha response returned and pending request retired. |
| Mobile browser correctness | No horizontal overflow, no page errors, zero localStorage entries. |
| Transcript exclusion | All three unique wave conversation markers absent from SQLite main/WAL/SHM and Relay runtime log; SQL quick_check passed. No transcript table. |
| Automated regression | `go test ./...`, `go test -race ./...`, vet, shell syntax and nine ES-module control-flow tests passed. Local socket tests run with the required environment permission. Doctor rejects non-loopback plaintext without its explicit flag and does not follow redirects or forward authentication to their target. |
| Public CI | Canonical controls and outbox commits passed GitHub CI, including Go race tests, UI control tests and all three cross-builds. |

Tests cover explicit capabilities; follow-up without an active turn ID; stale steer TURN_CHANGED; ACK/materialization races; queue errors retaining text; unknown disconnect outcome without resubmission; native queue rehydration; duplicate canonical user items; per-session identity and bounded outbox/TTL. Direct-input read-only state does not prevent answering an outstanding addressed server request, and answering it does not grant other controls.

New rc.3-code binaries also **ran on the real Spark and MacBook**: doctor connected to each existing 0.160.0 shared daemon and enumerated **78** and **85** sessions, respectively. These were private staging binaries, not agents enrolled on an assumed hub. Spark's pre-existing staged systemd unit remained inactive. MacBook launchd was not activated.

### Actual deployment matrix at this checkpoint

| Check | EXON | SPARK | MACBOOK |
| --- | --- | --- | --- |
| SSH/host reachable | local | yes | yes |
| New binary runs natively | yes | Linux arm64 | macOS arm64 |
| Real Codex discovered | yes, 0.160.0 | yes, 0.160.0 | yes, 0.160.0 |
| Agent on canonical Zima hub | not yet | not yet | not yet |
| Sessions/control through canonical Zima PWA | not yet | not yet | not yet |
| Local validation new turn/follow-up/live/answer | passed | not run | not run |
| Canonical deployment reconnect | not yet | not yet | not yet |

### Historical root blocker: trusted SSH to Zima

The operator confirmed temporary Ethernet connected. Known Zima SSH/Tailscale addresses remained unreachable; Tailscale reported Zima offline. Relevant known-neighbour/mDNS checks on Exon, Spark and MacBook did not identify a reachable Zima. The candidate IP supplied by the operator exposed HTTP/HTTPS and printing, with SSH closed. Both DNS-SD and its public device descriptor definitively identified an HP printer, not Zima.

The operator explicitly authorized using only the router's existing Firefox session to read DHCP. Direct scoped cookie queries found no usable persisted router cookies. Copying the entire locked Firefox cookie DB was rejected by automatic approval review because it would duplicate other sites' sessions; that action was not performed. A safer capture of the exact router window showed “Session timed out because of inactivity”; renewed router login was requested. No Wi-Fi credential, browser cookie, token or device lease list is in this repository. No router/firewall/routing setting was changed.

Until trusted Zima SSH is available, its actual Alfa USB chipset/driver, Wi-Fi survival after Ethernet removal, OS/service/HTTPS deployment and ten-minute resource/latency measurements cannot be verified. The three canonical agent enrollments and physical iPhone push/tap acceptance remain downstream requirements. The old Exon loopback hub is retained only as validation rollback; there is no claim of a completed Zima cutover or a production multi-machine fleet.

### Zima console recovery checkpoint

The operator connected a monitor and keyboard. The firmware displayed “Reboot and Select proper Boot device”, explaining why Linux services could not announce the machine. The Aptio Boot screen detected the eMMC and two Debian boot entries, with Windows Boot Manager first. After selecting a Debian entry, the operator reported Linux booted and supplied `192.168.66.1`. This is physical-console evidence of boot recovery, not yet a remotely verified Zima identity or deployment.

The reported address answered ARP on the office Wi-Fi broadcast domain. A temporary IPvlan diagnostic namespace reached it without changing persistent host network profiles; TCP 22, HTTP 80/443 and Cockpit 9090 all refused connections. The matching link-local IPv6 address also refused SSH. No credential was sent or new host key trusted. Containers and their temporary Docker network were removed; Docker is not a Relay runtime dependency.

During these checks Exon renewed its DHCP lease onto `192.168.66.0/24`, with the reported address acting as DHCP server and gateway. This overlaps the separately configured Exon–Spark Ethernet subnet. The first diagnostic preserved the host route table; the later comparison detected the DHCP-driven change, so unchanged live routing is not claimed for the entire experiment. Relevant NetworkManager logs recorded the new DHCP lease. No persistent Wi-Fi profile, manual host route or router setting was edited.

A single low-rate ICMP discovery of that currently connected LAN, with at most two concurrent probes, found one additional device already known from the previous LAN; its SSH port was closed. The existing `ssh zima` alias still timed out through Tailscale, whose last-seen timestamp remained unchanged. Local SSH activation was requested from the operator's console. The Alfa chipset/driver, persistent Wi-Fi connection and canonical Zima service remain unverified until administrative access is restored.

**Historical checkpoint: blocked at Zima access.** The current recovery status is recorded at the top of this document. Do not promote this candidate to v0.1.0 based on local tests or staged remote binaries.
