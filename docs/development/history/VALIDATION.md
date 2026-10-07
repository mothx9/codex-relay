# Validation record

## iPhone conversation and asynchronous-question context — 2026-10-06

Implemented the owner's iPhone chat reference: compact header, native Markdown, asymmetric conversation alignment, selectable Terminal/MCP details, queued Follow-up labels and a fixed keyboard-aware composer with Liquid Glass on iOS 26+ and a material fallback. Counts describe bounded recent activity and do not assert tool completion. Isolated Debug fixtures neither load credentials nor connect to the Hub.

Fourteen Swift core tests, Go/vet/race checks, nine browser tests, four installer tests and three cross-builds pass. The isolated UI case covers long history, initial positioning, composer/keyboard access, question display, tool details and draft preservation. The live case again covers the existing HTTPS Hub, Keychain restart, the three production hosts, an isolated New Turn/canonical reply, exact single-user-message reconciliation and foreground reconnect. The physical build passed strict signature verification, installation and launch; physical interaction acceptance remains distinct from installation.

A read-only inspection of Spark's existing Codex daemon found a canonical `agentMessage.questions` item in the working YVEX thread. The adapter and native DTO had discarded its titles/options. Both now preserve bounded question context, including question-only messages. Adapter tests and Hub WebSocket tests cover history/live routing without inventing a pending request or Answer capability. Question strings count toward both Hub and native RAM byte limits. No question text is persisted to Relay's database.

The original rollout shows that this particular question had already been answered in the original client. A real read-only history request through the Hub returned 24 normalized activities from the last 40 raw items, with zero questions: the older question is outside that window. The fixture UI passes; no new real asynchronous question was created in an unrelated working thread. Native asynchronous reply, canonical resolution state, discovery outside the open chat/recent window and physical receipt of a fresh question remain open. APNs closed-app delivery/tap also remains unverified and requires the owner's push-capable team/key.

Deployed the verified binaries to the one existing Zima Hub and then Spark, Exon and MacBook agents separately. All report rc.4, connected shared adapters and account metadata. The Hub sees the three production hosts ONLINE. Online SQLite backup/quick_check, bootstrap, VAPID, agent token rows, units/plist and current enrollments were preserved; an additional pre-existing enrollment was retained rather than removed. Binary hashes were checked before each remote installation. Only Relay services were restarted; no network setting, shared Codex daemon or unrelated workload was changed. No public rc.4 tag or final release is claimed.

## Native and rc.4 deployment checkpoint — 2026-10-06

Upgraded the existing Zima Hub in place to the verified rc.4 build. The binary, service definition, online SQLite backup and private credential files were retained for rollback; an initial failed recovery check actually restored rc.3 before the successful upgrade. The existing DB passed quick_check and bootstrap, VAPID, installed agent credentials and the operator cookie were preserved. Exon and MacBook recovered, then their Relay agents were upgraded separately without restarting Codex. Both now report only account kind/email/plan. Spark was unreachable during the upgrade; its credential and service were preserved. The final read-only check sees all three machines ONLINE, the Hub active on rc.4, SQLite quick_check OK and the iPhone enrollment active. Separate SSH checks confirm Spark is reachable with an active agent service and an rc.3 linux/arm64 binary. Spark's rc.4 upgrade and account metadata verification remain pending. The earlier three-host PWA acceptance below is historical evidence, not acceptance of the new native controls.

On the actual HTTPS Hub, an eight-digit operator OTP exchanged once, reuse returned 401 and a separate code expired after five minutes. Revocation closed the paired WSS socket immediately and subsequent HTTP returned 401; the disposable operator was removed. Disposable agent enrollment, conflict rejection, pause/resume, revoke, re-enrollment with a new credential and removal passed without touching real agent enrollments.

The native XCUITest ran against that same Hub on an iOS 27 simulator. OTP pairing, Fleet enumeration of the three enrolled hosts, Keychain recovery after app termination, isolated New Turn, a fresh canonical Codex reply and foreground reconnect passed. The submitted text appeared exactly once as the canonical user item, with no remaining optimistic duplicate. This run uses local simulator signing and simulator-only Keychain entitlements; the original unsigned app compiled but could not access Keychain. The test configuration and artifacts remain private.

