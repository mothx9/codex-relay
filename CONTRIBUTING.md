# Contributing to Codex Relay

Read the [architecture](docs/architecture/overview.md) and
[security boundaries](SECURITY.md) first. Relay can control work with local user
privileges; correctness and explicit uncertainty are product requirements.

## Development

Prerequisites: Go as specified in `go.mod`, Python 3, Node for PWA tests, and
Xcode on macOS for native work. Start with `make check`, `make test` and
`swift test --package-path native`. See [testing](docs/development/testing.md)
and [native development](docs/development/native-ios.md).

- `cmd/`: compatible CLI entry points.
- `internal/codex/`: local Codex app-server adapter.
- `internal/agent/`, `internal/hub/`, `internal/protocol/`: synchronization,
  authorization and canonical wire semantics.
- `native/`: SwiftUI client and independently testable core.
- `web/`: embedded fallback PWA.
- `scripts/`: installation, asset generation and checks.
- `docs/`: public architecture, setup, operations and development guides.

## Changes and reviews

Keep commits coherent and describe the concrete problem, resulting behavior and
validation. Run gofmt on Go changes. Use targeted tests while iterating, then
relevant full checks. Preserve unrelated working-tree changes.

Protocol fields need compatibility/absent-value behavior and tests across Hub,
Agent, native and PWA. Never make missing metadata grant a capability. Preserve
machine/session separation, epoch ordering, one-shot requests, identity-based
reconciliation, ACK versus completion and no retry after unknown outcome.

Do not add transcript persistence, forward Codex login tokens, or bypass approval
currentness to simplify a feature. Changes to auth, pairing, revocation, push,
request payloads and diagnostics require focused security review.

Use an isolated Hub or guaranteed ephemeral cleanup for enrollment tests. Real
Codex acceptance is optional and explicit: one owned validation thread, no real
workload control, no shared-daemon restart. Never commit private test configuration,
Apple credentials, database files, origins, OTPs or real transcript captures.

## UI and documentation

Public prose and source strings are English; Italian localization is supported.
Update the String Catalog and regenerate SwiftPM resources with
`python3 scripts/localization.py`. Do not localize wire enums/JSON keys.

Use the [screenshot pipeline](docs/development/native-ios.md) for sanitized assets;
review actual iPhone dimensions, Dynamic Type and Reduce Motion. Screenshots do
not replace live acceptance. Regenerate branding with `scripts/branding.py` and
diagrams with `scripts/diagrams.py` when their sources change.

Prefer durable guides to new root-level handoffs. Keep historical evidence clearly
marked as version-specific. Report security-sensitive issues privately as described
in [SECURITY.md](SECURITY.md).

Run `python3 scripts/docs-check.py` after moving guides or assets. The project
license is [Apache-2.0](LICENSE); keep license metadata consistent. Current release
and compatibility statements belong in [status](docs/status.md), while dated
acceptance evidence belongs under `docs/development/validation/`.
