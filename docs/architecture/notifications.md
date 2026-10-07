# Notifications

Notifications use remote APNs from the canonical Hub or best-effort local alerts
from a connected native controller. They do
not carry approval forms, authorize commands, or replace the current snapshot.
The iPhone remains usable without APNs.

## Independent states

1. iOS notification permission (not requested, denied, allowed, quiet delivery).
2. Apple device-token registration, using the signed app's APNs environment.
3. Hub APNs configuration.
4. This controller's registration on the Hub.

`GET /api/native-push/status` requires a paired controller credential and returns
only that controller's registration, environment and privacy preference. It
never returns a device token. Revoked/expired controllers cannot query status or
receive notifications. Subscribe/unsubscribe operations preserve the existing
Origin/CSRF and controller authorization checks.

The app refreshes permission and server registration after reconnect. When the
user has enabled delivery, it re-registers with Apple to obtain the current token
and upserts that token on the Hub. Disabling alerts stops local delivery immediately and removes Hub
registration before reporting remote unsubscription success; it does not revoke iOS permission.

## Delivery and privacy

The bounded delivery queue accepts Needs You, completion, failure and machine
offline (after the existing one-minute grace period). It never queues token,
command-output or tool-progress notifications. Semantic deduplication keys are
stored without transcript content. Delivery errors are logged without tokens or
Apple credentials. APNs Unregistered/BadDeviceToken responses remove the invalid
subscription. A test requested by a paired native controller targets that
controller, not the entire fleet of phones.

Default lock-screen text omits machine, project, question and transcript content.
The APNs payload contains opaque session/machine/request routing identities, a
notice kind and the pending-request count observed at dispatch. Requests already
resolved while queued are suppressed. Foreground rehydration corrects the badge
and removes delivered request notices whose sessions no longer need input.
Background badges can remain last-known until another push or foreground sync;
APNs delivery and background execution are not guaranteed by iOS.

Queue acceptance is not delivery. A successful APNs HTTP response is not proof
that a physical phone displayed a banner.

## Navigation

The notification delegate buffers a token or the latest navigation intent if it
arrives before the SwiftUI callbacks are attached. The controller retains a tap
through authentication and waits for a canonical socket snapshot before opening
its destination. A cold historical session is found via on-demand catalogue
pages; an offline machine remains explicitly offline. Missing machines/sessions
produce a contextual explanation.

A resolved question notification opens the conversation's *current* state. It
cannot recreate an approval form from old notification content. Expired access
requires pairing again before any session is fetched or action is available.
The `codex-relay://session/<canonical-id>` and `codex-relay://machine/<machine-id>`
URL schemes use the same navigation path. Credentials, queries, fragments,
control characters and malformed identities are rejected. Links never execute
commands or submit decisions.

## Apple configuration and acceptance

A real build needs an Apple team/provisioning profile that permits Push
Notifications, the `aps-environment` entitlement, and an APNs key configured on
the Hub. Development builds use the sandbox endpoint; production-signed builds
use production. A Personal Team profile without that entitlement cannot pass
physical APNs acceptance.

Follow the [setup guide](../setup/notifications.md) for the Apple key and Hub
service configuration. [Current status](../status.md) records external acceptance
gates separately from application/server test evidence.

Automated coverage exercises controller-scoped status, token privacy,
ES256 provider authentication, APNs endpoint selection, expired-token cleanup,
canonical badge counts, resolved-request filtering, navigation validation and
cold-start intent retention. Simulator URL routing tests use the already-paired
controller and read-only real sessions; they do not create test enrollments.

## Connected-client local alerts

The native controller derives semantic notices only from accepted live events:
`request`, `live_question`, `turn_completed`, `failed` and a machine remaining
offline for 60 seconds after an observed transition. Initial snapshots/history
do not alert. Completion in the open session is quiet. Permission UI finishes
independently of Apple/Hub registration. Local notices contain no transcript or
question text and use `UNUserNotificationCenter` plus the normal safe navigation
path. They are not a background service and do not replace APNs.

A confirmed current Hub subscription owns delivery, suppressing local duplicates.
Both transports use `notice_key`; a bounded foreground ledger suppresses duplicate
presentation. The local policy retains at most 512 identities. The badge is
canonical pending RPCs plus currently observed live questions; completion and
offline state never increment it. Losing the stream clears live hints. Remote
badges use canonical pending RPC counts; foreground reconciliation adds live
hints actually observed by this controller.

## Transient live-question channel

The Hub forwards an additive `attention` envelope to connected controllers,
independent of transcript watches. `live_question` carries only question content
and real machine/session/turn/item identity with the accepted epoch/sequence.
`live_question_cleared` retires session hints on turn boundaries or user input.
This uses an independent native freshness gate so the same original event may
still update a watched transcript. It never inserts a pending RPC or snapshot
entry. Hub notification identity metadata is bounded to 128 entries; the native
hint model is bounded to 64 entries and 256 KiB, with 256 retired identities.

Only initial live observation may notify. Queued notifications check currentness
before dispatch; APNs/Web Push expiry is zero for transient questions. Already
delivered remote alerts can outlive upstream work; a tap always rehydrates state
and never opens an approval form from the notification payload.