The owner's Personal Team signed the physical-device build, strict signature verification passed, and a regenerated profile included the connected iPhone. Installation passed. The owner confirmed developer trust, app opening and pairing. Physical New Turn/Follow-up/Answer/Steer/Interrupt acceptance and actual APNs receipt/tap have not passed yet. Personal Team signing has no APNs entitlement.

Nine Swift core tests pass, including MCP property-name preservation, typed fields, required values, enums, bounds, nested schemas and unsupported-schema rejection. Native permission and MCP forms compile, show full payload/schema and require an online machine and current request. Isolated SwiftUI previews render without loading Keychain or connecting to the Hub. Live native approval and the remaining control/recovery tests are pending. The default remains a release candidate; no final release or new rc.4 tag is claimed.

Final continuation: ten Swift core tests and four isolated installer tests pass, as do Go/race/vet, nine browser tests and three cross-builds. Temporary HTTP bootstrap failures now retry without treating them as revoked access; 401/403 returns to pairing. Steer retries retain the original expected turn, and Interrupt retains the turn captured before confirmation. The live native suite passed again after these changes. The updated physical build passed strict signature verification, installation and process launch. Installer tests verify persistent APNs path retention, explicit disable without key deletion, dry-run isolation and rejection of invalid/misrouted configuration; actual provider keys are still absent and APNs delivery remains unverified.

## Canonical deployment acceptance — 2026-10-06

Zima Debian 12 amd64 now boots normally with zero failed units. A missing optional HDD mount was made nonfatal; an invalid legacy NFS entry was disabled. The obsolete bridge/DHCP server was removed on Zima only. Root/data filesystems were not reformatted; private backups are retained locally. Exon's network configuration was not modified during this recovery.

Alfa USB `0bda:0811` is AWUS036ACS / RTL8811AU. The initial rtw88 backport had firmware TX errors and loss; DKMS `rtl8821au/5.12.5.2` from morrownr/8821au-20210708 commit `1a819991f5b75e64dfcf922b96a6681f367cbba0` passed checks with a 20 MHz limit and power saving off. Ethernet and monitor were physically removed; Ethernet carrier=0, new SSH and Wi-Fi-bound DNS/HTTPS checks passed. This proves cable-removal acceptance, not months of unattended stability.

Hub user service active/enabled, linger=yes. Real HTTPS certificate verified and WebSocket upgrade exercised from a real browser. Bootstrap/VAPID hashes and the operator cookie survived an actual Hub restart. Private origin, addresses and account identities remain outside this public repository.

| Real control through the single Zima Hub | EXON | SPARK | MACBOOK |
| --- | --- | --- | --- |
| Agent online / actual sessions visible | PASS | PASS | PASS |
| Shared Codex daemon discovered | 0.160.1 | 0.160.1 | 0.160.0 |
| Native binary | linux/amd64 | linux/arm64 | darwin/arm64 |
| Service | systemd user | systemd user | launchd |
| New turn / live response | PASS | PASS | PASS |
| Follow-up / exact client ID reconciliation | PASS | PASS | PASS |
| Harmless structured input / Answer / READY | PASS | PASS | PASS |
| Actual agent service restart / fresh snapshot | PASS | PASS | PASS |
| Fleet recovery after real Hub restart | PASS | PASS | PASS |

Only isolated validation threads received commands. Explicit Steer and Interrupt passed on Exon. A Codex-owned follow-up executed once across browser disconnect and Hub restart, with no automatic resend. All three agents reannounced after Hub restart in 2023 ms. Old Exon validation Hub/Agent processes are stopped and their PID file retired. No unrelated daemon or workload was restarted. MacBook physical sleep/wake and off-LAN roaming are unverified.

### Actual Zima resource sample

Same Hub PID, three agents connected, 600 seconds without controlled test turns followed by a 30.026-second CPU window. Other Codex work increased session metadata from 395 to 398, so this is not a zero-traffic sample.

