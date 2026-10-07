# Changelog

Entries describe verified implementation checkpoints, not unperformed acceptance.
The project remains a release candidate until native product acceptance, including
required physical notification delivery, is complete.

## Unreleased — M2 productization

- Native Now/Fleet navigation, live session heartbeat, contextual composer and
  structured Terminal/tool/file/diff presentation.
- Derived Codex Account Registry with sparse usage windows and account freshness.
- Product Settings, Machines, Controllers & Access and redacted Diagnostics.
- Notification registration state and authenticated foreground/cold-start routing.
- One-time machine installer flow, iPhone onboarding, English/Italian resources,
  shared product mark and isolated public screenshot tooling.

[M2 validation](docs/m2-validation.md) records the live acceptance evidence.
Physical APNs delivery is a separate acceptance requirement; implementation and
provider tests are not a delivery claim.

## 0.1.0-rc.4+m1.4 — 2026-10-07

Validated canonical reliability baseline ([report](docs/m1-validation.md)):

- Separate machine connectivity from last-known Codex session state.
- Explicit Syncing → Online admission, epochs, sequences and snapshot watermarks.
- Reconnect/Hub restart recovery and canonical pending-request preservation.
- Operational sessions prioritized over paginated cold history.
- Bounded diagnostics and measured real-fleet acceptance over 403 sessions.
- Go/race/Swift/native UI checks and physical iPhone connection validation.

This was a verified deployment build; it is not a claim that an identically named
public GitHub release was published.
