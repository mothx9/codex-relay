# M2 productization validation

This dated report preserves initial productization evidence. The final coherence
pass is recorded in the final section below; [current status](../../status.md) is the
canonical release and compatibility reference.

Validation date: 2026-10-07. M1 remains the reliability baseline in
[m1-validation.md](m1-validation.md). M2 remains an explicit release candidate:
physical notification delivery has not passed.

## Initial product and implementation checkpoint

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

The [provider audit](../../architecture/provider-boundary.md) records the boundary.
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
[assets/app/screenshots](../../assets/app/screenshots). They show Fleet, Needs You,
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
See [SECURITY.md](../../../SECURITY.md), [access](../../architecture/access.md),
[notifications](../../architecture/notifications.md) and
[test isolation](../test-isolation.md). This is a focused implementation
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
publication. At this initial checkpoint, physical/Apple acceptance remained outstanding; this
is not an implementation failure or a current release-status declaration.


## Final product coherence pass — 2026-10-07

Starting main: `7b88f79453cf6d9aedc7be3de43360981e9fc5c1`. This section supersedes
the initial checkpoint's navigation and physical-launch observations. Reliability
and the supported-RPC source-of-truth model remain unchanged.

### Entity homes and visual acceptance

The chosen root is **Fleet / Needs You**, with a native Relay administration
sheet. It was compared with the preceding three-tab layout on iPhone 16.
Settings contains Hub configuration, notifications and About; it does not repeat
Machines, Accounts, Controllers or Diagnostics. Accounts link to a filtered
canonical Machines screen. Global Diagnostics summarizes system health; machine
measurements belong to Machine → Diagnostics. See the
[navigation rationale](../../architecture/native-navigation.md).

Fleet is quiet when infrastructure is healthy and shows an actionable exception
when necessary. Working stays green without changing the application accent.
The conversation keeps its reader-intent policy and heartbeat, with a compact
jump-to-latest button. Terminal cards show current/last activity, while execution
history and output live in detail. Inline pending questions use neutral content
with restrained warning treatment and avoid repeated machine/project labels.

Fifteen sanitized screenshots were captured using production views and visually
reviewed: Fleet, conversation, Inbox, inline question, Terminal, tools, diff,
Machines, Account, Settings, global Diagnostics, machine Diagnostics, Relay menu,
pairing and [live assistant question](../../assets/app/screenshots/live-question.png).
Visual iteration corrected a clipped Terminal header, unnecessary zero-count
metadata, repeated question headings and singular warning copy. Public fixtures
are visual evidence only; real-Hub acceptance is listed separately below.

### Async questions and account data

Installed Codex remained **0.160.1**. Supported pending RPCs remain canonical;
historical assistant questions never create pending requests or Inbox entries.
A bounded live-turn presentation hint preserves observed assistant questions and
lets an option prepare a draft. It sends no Answer RPC and does not dismiss
another client's local question. Disconnect, navigation away and turn changes
clear the hint; transcript content remains readable. No cross-client async
currentness guarantee is claimed.

The upstream `CreditsSnapshot.balance` is an optional string without a defined
unit or display precision. Primary UI therefore shows only supported availability
or unlimited state; exact reported balance is under Data details, explicitly
without an invented currency/unit. Usage windows retain protocol-defined duration
and sparse values. Updated time is primary; source-machine provenance is advanced.

### Repository and checks

Apache-2.0 is consistent with the unchanged tracked LICENSE. README is edited as
a product introduction with five selected screenshots and an expected-result
Quick Start. The documentation portal is user-oriented. Validation/audit evidence
moved here with links repaired; [current status](../../status.md) is the single
release/limitations reference. Public docs were inspected for private origins,
paths, identifiers and deployment-specific instructions. Reference-deployment
history remains clearly identified. A local documentation-link check now runs in
`make check` and CI. No new provider abstraction or Codex RPC leakage was added.

- `make check test checksums` passed: formatting, vet, Go ordinary/race tests,
  nine web checks, eight installer checks, localization, local links and three
  Go cross-builds. All generated checksums verified.
