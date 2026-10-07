# M2 productization validation

Validation date: 2026-10-07. M1 remains the reliability baseline in
[m1-validation.md](m1-validation.md). M2 remains an explicit release candidate:
physical notification delivery has not passed.

## Product and implementation

The native root is Fleet / Needs You / Settings. Fleet prioritizes pending work,
current work and a bounded recent set; an actionable machine summary opens the
machine list. Historical sessions remain searchable and paginated. Conversation
navigation hides the root tabs, with Session Info behind the title and a live
heartbeat beside the sticky contextual composer. Working indicators are green;
the application-wide interaction accent remains the system accent.

Assistant Markdown uses Swift Markdown, dedicated native code blocks and
horizontally scrollable tables. Code uses a bounded offline lexer rather than a
WebView or a large multi-language regex parser. Commands, output, MCP operations,
files and per-file diff hunks have separate detail/copy actions. A real-device
build includes English/Italian resources and the independent Relay mark.

High-frequency content observation lives in the transcript; Markdown work is
batched and stable item identities survive snapshots. Live acceptance exposed a
scroll bug: content/keyboard geometry could disable following before a streamed
response arrived. Following now represents reader intent; explicit upward
reading suspends it, while content growth and keyboard resizing preserve it.
Sending or choosing Latest messages resumes following. File-summary invalidation
now includes progressive patch fields rather than only the last text label.

Settings separates Relay, Machines, Codex Accounts, Notifications, Controllers &
Access, Diagnostics and About. Controller rights describe the existing single-user
model honestly: the Hub administrator owns recovery; paired controllers have equal
control permissions. Pause, credential revocation, enrollment removal and local
sign-out have distinct effects. Pending forms gate submission on current machine
connectivity as well as request/capability state. Reconnect acceptance also found
an accessibility value that called Syncing/Degraded “Live”; it now reports the
actual connection state, matching the visible heartbeat.

## Accounts and protocol boundaries

The Hub derives one registry from typed Agent account snapshots. Supported stable
account identity takes precedence over normalized email fallback; anonymous API
credentials are not merged. Source machines, receipt freshness, plan, sparse
rate-limit windows, resets, credits and supported limits remain explicit. Window
labels derive from duration metadata; missing data is not zero. Thread token
counters/context window stay in Session Info. Unsupported analytics are omitted.
No OpenAI credentials or independent OpenAI login are introduced.

The real reference fleet reported one fresh account shared by three machines,
using a supported account ID and one populated rate-limit bucket. This observation
does not imply every optional field is available on every plan.

The [provider audit](architecture/provider-boundary.md) records the boundary.
MCP progress, terminal interaction and file patch events are normalized inside the
Codex adapter. Terminal input text is not forwarded. Tool results retain bounded
text summaries and discard arbitrary structured/authentication data. The existing
M1 epoch/sequence/watermark and one-shot request guarantees remain enforced.

## Real native acceptance

Tests reuse the already-paired development simulator controller. They do not mint
production credentials on each run. Three confirmed stale test-only controllers
were removed; the physical iPhone and one intentional paired development
simulator remain. Two explicitly owned validation threads were used sequentially
and archived after completion. No real project turn was answered or interrupted.

| Flow | Evidence |
| --- | --- |
| Needs You | Real supported request; Agent restart while pending; Fleet, Inbox and inline request; resolution from the other allowed client; disappearance after app relaunch |
| Assistant/Terminal streaming | Harmless multi-second printf/sleep command; output visible while running; assistant deltas before completion |
| Follow-up and editing | Normal Working send queued immediately; Edit Last Queued Message replaced the same queue identity; one canonical execution/bubble remained |
| New Turn | Native composer sent to an isolated thread; canonical user message once; assistant response visible with keyboard open; background/foreground recovered state |
| Steer | Contextual current-turn action changed the active turn's final reply; canonical user message once; no queued Follow-up created |
| MCP/files/diff | Read-only public documentation MCP call and one owned temporary file; running/completed item events, 23 assistant deltas and three turn-diff updates; native details opened |
| Full-message copy | Both a paragraph context menu and the explicit full-message action copied the exact three-paragraph, 51-byte canonical response; pasted into the composer and compared, then cleared without sending |
| History | Real earlier-history loading and navigation passed without another enrollment |
| Agent silence/reconnect | Only the Relay Agent was suspended; Offline/last-known Working remained visible; the fresh snapshot restored Live; shared Codex process identities were preserved |
| Settings/accounts/diagnostics | Real Hub views opened; registry aggregation rendered; copied diagnostics excluded sensitive identifiers/content |
| Notification routing | Authenticated foreground/cold-start URL routing and resolved-request behavior tested without claiming APNs delivery |

The MCP/file sample did **not** emit granular MCP-progress or file-patch-update
notifications. Those mappings have deterministic coverage; this sample proves
item lifecycle and turn-diff streaming, not every optional upstream event.

