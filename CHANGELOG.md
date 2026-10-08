# Changelog

Entries describe verified implementation checkpoints, not unperformed acceptance.
Native remote APNs delivery and Apple consumer distribution are tracked separately
from the downloadable self-hosted release.

## v0.1.0 — 2026-10-08

- Standardized versioned Hub/Agent archives, an unsigned device IPA, installer,
  checksums and exact source manifest; replaced the old RC downloads/tags.
- Guided installation downloads the current release automatically; no clone or
  Go toolchain. The Agent machine ID can default to its hostname.
- Documented iPhone sideloading without Xcode and immediate Home Screen PWA access.
- Grouped compact active Fleet surfaces with quieter Recent separators; Working
  scrolls with the transcript and the composer floats without a solid footer.
- Generic machine diagrams and refreshed screenshots/recorded walkthrough.

- Compact hybrid Fleet: light glass emphasis for active rows, flat Recent, larger
  source metadata and an explicit Working state separate from activity.
- Direct queued-message Steer with preserved input/client identity; `+` contains
  attachments only, and an empty working composer offers Stop.
- Draft remains editable without live control; Live Questions show source context,
  clear reply access and formatted text without transport-lifecycle prose.
- Opaque semantic Activity cards retain individual operation/file routes.

- Open Fleet, Needs You and Relay menu lists with title-first hierarchy, quiet
  Recent rows and stable Working order during live updates.
- Two-line Working rows align machine/project above elapsed time and show a
  green execution-state sweep beside the secondary activity category;
  current live questions have one composer-side reply home without transcript copies.
- Consistent activity alignment and distinct routes for one operation, changed files
  and the compact aggregate; short live questions use a partial-height sheet.
- Smaller code blocks and renewed native screenshots, video and transparent SVGs.

- Bounded photo/screenshot input through the native picker and image drops,
  gated by Agent capability and forwarded through the official Codex input API.
- Separate Next up queue, canonical queue-edit results and independent read/control
  lanes; uncertain outcomes remain explicit and never resend automatically.
- Compact, individually navigable activities with source/tool context; persistent
  live-question reply access and readable structured reply history.
- Foreground alerts retained in Notification Center, with Lock Screen and remote
  delivery limitations made explicit.

- Contextual notification banners identify machine, project, session and source turn,
  with an explicit hide-details preference and automatic device registration retry.
- Slimmer composer with persistent contextual actions, tighter activity indentation,
  quieter code typography, refreshed screenshots and a recorded native walkthrough.

- Connected-client local iOS alerts, independent permission/delivery readiness,
  semantic deduplication and safe notification routing; remote APNs remains separate.
- Ephemeral cross-session Live Questions with current-turn/epoch invalidation,
  separate from canonical RPC requests and never reconstructed from history.
- Quiet grouped Fleet, remaining-capacity quotas, integrated composer, mixed
  activity previews, direct file inspection and mobile diff/readability hardening.
- Explicit context-compaction lifecycle and neutral animated session heartbeat.
- Updated native Codex icon attribution, transparent diagrams and screenshot suite.

- Work-focused navigation with single entity homes and exception-only Fleet health.
- Compact Terminal summaries, machine-local diagnostics and account relationships.
- Live async-question draft preparation stays separate from authoritative Needs You;
  reconnect/history never reconstruct pending questions from assistant content.
- Apache-2.0 metadata aligned, public guides edited and validation evidence relocated.

- Native Now/Fleet navigation, live session heartbeat, contextual composer and
  structured Terminal/tool/file/diff presentation.
- Derived Codex Account Registry with sparse usage windows and account freshness.
- Product Settings, Machines, Controllers & Access and redacted Diagnostics.
- Notification registration state and authenticated foreground/cold-start routing.
- One-time machine installer flow, iPhone onboarding, English/Italian resources,
  shared product mark and isolated public screenshot tooling.

[M2 validation](docs/development/validation/m2-validation.md) records the live acceptance evidence.
Physical APNs delivery is a separate acceptance requirement; implementation and
provider tests are not a delivery claim.

## 0.1.0-rc.4+m1.4 — 2026-10-07

Validated canonical reliability baseline ([report](docs/development/validation/m1-validation.md)):

- Separate machine connectivity from last-known Codex session state.
- Explicit Syncing → Online admission, epochs, sequences and snapshot watermarks.
- Reconnect/Hub restart recovery and canonical pending-request preservation.
- Operational sessions prioritized over paginated cold history.
- Bounded diagnostics and measured real-fleet acceptance over 403 sessions.
- Go/race/Swift/native UI checks and physical iPhone connection validation.

This was a verified deployment build; it is not a claim that an identically named
public GitHub release was published.