- 52 Swift core/presentation tests passed, including live-question lifetime and
  history exclusion; historical async-question regression remains green.
- Simulator build and build-for-testing passed on iPhone 16.
- Seven read-only real-Hub UI tests passed: Settings/diagnostics, account,
  historical Inbox exclusion, reading position with keyboard, notification deep
  links, management surfaces and Fleet/session heartbeat navigation.
- Behavioral UI tests passed for nonduplicated administrative homes, live-question
  draft preparation versus static history, composer/Terminal inspection with draft
  preservation, and Home Screen icon launch. The icon attachment was visually
  reviewed. The screenshot pipeline passed.
- Test harness assumptions were updated for the new navigation and explicit
  transcript scroll target. The real scroll test loads earlier history when the
  first page is shorter than the viewport, before checking reading-position
  retention; production scroll policy was preserved.
- No test controller or validation Codex thread was created in production by this
  pass. Real workloads were observed only. Existing paired simulator state was
  restored after isolated screenshot/tests.

### Deployment and external acceptance

The read-only deployment sample found Hub and all three Agents Online on
`0.1.0-rc.5+m2.3`, database reachable, 403 catalogue sessions, six hot sessions and
zero pending RPCs. This pass changes native presentation, documentation and a
sanitized backend test fixture; it requires no Hub/Agent upgrade. Shared Codex
daemons, service settings, SQLite, enrollment, credentials and networking were
unchanged. These are current counts from one sample, not workload guarantees.

The newest native build **built, signed, installed and launched** on the existing
physical iPhone. Enrollment was retained. Current-build owner gesture/Home Screen
acceptance is still pending and must not be inferred from automated launch.

Both the signed app and Personal Team profile lack `aps-environment`. The Hub
service has neither APNs configuration nor provider key; no usable key was found
in the inspected local Relay/private setup locations. The missing material cannot
be generated from notification permission. The exact external gate is a
Push-capable Apple team/profile plus an authorized APNs key privately configured
on the Hub, followed by physical delivery, badge and tap/cold-start acceptance.
The [notification setup guide](../../setup/notifications.md) documents the existing
installer-supported path. No key was fabricated or Apple credential changed.

Independent software work is RC-ready. Source stays `0.1.0-rc.5`, reference
services stay `0.1.0-rc.5+m2.3`; no final release/tag is published. Physical owner
and Apple/APNs acceptance remain explicit external gates.


## Native control-surface wave — 2026-10-07

This entry supersedes earlier **current-state** statements above; earlier entries
remain historical evidence. The wave started at `4bc4cb9` and retains release
candidate `0.1.0-rc.5`.

### Product and protocol changes

- Fleet uses neutral Working rows and grouped Recent sessions. Quota windows
  display remaining capacity with matching bars and duration-derived labels.
- Consecutive same-turn operations form stable, compact activity groups with
  concrete command/tool/file previews. Individual filenames open their diff
  directly. Full command/output inspection remains in detail.
- One glass composer contains the plus menu, growing text and submit control.
  Working uses a restrained gray-to-white sweep, with no duplicated operation
  subtitle. Reduce Motion keeps the label static.
- Markdown list paragraphs wrap fully; message actions use native context menus.
  Full-message copy was verified from the last paragraph. File detail preserves
  patch fidelity while hiding transport metadata from the primary view.
- Empty-text upstream `contextCompaction` items were previously dropped by the
  adapter. Explicit start/completion now reach Relay as `context_compaction`,
  with canonical item/turn identity; the live heartbeat shows Compacting context
  only while current. No reasoning content is exposed.
- Live async questions are bounded ephemeral attention, separate from canonical
  pending RPCs. Initial live observation reaches the connected controller even
  without an open transcript. History/reconnect never reconstruct the hint.
- Connected native clients can deliver local notifications with semantic dedupe,
  private copy, safe deep links and attention-only badges. Permission, local
  readiness and remote registration/configuration are modeled separately.
- The native icon uses the owner-requested Codex mark, with provenance and
  attribution in the asset documentation. Public screenshots use sanitized
  fixtures; all seven architecture diagrams have transparent canvases and
  maintained generator source.

### Qualification evidence