| Metric | Observed |
| --- | --- |
| RSS start / after 10 minutes | 20,620 / 20,172 KiB (20.14 / 19.70 MiB) |
| CPU final window | 4 ticks at 100 Hz: 0.133% of one core |
| Main SQLite DB | 376,832 bytes (368 KiB), unchanged |
| WAL start / final | 1,009,432 / 3,436,112 bytes |
| SHM | 32,768 bytes |
| TCP sockets | One loopback listener, three established agent connections |
| Kernel receive/send queue samples | 0 bytes |
| Socket file descriptors | 5 |

Application event-queue occupancy is not exposed; kernel queue bytes are not that metric. WAL checkpointing is SQLite's default; no transcript table exists. This short sample is not a long-duration leak test.

### Transport latency without inference

All three agents used Tailscale direct peers. Five metadata-only official `thread/name/set` events per isolated validation thread were correlated by event ID between a loopback observer on Zima and a real HTTPS browser. Source/Hub/browser clocks were calibrated over persistent SSH connections. One-way values include clock asymmetry, millisecond quantization and observer overhead.

| Hop | Five observed samples, ms |
| --- | --- |
| Exon Agent → Hub observer | 9.04, 5.45, 6.72, 10.00, 5.63 |
| Spark Agent → Hub observer | 7.54, 6.19, 6.25, 8.66, 7.64 |
| MacBook Agent → Hub observer | 11.68, 11.12, 7.49, 9.66, 10.70 |
| Hub observer → HTTPS browser | 1.80–25.77 across all 15 events |

Model inference is excluded. Temporary measurement tooling is outside the production runtime. Private network endpoints/topology identifiers are not published.

### Native extension handoff before the macOS continuation

The user requested a native Swift iPhone client, OTP pairing and device management after the canonical cutover. New Go/race/control tests, three cross builds, five Swift tests, an actual Xcode simulator build and implementation CI pass. The backend was also built/tested on macOS with Go 1.27.1. New pairing/device/APNs endpoints are **not deployed**; native app E2E, physical signing/install and real notification receipt/tap remain unverified. Native permission/MCP forms remain incomplete. No complete v0.1 release is claimed. The user closed this wave to move development to macOS; see [HANDOFF_MACOS.md](HANDOFF_MACOS.md).

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

The operator connected a monitor and keyboard. The firmware displayed “Reboot and Select proper Boot device”, explaining why Linux services could not announce the machine. The Aptio Boot screen detected the eMMC and two Debian boot entries, with Windows Boot Manager first. After selecting a Debian entry, the operator reported Linux booted and supplied a private legacy gateway address. This is physical-console evidence of boot recovery, not yet a remotely verified Zima identity or deployment.

The reported address answered ARP on the office Wi-Fi broadcast domain. A temporary IPvlan diagnostic namespace reached it without changing persistent host network profiles; TCP 22, HTTP 80/443 and Cockpit 9090 all refused connections. The matching link-local IPv6 address also refused SSH. No credential was sent or new host key trusted. Containers and their temporary Docker network were removed; Docker is not a Relay runtime dependency.

During these checks Exon renewed its DHCP lease onto the same private legacy subnet, with the reported address acting as DHCP server and gateway. This overlaps the separately configured Exon–Spark Ethernet subnet. The first diagnostic preserved the host route table; the later comparison detected the DHCP-driven change, so unchanged live routing is not claimed for the entire experiment. Relevant NetworkManager logs recorded the new DHCP lease. No persistent Wi-Fi profile, manual host route or router setting was edited.

A single low-rate ICMP discovery of that currently connected LAN, with at most two concurrent probes, found one additional device already known from the previous LAN; its SSH port was closed. The existing `ssh zima` alias still timed out through Tailscale, whose last-seen timestamp remained unchanged. Local SSH activation was requested from the operator's console. The Alfa chipset/driver, persistent Wi-Fi connection and canonical Zima service remain unverified until administrative access is restored.

**Historical checkpoint: blocked at Zima access.** The current recovery status is recorded at the top of this document. Do not promote this candidate to v0.1.0 based on local tests or staged remote binaries.
