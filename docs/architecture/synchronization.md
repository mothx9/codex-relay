# Canonical state and recovery

Relay owns fleet connectivity and control routing. Codex owns threads, turns,
conversation, queue and execution requests. A socket is not proof of current
Codex state. None of the mechanisms below persists conversation or tool output.

## Two independent state dimensions

Machines use `OFFLINE`, `SYNCING`, `ONLINE`, and `DEGRADED`. `RECONNECTING` is
reserved for a client-facing retry indication; the Hub does not fabricate a
reachable Agent while retrying. Transport acceptance immediately publishes
`SYNCING`. Only an accepted complete Codex snapshot admits `ONLINE`. An Agent
unable to open Codex announces `DEGRADED` without erasing last-known sessions.

Sessions keep `READY`, `WORKING`, `NEEDS_YOU`, `FAILED`, or `INACTIVE`. Their
`fresh`, `observed_at`, and `agent_epoch` fields describe observation, not task
completion. Disconnect invalidates freshness and capabilities; it never turns
Working into Ready. Native Fleet and conversation show connection state and
last-known session state separately. The transport remains independent of VPNs.

## Epoch, sequence and snapshot admission

An adapter connection to Codex owns a random epoch and increasing event sequence.
A Hub socket additionally owns a connection identity. A replaced socket cannot
mutate the new connection. Epoch is pinned after its first announcement; changing
it requires another connection. Consequently an older process cannot write
through its previous socket even if its sequence is numerically larger.

A snapshot carries its covered event watermark and a per-Hub-connection snapshot
revision. Lower watermarks and repeated/older nonzero revisions are ignored.
Legacy protocol-v1 agents omit revision and retain the ordered-WebSocket/lower-
watermark rule. New fields are additive; existing native/PWA clients remain
compatible. Events at or below the accepted sequence are idempotent. A bounded
2048-ID window also rejects duplicate IDs with altered sequence numbers.

Adapter publication refreshes captured session metadata under the sequence lock.
Periodic refresh flushes transcript events through the snapshot watermark before
announcing it: metadata is not a replacement for message/output deltas. Accepted
machine, session and request-routing snapshots commit in one SQLite transaction.

The native client additionally rejects wrong-epoch and non-increasing events.
Its socket generation guard rejects callbacks from old transports. The private
`pending` message may enrich the already-received fleet request without creating
a second request or form incarnation.

## Reconnect and bounded liveness

1. Transport connects; Hub publishes `SYNCING` and disables mutation capabilities.
2. Adapter enumerates loaded threads across all cursor pages and subscribes them.
3. Codex replays supported unresolved server requests during subscription.
4. Adapter constructs a snapshot including every observed pending request's session.
5. Hub validates identity, epoch, revision and watermark, commits and publishes
   the accepted state as `ONLINE`.

Failed active-thread subscription fails synchronization. One observed Codex edge
case is a loaded idle thread whose `thread/resume` returns JSON-RPC `-32600`,
`no rollout found for thread id`. Relay rereads the thread, requires current
`idle` status and no observed pending request, then retains read-only metadata.
It never applies that exception to active or pending work.

Snapshot reads run in a separate serialized worker with a 15-second deadline.
Live events, operator controls and heartbeats continue while it waits. A failed
read announces `DEGRADED` on the existing Hub socket and retries with bounded
backoff; it does not turn a healthy transport into a reconnect storm. Only the
first complete snapshot reconciles requests absent from reconnect replay; an
incomplete announcement cannot count as snapshot admission. Same-connection
periodic recovery retains unresolved requests and the initial sync duration.
Initial event replay retains a bounded tail and requires snapshot coverage for
any discarded prefix. Periodic snapshots cannot overwrite newer live events.

Agent heartbeat and WebSocket ping intervals are 10 seconds. The Hub checks every
5 seconds and closes a peer after more than 30 seconds without heartbeat/event
contact, bounding silent machine loss to approximately 30–35 seconds. WebSocket
read deadlines also close a peer 30 seconds after its last pong. Clean socket
loss is immediate. Agent reconnect backoff is capped at 15 seconds with jitter;
a successful handshake alone does not reset repeated short-failure backoff.
No shared Codex daemon restart is required.

The native client opens WSS before optional bootstrap reads. It requires the
first canonical snapshot within 30 seconds, allowing cold mobile/VPN routing and
TLS setup. It probes an admitted quiet socket every 10 seconds, reconnecting
after a missing pong exceeds 10 seconds. No ping is sent before admission. Callbacks check
both controller generation and socket identity. Foreground recovery starts a new
connection; retries are capped at 8 seconds with jitter. HTTP diagnostics reuse
an ephemeral transport with request-scoped credentials and no cookie/cache or
redirect forwarding. Authentication rejection remains distinct from a network
retry. Uncertain commands are never automatically replayed.