- `make check test`: formatting, vet, ordinary Go tests, race tests, nine web
  checks, eight installer checks, localization and documentation links passed.
  Linux amd64/arm64 and macOS arm64 cross-builds/checksums passed.
- 61 Swift tests passed, including transient-question lifetime/history exclusion,
  grouping, file previews, quota remaining, notice readiness/dedupe and explicit
  compaction. Existing pending-RPC and scroll regressions remain covered.
- Simulator builds and build-for-testing passed. Targeted XCUITests covered
  composer/tool inspection, direct file selection, compaction, whole-message
  copy, Home Screen icon, transient draft preparation and notification delivery.
- Actual simulator OS banners passed for completion, pending RPC, live question
  and failure, including dedupe, disabled notifications and badge updates. These
  are local notifications, not simulated evidence of remote APNs receipt.
- A real isolated Codex turn emitted an async question. Hub live attention reached
  the Inbox, badge and local banner; tapping the banner opened the session and
  an option prepared a draft. Ending the owned turn removed the hint; relaunch
  did not resurrect it or modify canonical pending RPCs. The thread was archived.
- A second owned turn emitted assistant text → command → file → command → file
  → assistant text. Native acceptance verified one group with two commands/two
  files and direct per-file navigation. The thread was archived afterward.
- Manual compaction on an owned thread produced both `item/started` and
  `item/completed`; the thread was archived afterward. No real project work was
  answered, interrupted or compacted.
- Real-Hub read-only acceptance covered accounts, history/Inbox exclusion,
  notification links, Fleet/session navigation, reading position through keyboard
  changes and Settings/diagnostics. Real screenshots and identifiers stay private.

### Reference deployment and physical acceptance

Hub and Exon/Spark/MacBook Agents were safely upgraded to
`0.1.0-rc.5+m2.5`; all returned Online and the database remained reachable.
Existing SQLite, identity, enrollment, credentials and service configuration were
preserved. Shared Codex daemon process identities were unchanged. No networking
configuration or production controller enrollment was added.

One measured upgrade sample (wall-clock observations, not latency guarantees):

| Component | Measurement |
| --- | --- |
| Hub service restart | 178 ms; RSS 14,844 kB |
| Linux workstation Agent | snapshot 240 ms; synchronization 345 ms; RSS 12,004 kB |
| GPU node Agent | snapshot 389 ms; synchronization 430 ms; RSS 10,112 kB |
| macOS Agent | snapshot 571 ms; synchronization 629 ms |

The newest signed physical build was installed and launched without losing
pairing. The owner explicitly confirmed **“Tutto funziona, banner visibile”** for
the requested batch: Codex Home Screen icon, history scroll, keyboard/plus menu,
direct file diff and Test local alert. This physical confirmation is separate
from the automated and real-service tests above.

The signed application and Personal Team profile still have no
`aps-environment`; the Hub has no APNs provider key. The sole remote-delivery gate
is a Push-capable Apple team/profile and authorized provider key configured
privately on the Hub, followed by physical remote banner/badge/tap/cold-start
acceptance. Local alerts do not replace remote push. No final `v0.1.0` tag or
release is published.

## Composer and notification-context follow-up — 2026-10-07

Starting reference: `fe9d1ec`. This follow-up preserves canonical state and changes
presentation, notification context and public evidence.

- Native and Hub notices identify machine/project, session title and the source
  event's turn reference. They never borrow a newer session turn or include prompt,
  response, command or output text. Hide session details restores generic copy;
  existing explicit privacy preferences remain respected. This replaces the older
  native-default description above; web privacy defaults are unchanged.
- The one-line composer is 44 points high, with 44-point controls and a quieter
  32-point send glyph. Its action panel leaves the composer, keyboard and heartbeat
  visible. Steer and Interrupt remain capability/current-turn gated; Copy Session
  Link and the duplicate send-button Steer action were removed. Draft preservation
  and keyboard behavior pass targeted XCUITest.
