# Testing

## Local checks

Use the Go version in `go.mod`, Python 3 and Node for backend/PWA/installer checks.
A Mac with Xcode is required for native builds and UI tests.

```sh
make check
make test
swift test --package-path native
python3 scripts/localization.py --check
```

`make check` includes formatting, vet, Go race, browser and installer tests.
`make test` runs the ordinary Go test suite as well. Run focused package/tests
while iterating, then the complete relevant checks before a checkpoint.

[Native build commands](native-ios.md) compile the app and UI test runner.
Behavioral XCUITests use a simulator destination and `test-without-building`
after a signed `build-for-testing`; disable parallel testing for an explicitly
selected simulator. Compilation alone is not UI or live acceptance.

## Deterministic coverage

Protocol/reducer tests cover epoch/sequence/watermark admission, reconnect,
last-known state, pending requests, canonical identity and unknown outcomes.
Native tests additionally cover Markdown, links, source/diff presentation,
account windows, sparse updates, deep-link routing and redacted diagnostics.
Use behavior/state assertions; avoid pixel-perfect snapshots.

Public screenshot tests use isolated DEBUG fixtures and never create an
enrollment. They prove rendering only. Review dark/light appearance, Dynamic
Type, Reduce Motion, keyboard, selection and scrolling as appropriate.

## Optional live acceptance

Live XCUITests skip without a private `AcceptanceConfig.json` in the **built test
bundle**. The simulator must already be paired; tests do not mint production
controllers on each run. See [controller hygiene](test-isolation.md).

Keep the configuration, result bundles and real screenshots outside Git. Values
include the intended session/machines and opt-in mutation flags. Never use real
project work for New Turn, Follow-up, queue editing, approval, Steer, Interrupt
or failure tests. Reuse one clearly named owned validation thread and archive it
afterward. Preserve the shared Codex daemon and existing service credentials.

Read-only acceptance may inspect existing history, accounts, diagnostics and
navigation. Mutating acceptance must prove canonical event completion, not ACK:
observe assistant/output before completion, exactly-once queued work, request
visibility across Fleet/Inbox/inline, resolution elsewhere and rehydration.

Suspend an existing rebuild watcher during UI tests and restore it in a `finally`
block. The simulator watcher does not deploy to a physical phone. Physical
build/sign/install, keyboard/gesture checks and real APNs receipt/tap are separate
acceptance steps. A fake APNs provider or URL-open test cannot prove delivery.

## Native control-surface acceptance

Install and launch the signed build using the [native guide](native-ios.md),
retaining the existing pairing. For repeatable owner acceptance:

1. Open a session with sufficient history. Scroll upward during streaming, open
   the keyboard and dismiss it. Reading position must remain stable; the compact
   down button returns to recent content only when tapped.
2. Open `+`. Current-turn actions follow capabilities; Session Info belongs to
   the title. The composer remains one aligned control as text grows.
3. In an owned command/file validation session, inspect the compact activity
   group. Commands and changed basenames must be visible. Tap a filename to open
   its diff directly; copy a patch and compare with the canonical detail.
4. Open Relay → Codex Accounts. Each available duration window shows remaining
   percentage and a matching remaining-capacity bar; missing windows stay absent.
5. Open Relay → Settings → Notifications. Allow permission once if needed; the
   local and remote summaries remain distinct. Tap Test local alert: expect one
   native banner. This does not validate APNs or background delivery.
6. In a disposable live turn, observe a supported pending RPC or live async
   question. Verify the correct Inbox section, one notice and the badge. Resolve
   or end only that owned turn; reopen the app and confirm no stale form returns.

Compare the UI with the backend using supported read-only checks:

```sh
codex-relay version
codex-relay doctor --hub-url https://relay.example.com
```

Run `doctor` on an Agent host with its normal local Codex endpoint configuration;
the output reports `codex_adapter`, `codex_version` and Hub reachability. The
example origin must be replaced with the installation's real HTTPS origin.
Doctor's `push` field concerns Web Push key presence, not APNs delivery. Use
Relay → Diagnostics for canonical machine freshness and Settings → Notifications
→ Delivery details for APNs/device/Relay registration. Use Copy Diagnostics for
a redacted receipt. Do not paste credential files or private transcripts into
issues.

Record which checks used sanitized fixtures, real owned turns, the simulator or
the physical phone. An automated pass does not imply owner gesture acceptance;
an owner-confirmed local banner does not imply remote APNs acceptance.
