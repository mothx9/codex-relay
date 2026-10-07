# Notifications

Notifications are an optional delivery channel from the canonical Hub. They do
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
and upserts that token on the Hub. Disabling notifications removes the Hub
registration before reporting success; it does not revoke iOS permission.

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

During M2 inspection, the existing reference iPhone build's provisioning profile
was local provisioning and both its profile and signed executable lacked
`aps-environment`. No signing credentials were changed. Server and simulator
validation is distinct from the still-required real-device delivery test.

Automated coverage exercises controller-scoped status, token privacy,
ES256 provider authentication, APNs endpoint selection, expired-token cleanup,
canonical badge counts, resolved-request filtering, navigation validation and
cold-start intent retention. Simulator URL routing tests use the already-paired
controller and read-only real sessions; they do not create test enrollments.
