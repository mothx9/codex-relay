# Current status and compatibility

This is the canonical current-status reference. Validation reports are dated
engineering evidence; they do not override this page or claim a public release.

## Release and distribution

The release line is **v0.1.0**: three versioned host archives, an unsigned native
device IPA, installer, checksums and exact source manifest. Start with
[downloads](setup/downloads.md); cloning and compiling are optional. The
installer's default is v0.1.0 and includes guided one-time enrollment.
The reference Hub and all three Agents run `0.1.0`, upgraded in place with their
credentials, service configuration and shared Codex daemons preserved. Dated
reports retain their original build identifiers.

The latest wave adds explicit context-compaction status, compact mixed activity
groups, direct file diffs, remaining-capacity quota windows and connected-client
local banners with machine/session/turn context and a slimmer persistent composer.
Fleet groups compact Working/Needs You rows in visible glass surfaces and keeps
a flat Recent index with quiet separators.
Green execution state is separate from the current activity; source text and
spacing are balanced. Send queues work, and a direct Next up Steer button (or
physical-keyboard Escape) promotes the selected canonical input without creating
a second message. The + menu contains attachments only. Activity inspection distinguishes its
compact aggregate, individual operation and changed-file list. Short live
questions open in a partial-height material sheet. Sanitized screenshots and a
recorded walkthrough document the current native views. The v0.1.0 signed iPhone
build is installed and launched in place on the physical device. Owner gesture
and notification presentation acceptance remain separate from installation.

The native app supports iOS 17+, English/Italian, Dynamic Type and Reduce Motion.
Liquid Glass uses a material fallback on older iOS. The native download can be
signed/sideloaded with AltStore Classic without Xcode. Free Apple accounts require
signature refresh every seven days. TestFlight/App Store distribution is not yet
provided. Safari → Add to Home Screen offers immediate PWA access without a
computer, with different presentation/features.

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
attention badge. It is an ephemeral hint, not a pending RPC. While current, its only presentation is above the session composer and in its
reply sheet. After retirement, the original question remains readable in history.
Reply prepares only the answer as an explicit
current-turn Steer draft for review; it never sends automatically. It cannot dismiss
another client's question. Turn boundaries, user input, local submission,
disconnect or epoch changes retire the hint. Navigation alone does not.
History and reconnect never reconstruct it. Cross-client async-question parity
is not claimed. See the [protocol](architecture/protocol.md) and
[event audit](development/validation/live-event-audit.md).

## Native inputs

New turns, Follow-ups and explicit Steer accept up to two selected photos or
screenshots when the connected Agent advertises image support. The iPhone uses
the system photo picker or an image drop, downscales to 1600 pixels and re-encodes
without original metadata. Each image is at most 256 KiB. Arbitrary files, video
and audio are not supported. Image previews are bounded local memory; after
relaunch, canonical history can show attachment counts rather than stored copies.

Queued work has a separate **Next up** home above the composer. Canonical user
items enter the transcript by upstream identity, not by the order of taps. An
absent queue entry is not treated as completed; uncertain outcomes never resend
automatically. Slow history/catalogue reads use a separate Agent lane from
serialized control commands.

## Native notifications

The native app provides **local alerts while connected**, separately from
**remote APNs push**. Local foreground banners for completion, supported pending
RPCs, live questions and failure pass simulator OS-notification acceptance.
The owner accepted an earlier installed physical build: Home Screen icon, chat scroll,
keyboard/composer menu, direct file diff and the local test banner. This is separate
from the simulator event-routing tests. The latest images, queue controls and
Notification Center/Lock Screen gestures await a new owner check. Delivered local alerts remain in Notification Center when that iOS presentation
option is enabled; Lock Screen presentation is a separate system preference.
New local alerts cannot reach a force-quit or arbitrarily suspended app. Permission alone does not mean remote delivery is operational. The notification screen
summarizes both paths and discloses registration details.

Routing, semantic deduplication, privacy, expired-token cleanup and deep links
remain covered by tests. Physical APNs delivery is **not yet accepted**.

Current external gates: an Apple team/profile with Push Notifications and
`aps-environment`, an authorized APNs provider key on the Hub, then physical
banner/Notification Center/badge/tap/cold-start checks. The inspected Personal
Team build lacks the entitlement and the reference Hub has no APNs provider key.
The owner-provided Apple portal shows enrollment pending with a membership
purchase prompt; the paid capability has not been activated. Local alerts remain
available without that membership. See the setup guide for the separate free
Home Screen Web Push option.
Use the [notification setup guide](setup/notifications.md); ordinary control does
not require APNs. This release does not claim accepted physical remote APNs delivery.

## Evidence

- [v0.1.0 release validation](development/validation/v0.1.0.md)
- [M1 reliability validation](development/validation/m1-validation.md)
- [M2 product validation](development/validation/m2-validation.md)
- [Live event audit](development/validation/live-event-audit.md)

These reports distinguish automated, simulator, real-service and physical-owner
acceptance. Public screenshots use sanitized production-view fixtures.