- Activity indentation and code type size are tighter. Public fixtures use one
  coherent validation example, not private live work. A reproducible 18-second
  simulator walkthrough records actual Fleet → conversation → actions → file diff
  → Needs You navigation, with launcher frames excluded. All 18 screenshots were
  regenerated and visually reviewed. Onboarding links to the canonical Machines
  destination and its screenshot starts at the introduction.

### Verification

- Go formatting/vet, ordinary and race tests, 9 web checks and 8 installer checks
  passed (`make check test`). The notification-context Go test covers redacted and
  contextual payloads. 62 Swift tests passed, including source-turn identity,
  missing metadata and privacy behavior.
- Simulator build/build-for-testing passed. Native OS-banner acceptance passed for
  completion, RPC input, live question and failure, including contextual subtitle,
  dedupe, badge and disabled state. These are local notifications, not APNs.
- Composer visibility/geometry, retained draft through Steer, whole-message copy,
  the recorded walkthrough and screenshot assertions passed. Real-Hub read-only
  XCUITest passed reading-position preservation with keyboard and foreground/cold
  session/machine notification deep links. No real session received a command.
- Signed physical build installed and launched in place. The earlier owner batch
  acceptance remains valid evidence for that earlier build; this follow-up's
  slimmer composer and contextual banners still need the owner's visual check.

### Reference deployment and external limits

Only the Hub required a backend update: `0.1.0-rc.5+m2.6`. Agents remain on
`0.1.0-rc.5+m2.5`. The existing Hub upgrade retained its service/credential hashes,
backed up SQLite and preserved shared Codex process identities. Direct configured
Hub SSH worked after the workstation route timed out. The post-upgrade snapshot
reported the GPU node and macOS Agent Online; the Linux workstation was Offline
and independently unreachable by SSH. No network setting or workstation service
was changed to conceal that state.

The current signed app and embedded profile both lack `aps-environment`. The Hub
still has no APNs key. The owner's Apple portal shows pending enrollment and a
membership purchase prompt. Native remote push requires the paid Apple capability;
local connected alerts do not. Home Screen Web Push is a separate no-membership
option, not a claim of newly accepted native remote delivery. The project remains
an RC with no final release/tag.

### Owner check for this follow-up

Open the installed app without re-pairing. In a currently Working session, open
`+`: the slimmer input stays visible, Working remains readable, and the menu offers
current-turn controls without Copy Session Link. Type a draft and switch to Steer
without sending; confirm the text remains. Return to Follow-up or cancel the draft.
Open a visible filename to inspect its diff. In Notifications, confirm Hide session
details matches your preference. With the app connected on Fleet, a completion in
an isolated validation session should identify machine/project, session and turn;
do not create commands in production work just to trigger a banner.

Compare machine connectivity in Relay → Machines with the canonical Hub view;
an Offline machine must stay Offline rather than be displayed as Ready/finished.
The public `codex-relay doctor` path documented in the operations guide is a
transport/service diagnostic, not proof of a visible iPhone banner. Report any
composer overlap or notification missing its source; owner gesture/banner
acceptance is separate from the automated receipts above.


## Input control and conversation hardening — 2026-10-07

This follow-up starts at `cf3eab7` and preserves the RC release boundary. Source
slices include `462b0d2`, `7dcd217`, `bea7f67`, `13b1469`, `451d2cf`, `392178c`
and the Xcode 26.6 compatibility correction `2c1e830`.

### Behavior and evidence

- Follow-ups have a separate **Next up** area. Canonical IDs reconcile Steer and
  dispatched input; disappearance from the queue is not completion. A real isolated
  Codex thread passed native queue + Steer acceptance: Steer entered the current
  turn, the Follow-up remained queued, then appeared exactly once when consumed.
- System Photos and image drop support bounded JPEG/PNG input. Native photo-picker
  selection/removal passed. A real native → Hub → Agent → Codex turn received and
  recognized the selected image; an independent thread read found the image item.
  The disposable thread was archived afterward. No production thread was used.
- Expanded activity rows replace the collapsed preview, identify server/tool, and
  open only the selected operation. File previews share a compact row. A live
  question has one current presentation above the composer, with full options in
  its reply sheet. It is not repeated in the transcript while current; afterward
  its original history item remains readable. Selecting an option prepares only
  the answer as an explicit Steer draft. Historical questions never regain actionability.
