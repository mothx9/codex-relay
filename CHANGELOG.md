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
- Smaller single-line composer with scalable input and clear heartbeat spacing
  when the draft grows across lines.
- Centered, smaller glass jump-to-latest control, visible only while substantial
  recent content is outside the viewport.
- Canonical Next up queue and direct Steer preserve input/client identity; `+`
  contains attachments only, and an empty working composer offers Stop.
- Photo/screenshot picker and image drops forward bounded images through the
  official Codex input API when the Agent supports them.
- Drafts remain editable offline. Live Questions have one reply home, readable
  structured history and partial-height panels; canonical Needs You stays distinct.
- Aligned Activity cards open one operation, changed files or the aggregate;
  smaller code blocks, syntax highlighting and readable diffs.
- Independent history/control lanes and coalesced refresh invalidations keep
  slow reads from delaying Steer or Interrupt.
- Contextual local alerts, notification deduplication, device registration retry
  and safe routing; native remote APNs delivery remains separately gated.
- Machine/account/access settings, bounded redacted diagnostics, English/Italian
  resources and the attributed Codex mark.
- Generic machine diagrams and refreshed screenshots/recorded walkthrough.

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