Fleet retains the failure category while retrying instead of showing an endless
Connecting label. Diagnostics expose a fixed category and numeric error code,
including before a first successful connection; copied reports omit URLSession
descriptions, URLs, headers and credentials. `--connection-diagnostics` adds
opt-in redacted console traces and an HTTPS health probe for device debugging.

On Hub restart persisted machines load Offline, with last-known session metadata
and pending routing. Payloads are rehydrated from the Agent/Codex, not SQLite.
Agent reconnect never resends uncertain operator commands; `UNKNOWN_OUTCOME`
requires deliberate investigation. ACK remains distinct from canonical completion.

## Pending requests: one canonical store

`Hub.requests` drives snapshots, Fleet state, Inbox, inline context and push
routing. A request creates enough session metadata even when its thread is absent
from history pages. A same-epoch periodic snapshot cannot remove an observed
unresolved request by omission. A complete reconnect replay reconciles absence;
`serverRequest/resolved` retires it immediately. The legacy `expires_at` field is
advisory: elapsed wall time alone no longer resolves a Codex request.

Duplicate request replay preserves the request incarnation and one-shot answer
reservation. Local UI disconnection, route changes and last-known offline state
cannot remove the canonical request. Native form identity uses machine, session,
request, turn and creation identity, not list position or snapshot instance.

An `agentMessage.questions` display item is different from a pending server RPC.
Do not synthesize `CanAnswer`, resolution, or a Follow-up-based answer for an
asynchronous display question. The prior reported question incident involved
this field being discarded and a question outside the recent item window; the
existing bounded question-content transport and paginated transcript preserve
it. Supported blocking RPC recovery is tested separately.

## Operational set and history

Loaded threads are paginated independently of the recent historical catalogue.
Working, Needs You, loaded threads and sessions pinned by requests precede cold
metadata when enforcing the bounded catalogue. Incomplete replay or an oversized
live set fails synchronization instead of silently removing active work. Cold
sessions remain read-only until explicitly attached. Conversation history remains
on-demand and paginated from Codex.

The initial snapshot caps metadata at 256 sessions per machine, prioritizing the
operational set. `catalogue` commands fetch independent 100-thread cursor pages
from Codex only when requested. They do not subscribe threads, replace canonical
session state, enter the Agent command-result cache, or persist a second catalogue.
The native All Sessions view merges discovered metadata beneath canonical state
and bounds its discovery cache to 1024 entries. Paging can be restarted; older
pages are fetched again from Codex rather than retained indefinitely.

An unknown canonical machine/thread identity may be read or explicitly attached,
never directly controlled. Opening cold history reads metadata without resuming
the thread; explicit Attach retains the existing control admission checks.
Codex 0.162.0 can reject `thread/resume` when another client holds the active
writer. Relay classifies this as `THREAD_BUSY` and leaves the thread read-only;
it does not take over that writer or imply that a draft was sent.
Reconnection does not enumerate all cold pages. Tests cover 600 discovered
threads, a full initial catalogue with Working/pending threads outside it, and
canonical pending state taking precedence over stale discovery metadata.

## Diagnostics and account foundation

Authenticated `GET /api/diagnostics` exposes an explicit allowlist: Hub/Agent/
protocol/Codex versions, adapter, connection/epoch, heartbeat/event/snapshot times,
sequence, snapshot watermark, reconnect count, last disconnect reason, snapshot
age, snapshot duration, initial connection-to-Online duration, and bounded
Agent-to-Hub timing aggregates. No transcript, credentials, account identity,
request context or tool arguments are included in this endpoint.

Agent timestamps are observation times, not model-emission timestamps. Hub receipt
uses the Hub clock. Native receipt and reducer duration are held in bounded memory
and shown in connection diagnostics. Cross-host deltas include clock offset;
negative or implausible values are flagged, not presented as precise latency.
Reducer duration is not a measurement of SwiftUI frame rendering. There is no
persistent high-frequency event log or SQLite write on every heartbeat.

Account snapshots and sparse updates carry only typed identity/plan, rate-limit
windows, credit balances and spend-control data, with Codex source/observation
metadata. Token usage contains counters, not reasoning or conversation content.
Unknown/authentication fields are discarded. Login tokens remain on the worker.
