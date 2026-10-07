# Changelog

Entries describe verified implementation checkpoints, not unperformed acceptance.
The project remains a release candidate until native product acceptance, including
required physical notification delivery, is complete.

## Unreleased — M2 productization

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
