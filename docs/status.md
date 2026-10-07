# Current status and compatibility

This is the canonical current-status reference. Validation reports are dated
engineering evidence; they do not override this page or claim a public release.

## Release and distribution

The source candidate is **0.1.0-rc.5**. The validated reference Hub and Agents use
`0.1.0-rc.5+m2.3`. No final v0.1.0 is published by this productization pass.
Build the candidate from source with `make build`; use `--binary` with the
installer. The legacy default download is an older published RC, not current main.

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

In an open, connected session, a question observed during the current live turn
can prepare a message in the composer. The user reviews and sends it using the
normal New Turn/Follow-up or explicit Steer controls. This does not submit an
Answer RPC, dismiss another client's question, or create a Needs You badge.
After disconnect, navigation away or turn change, the live hint expires;
transcript content remains readable. Cross-client async-question parity is not
claimed. See the [protocol](architecture/protocol.md) and
[event audit](development/validation/live-event-audit.md).

## Native notifications

Routing, registration, deduplication, privacy, expired-token cleanup and deep links
are implemented and covered by tests. Notification permission, Apple device-token
registration, Hub APNs configuration and controller registration are separate.
Physical APNs delivery is **not yet accepted** in the reference deployment.

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