A first New Turn UI test failed because its old config assertion expected an
origin outside Keychain and because the new response fell below the viewport.
The obsolete assertion and actual scroll bug were corrected; the successful rerun
requires the assistant response to be hittable, not merely present offscreen.
An earlier copy attempt in a long real transcript failed navigation; only the
subsequent exact clipboard comparisons count as copy acceptance.

## Visual evidence

Twelve sanitized product screenshots are versioned under
[assets/app/screenshots](assets/app/screenshots). They show Fleet, Needs You,
conversation, Terminal, tools, diff, Machines, Account, Settings, Diagnostics,
onboarding and pairing. They exercise the production views with isolated DEBUG
fixtures, without Keychain, Hub or network. Private live-test screenshots remain
outside Git. Capture tooling restores the existing watcher and live app.

Each major surface was compiled, opened, captured and inspected. Corrections
included compact Fleet hierarchy, semantic status, mobile-safe rich content,
question option selection, removal of repeated question text, patch summaries,
composer/keyboard position and live scrolling. Italian maximum accessibility
Dynamic Type onboarding and the simulator Home Screen icon were also checked.
The five architecture SVGs have maintainable generator sources and were rendered
and inspected. Public screenshots contain generic machine/account identities.

## Deployment and measurements

The existing Hub and all three Agents run `0.1.0-rc.5+m2.3`. They were upgraded
sequentially from the same reviewed source; SQLite, enrollment, credential files
and service configuration were preserved. Shared Codex daemon process identities
were unchanged. No network or Tailscale configuration was changed.

| Worker | Snapshot reconstruction | Connected to Online | Restart to Online observation |
| --- | ---: | ---: | ---: |
| Linux x86-64 | 94.5 ms | 204.0 ms | 374.8 ms |
| Linux ARM64 | 301.7 ms | 356.1 ms | 703.4 ms |

The final silent-Agent acceptance observed Offline after about 63 seconds, then
restored current state after resuming the Agent. No shared daemon was restarted.
The macOS launch-service restart command took about 530 ms; this is not a
connection-to-Online measurement. Hub restart took about 122 ms and observed RSS
was about 14.4 MiB. These are single observations, not percentile guarantees.
The final snapshot after archiving validation threads contained 403 catalogue
entries and eight hot entries across three Online workers, with no pending
requests. A prior sample included the temporary validation thread.

## Automated checks and security review

- Go formatting, vet, ordinary tests and race tests passed.
- Nine web checks and eight installer checks passed.
- 48 Swift core/presentation tests passed.
- iPhone 16 simulator build-for-testing and targeted XCUITest flows passed.
- Product screenshot capture and behavioral question-selection checks passed.
- Localization generation matches the catalog; documentation links and diffs were checked.
- Changed tracked files had no private-key/OpenAI-secret pattern matches; no real
  AcceptanceConfig, token, provisioning profile or database is tracked. This
  targeted inspection is not a claim that automated scanning proves secrecy.
- Three architecture-specific Go artifacts and matching SHA256SUMS were generated.
- CI checks run on each coherent pushed checkpoint; the final Git state is reported
  with the handoff rather than embedding a self-referential commit hash here.

Focused review retained exact-Origin/CSRF and socket authorization, one-time
expiring pairing, immediate controller revocation, Keychain storage and one-shot
pending decisions. Account allowlists and diagnostics redaction have negative
secret tests. Notifications are controller-scoped, private by default, suppress
resolved requests and remove expired APNs tokens. Deep links only select current
authenticated state; they cannot execute actions or reconstruct stale approvals.
See [SECURITY.md](../SECURITY.md), [access](architecture/access.md),
[notifications](architecture/notifications.md) and
[test isolation](development/test-isolation.md). This is a focused implementation
review, not an external penetration-test certification.

## Physical iPhone and remaining acceptance

The updated application builds, signs and installs on the existing physical
phone without replacing its Keychain enrollment. Automated launch encountered
Apple's Locked-device rejection. Current-build gesture, Home Screen icon and
foreground verification therefore require the owner to unlock/open the app.
Earlier owner confirmations do not substitute for this build's acceptance.

The signed executable and its local Personal Team provisioning profile both lack
`aps-environment`; the Hub also has no APNs provider configuration. No Apple
credentials were changed. Server registration/routing/dedupe/privacy/error tests
and simulator navigation pass, but **no physical APNs banner, badge or cold-start
notification tap is claimed**. Required external setup is a Push Notifications-
capable Apple Developer team/profile plus its APNs key configured privately on
the Hub, followed by physical phone acceptance.

No final v0.1.0 or public tag was published. Source defaults remain `0.1.0-rc.5`;
the reference deployment has the explicit `+m2.3` build suffix. The tag workflow
creates a reviewed draft release with checked artifacts, not automatic final
publication. The milestone remains BLOCKED on the stated physical/Apple gates.
