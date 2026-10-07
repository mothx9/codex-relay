# Troubleshooting

Start in **Relay menu → Diagnostics** and **Machines → machine detail**. Copy
Diagnostics produces a redacted report; the detailed on-screen view can still
contain private identities. Do not post credentials, Hub origins, request bodies
or real conversation screenshots in public issues.

| Symptom | Check |
| --- | --- |
| Hub not connected | HTTPS trust, configured public origin, reverse-proxy WebSocket upgrades, controller expiry/revocation |
| Machine Offline | Relay Agent service and its last contact; local Codex may still be working |
| Relay paused | Resume Relay access from machine detail; this is different from powering off a host |
| Syncing persists | Adapter access to the shared daemon and complete snapshot/request replay; a socket alone is insufficient |
| Codex not connected / Degraded | Local Codex runtime and adapter diagnostics; do not silently substitute a second daemon |
| Last known: Working | Machine state is stale; Relay deliberately does not invent completion or Ready |
| Old session absent from Now | Open All Sessions/search and fetch catalogue pages; active/pending canonical state remains primary |
| Read-only history | Explicitly attach only when the intended machine/runtime can own that thread |
| Needs You differs from a message question | A blocking request RPC is actionable; an assistant message with question text is not automatically an approval RPC |
| Unknown command outcome | Inspect canonical conversation/queue before deliberate intervention; do not auto-resend |
| Steer says turn changed | The original turn ended/replaced; text remains for an explicit next action |
| Push unavailable | Distinguish iOS permission, push entitlement, Hub APNs setup and this-controller registration |
| Account window absent | Codex did not provide it; missing is not zero usage |

On Linux, inspect the **Relay** user service with `systemctl --user status` and
`journalctl --user -u codex-relay-agent` (or `codex-relay-hub`). On macOS, inspect
the installed user LaunchAgent and its configured log paths. Logs and private
state should remain on the host; sanitize before sharing.

Silent machine loss is bounded by heartbeat/read deadlines, not immediate power
telemetry. Clean disconnect is immediate; heartbeat/event silence normally closes
a peer in roughly 75–90 seconds from last contact. Snapshot/transport timings
include observation and clock effects, not model execution time. Do not diagnose
a VPN from a spinner: measure each layer and inspect direct/relayed status only
when reliable tooling provides it. Relay does not alter network configuration.

For lost-controller recovery, use the Hub administrator's local access to create
a fresh one-time controller code, then revoke the lost credential. Local sign-out
alone does not claim server revocation. See [access and recovery](../architecture/access.md).

For command-line diagnostics, run on the relevant host:

```sh
codex-relay doctor --hub-url "$RELAY_HUB_URL"
codex-relay version
```

`doctor` reports available runtime/Hub/database checks, not a guarantee that a
physical controller or notification provider completed an end-to-end action.
Advanced machine authentication uses `--machine` and `--token-file`; credentials
belong in private files, never copied into command arguments or public output.

## Notification permission is allowed, but remote push is unavailable

Permission only authorizes iOS presentation. Check the separate Local alerts and
Remote push summary under Relay menu → Settings → Notifications. Local alerts
require a connected client; remote delivery additionally requires an entitled
Apple build, device token, configured Hub provider and verified registration.
Follow [notification setup](../setup/notifications.md); do not replace credentials
or restart Codex to fix Apple provisioning.

## Working during context compaction

Current adapters forward explicit compaction item start/completion. The heartbeat
shows “Compacting context” while current and returns to Working afterward. Older
Agent builds silently omitted this empty-text item. Upgrade Relay Agents without
restarting shared Codex; no transcript heuristics or reasoning display is used.
