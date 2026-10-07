# Installation ownership and access

Codex Relay is self-hosted. The administrator of the Hub host owns the
installation and its recovery material. There is no Relay cloud account, no
OpenAI login handled by Relay, and no privileged “primary iPhone” role.

A paired controller receives an expiring credential stored in the iOS Keychain
(or the browser's secure session). All authorized controllers currently have
the same fleet-control and enrollment-management permissions. The UI describes
that existing model; it does not pretend controllers are read-only guests.
If every controller loses access, the Hub administrator creates a new one-time
pairing code locally. The bootstrap credential stays on the Hub host.

| Action | Effect |
| --- | --- |
| Pause Agent | Denies Relay transport until resumed; local Codex continues |
| Resume Agent | Allows reconnect through Syncing and a fresh canonical snapshot |
| Revoke machine credential | Denies future Agent authentication; retains last-known fleet state; new enrollment required |
| Remove machine enrollment | Revokes credential and removes Relay machine/session/request routing metadata; Codex data remains local |
| Revoke controller | Immediately denies its credential and socket access; retains its enrollment record |
| Remove controller | Removes enrollment and notification registration; credential stops working |
| Revoke this iPhone | Confirms revocation on the Hub before clearing local access |
| Sign out locally | Removes only the local Keychain credential; does not claim Hub revocation |

Pausing or revoking a machine is **not** Codex request resolution. Unresolved
requests and one-shot reservations remain canonical, visibly last-known, until
Codex resolves them or a fresh Agent epoch reconciles them. Only explicit
machine-enrollment removal discards that machine's Relay routing metadata.

Diagnostics use an explicit metadata allowlist. The native “Copy Diagnostics”
report omits installation origins, machine names/IDs, account identities,
controller IDs, epochs, raw disconnect descriptions, credentials and content.
Database “reachable” means a read succeeded, not a full integrity audit.
