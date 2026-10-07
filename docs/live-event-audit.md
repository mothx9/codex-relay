# App-server event audit

Audited against the installed Codex CLI 0.160.1 JSON schema generated with
`codex app-server generate-json-schema --experimental`, and the
[official app-server documentation](https://learn.chatgpt.com/docs/app-server).
Schema availability is not proof that every event occurred in this deployment.
Relay does not expose model reasoning.

| Codex event / API | Adapter and Agent | Hub | Native |
| --- | --- | --- | --- |
| `thread/status/changed` | Canonical session event; recognizes `waitingOnApproval`, `waitingOnUserInput` and legacy `waitingFor…` | Current session plus canonical pending overlay | Session state gated by machine freshness |
| `turn/started`, `turn/completed` | Turn identity/state; completion/failure separated | Ordered control events | State and elapsed turn; outbox completion still canonical |
| `item/agentMessage/delta` | Incremental visible assistant text | Ephemeral watched-session buffer | Incremental transcript |
| `item/started`, `item/completed` | User-visible message, command, file and MCP activity | Ephemeral activity and bounded fleet summary | Stable activity identity / running or final state |
| `item/commandExecution/outputDelta` | Command-output delta | Watched-session stream | Incremental terminal output |
| `item/commandExecution/terminalInteraction` | M2: canonical interaction marker; stdin and process ID omitted | Watched-session progress, separate from output | Input-sent marker; does not replace command output |
| `item/fileChange/patchUpdated` | M2: replaces the bounded patch under the existing item identity | Ephemeral activity replacement | File sections and diff update before completion |
| `item/fileChange/outputDelta` | Deprecated in the installed schema; server does not emit it | No fabricated output | File patches and turn diff are used |
| `turn/diff/updated` | Progressive patch | Ephemeral watched-session stream | Current diff |
| `item/mcpToolCall/progress` | M2: bounded progress message, stale completed-item progress rejected | Watched-session progress; no fleet-wide text fan-out | Current progress under the existing tool item |
| `thread/queue/changed` | Canonical queue reread; no Relay-owned queue | Ephemeral queue event | Identity-based optimistic reconciliation |
| `thread/tokenUsage/updated` | Typed token counters, source and observation time | Session accounting metadata | M2: counters in Session Info |
| command/file/permissions approval, `item/tool/requestUserInput`, `mcpServer/elicitation/request` | Supported pending RPC mapping; replay pins session | One canonical pending map, metadata persistence, private watched form context | Fleet, Inbox and inline form derive from the same request identity |
| `serverRequest/resolved` | Removes canonical local pending request once | Removes Hub request and reservation | Removes request across routes |
| `account/updated`, `account/rateLimits/updated` | Allowlisted typed account event and sparse quota merge | Canonical account metadata / fleet snapshot | M2: derived Account Registry and dynamic usage windows |
| `account/read`, `account/rateLimits/read` | Read without token refresh; source/freshness metadata | Snapshot account foundation | No Relay-side authentication |
| reasoning deltas, auth token refresh RPCs | Not forwarded | No reasoning/auth payload | No reasoning/auth payload |

## Loss and delay findings

- Hub transport acceptance previously retained a machine's old Online state;
  reconnect now immediately publishes Syncing.
- A degraded empty snapshot previously replaced last-known sessions. It now
  changes connectivity without inventing a new Codex task state.
- Local 24-hour expiry could retire an unresolved supported request without a
  Codex resolution; it no longer does.
- Pending events for unknown sessions and snapshot catalogue bounds could hide
  the request's session. Pending requests now create/pin sufficient metadata.
- Loaded-thread pagination was ignored; subscription failures were silently
  omitted. Pages are now followed and incomplete active-state replay fails sync.
- Hub restart did not reload persisted pending routing. It now loads that routing
  Offline and rehydrates sensitive context from Codex. Snapshot replacement is
  atomic, so a mid-update failure cannot erase the durable request set.
- Replayed requests could receive a new local creation time / answer reservation.
  Their incarnation now remains stable within the adapter epoch.
- An asynchronous subscription task could publish captured older session metadata.
  Publication now reads current session metadata under the sequencing lock.
- Before M1, the earlier refresh fix already flushed ephemeral transcript events
  through the snapshot watermark. M1 preserves its regression test; accepting a
  metadata snapshot must never discard unseen assistant or terminal deltas.
- The historical question report involved `agentMessage.questions` being omitted
  from adapter/native display data and lying outside the recent item window. It
  had already been answered elsewhere. Existing tests preserve question-only
  messages, bounded question content and canonical history. This is distinct
  from the supported pending-RPC recovery tests and should not be relabelled a
  still-pending request.

## Latency interpretation

Snapshot duration measures local Codex enumeration/subscription. Connection to
Online additionally includes serialization and transport. Measurement found that
optional account/quota reads previously added hundreds of milliseconds to over a
second to this path. Those reads now run in a separate bounded worker and publish
canonical account events: they cannot delay Online or pending-request delivery.
A slow account provider does not block the control stream.

Agent event timestamps are adapter observation times. Hub receipt minus Agent
observation estimates transport/queueing plus cross-host clock offset. Native
receipt minus Hub observation has the same clock caveat. Native reducer time
measures state application, not rendering or model computation. Diagnostics keep
bounded aggregates and do not persist the high-frequency stream.

## M2 operational presentation

MCP completion retains at most 4 KiB of text result or error summary. Binary
content, embedded resources, `_meta`, arbitrary argument values and structured
payloads are not forwarded. This intentionally provides a text summary rather
than a second MCP transport. Summaries and progress count toward ephemeral
memory budgets. Terminal input is never copied into Relay.

Progress updates are additive protocol events (`tool_progress`,
`terminal_interaction`) scoped to session watchers. They update the existing
activity ID without replacing text/output. File patches use the existing
`activity` event and file fields. Older clients continue to receive ordinary
item lifecycle events. The PWA also renders progress and text summaries.

Native transcript observation is scoped away from the composer/header.
Markdown parsing runs at most one job per visible message and coalesces pending
text over a 100 ms window without waiting for the stream to finish. This is a
presentation throttle, not an added transport delay. Operational state changes
remain immediate. Terminal detail separates command/status/exit/duration from
collapsible output; the latest operation starts expanded.
