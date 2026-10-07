# Current status and compatibility

This is the canonical current-status reference. Validation reports are dated
engineering evidence; they do not override this page or claim a public release.

## Release and distribution

The source candidate is **0.1.0-rc.5**. The validated reference Hub and Agents use
`0.1.0-rc.5+m2.5`. No final v0.1.0 is published by this productization pass.
Build the candidate from source with `make build`; use `--binary` with the
installer. The legacy default download is an older published RC, not current main.

The latest wave adds explicit context-compaction status, compact mixed activity
groups, direct file diffs, remaining-capacity quota windows and connected-client
local banners. Eighteen sanitized screenshots document the current native views.

The native app supports iOS 17+, English/Italian, Dynamic Type and Reduce Motion.
Liquid Glass uses a material fallback on older iOS. Installation currently
requires Xcode and your own signing team. TestFlight/App Store distribution is
not yet provided. The PWA remains a fallback/debug client.

## Codex compatibility

The adapter is validated against Codex app-server **0.160.1**. Runtime capabilities
gate actions; Relay protocol v1 is independent of the upstream schema. Codex owns
threads, transcripts, running turns and the follow-up queue. Relay retains only
bounded ephemeral conversation/outbox content.

**Needs You is authoritative for supported pending server RPCs.** Such requests
have canonical identity and resolution through the Hub, including reconnect.

**Async assistant questions are conversation content.** In validated Codex
0.160.1, `request_user_input_async` produces `agentMessage` content with
`delivery = async` and `questions`. Its dismissal/currentness lives in the TUI;
the app-server exposes no shared authoritative pending lifecycle for it.
Relay never infers pending state from history or from a missing visible reply.

A live question observed on the current connection appears in a separate
**Live Questions** section of Needs You and contributes to the connected app's
attention badge. It is an ephemeral hint, not a pending RPC. It can prepare a
composer draft; the user chooses Follow-up or explicit Steer. It cannot dismiss
another client's question. Turn boundaries, user input, local submission,
disconnect or epoch changes retire the hint. Navigation alone does not.
History and reconnect never reconstruct it. Cross-client async-question parity
is not claimed. See the [protocol](architecture/protocol.md) and
[event audit](development/validation/live-event-audit.md).

## Native notifications

The native app provides **local alerts while connected**, separately from
**remote APNs push**. Local foreground banners for completion, supported pending
RPCs, live questions and failure pass simulator OS-notification acceptance.
The owner accepted the installed physical build: Home Screen icon, chat scroll,
keyboard/composer menu, direct file diff and the local test banner. This is separate
from the simulator event-routing tests. Local alerts cannot reach a force-quit or
arbitrarily suspended app. Permission alone does not mean remote delivery is operational. The notification screen
summarizes both paths and discloses registration details.

Routing, semantic deduplication, privacy, expired-token cleanup and deep links
remain covered by tests. Physical APNs delivery is **not yet accepted**.

Current external gates: an Apple team/profile with Push Notifications and
`aps-environment`, an authorized APNs provider key on the Hub, then physical
banner/Notification Center/badge/tap/cold-start checks. The inspected Personal
Team build lacks the entitlement and the reference Hub has no APNs provider key.
Use the [notification setup guide](setup/notifications.md); ordinary control does
not require APNs. Keep the RC until required physical acceptance passes.

## Evidence

- [M1 reliability validation](development/validation/m1-validation.md)
- [M2 product validation](development/validation/m2-validation.md)
- [Live event audit](development/validation/live-event-audit.md)

These reports distinguish automated, simulator, real-service and physical-owner
acceptance. Public screenshots use sanitized production-view fixtures.