- The Codex adapter projects valid structured question replies into question and
  answer content, preserving upstream item/client IDs. It does not expose the
  transport XML/JSON wrapper or infer pending state. Markdown uses a restrained
  inline-code scale, list rhythm, headings and quotes.
- Local foreground alerts request both banner and Notification Center list
  presentation. Completed/failed notices are retained; obsolete attention notices
  can be retired. Badge changes do not clear delivered completion notices.
- Native chrome, app icon, PWA icons and public branding now share Codex geometry;
  the obsolete R mark is removed. Twenty sanitized product surfaces were captured.
  The refreshed 17.83-second walkthrough was reviewed across its full duration.
  Diagrams are transparent SVGs, including the bounded image-input path.

### Qualification

Go formatting/vet, ordinary and race tests, 9 web checks, 8 installer checks,
localization and repository-link checks passed. All 66 Swift tests passed. Simulator
build and generic build-for-testing passed. Eight focused UI checks passed,
including four actual local OS banner kinds, semantic dedupe, disabled delivery,
Notification Center retention, image picking, individual activity navigation and
live-question draft behavior. Separate real-Codex image and queue/Steer UI tests
passed; independent canonical history contained four owned turns and one image.

CI initially exposed excessive SwiftUI type-check complexity on Xcode 26.6;
extracting the live-question choice view fixed it. CI at `2c1e830` is green, and
its focused live-question UI test also passed locally. This is qualification,
not a substitute for owner gesture acceptance or remote APNs delivery.

### Reference deployment

Hub and all three Agents were upgraded to `0.1.0-rc.5+m2.7`; the Hub then received
`0.1.0-rc.5+m2.8` solely to ship the corrected embedded web branding. SQLite backups,
service/credential hashes and shared Codex daemon identities were preserved.
The Linux Agent synchronized in 398 ms, the GPU Agent in 445 ms, and all three
Agents reached Online. These measurements describe that deployment, not an iPhone
latency guarantee. Slow history now has a separate lane from serialized controls.
The final signed native build is installed in place without re-pairing.

### One physical acceptance batch (Italian)

Prerequisito: apri Codex Relay già installato; non reinstallare, non ripetere il
pairing e non usare turni di lavoro reali per prove distruttive.

1. Controlla l'icona Codex nella Home e nella barra Fleet: nessuna R.
2. In una chat apri `+` → Add photos, scegli uno screenshot e rimuovilo senza
   inviarlo. Il composer resta visibile. Prova il trascinamento di uno screenshot
   quando disponibile sul dispositivo.
3. Espandi un gruppo Activity e tocca una singola operazione: il dettaglio deve
   riguardare quella operazione. Apri anche un file; scroll e tastiera non devono
   riportarti forzatamente in fondo.
4. In un turno isolato, verifica Next up e Steer; confronta ordine e consumo con
   lo stesso thread nel client Codex. Il messaggio in coda non è un messaggio già
   eseguito. Per una domanda live usa Reply vicino al composer: prepara soltanto
   la bozza; inviala solo se vuoi davvero modificare quel turno.
5. Relay → Settings → Notifications → Test local alert. Dopo il banner abbassa
   il Centro notifiche; poi blocca il telefono e verifica l'avviso già consegnato.
   Le opzioni iOS Banner, Centro notifiche e Schermata di blocco devono essere
   abilitate per Relay. Non è una prova di nuovi eventi ad app sospesa/chiusa.

Restituisci eventuali screenshot di icona, singolo dettaglio, Next up o avviso
mancante. Confronta Relay → Machines con lo stato canonico Hub; i test backend
`TestSlowHistoryCannotBlockCurrentTurnControl` e
`TestReconnectAndHistoryDoNotResurrectAsyncQuestions` coprono rispettivamente
isolamento delle letture e mancata resurrezione dalla cronologia. Le prove su
fixture, le due prove Codex isolate e l'accettazione fisica restano distinte.
L'accettazione fisica precedente non certifica automaticamente questa build.
Remote APNs resta esclusivamente il gate Apple descritto nello stato prodotto.
