# Codex compatibility discovery

Installed CLI and existing managed daemon: **0.160.0**. Discovery and live acceptance performed on Linux amd64, 2026-10-04. The shared daemon was already serving local CLI/VS Code work and was not stopped or restarted.

## Local inspection before integration

Examined `codex --version`, `codex --help`, `codex app-server --help`, `daemon version`, `proxy --help`, `queue --help`, and the installed output of `generate-json-schema --experimental`. Generated schemas and local session data are not committed. Relay implements minimal adapter types rather than copying the full upstream schema.

Official transports include stdio, TCP WebSocket and WebSocket over Unix sockets. **`app-server proxy` forwards raw transport bytes**, not JSON-lines RPCs for the shared daemon. An initial JSON-lines proxy probe timed out; a proper WebSocket handshake over `~/.codex/app-server-control/app-server-control.sock` succeeded. This is Relay's default. Explicit private supervised stdio is a fallback.

## Second-client compatibility: observed results

| Primitive/boundary | Experiment/result |
| --- | --- |
| Existing UI sessions | Second connection `initialize`, `thread/list`, `thread/loaded/list` and `thread/read` returned existing CLI/VS Code threads, including active work. Pagination later enumerated 225 threads. |
| Active status | `thread/read` reported real active/idle state. List responses omit `canAcceptDirectInput`; metadata read/resume provides it. |
| Live subscription | `thread/resume` with `excludeTurns: true` and no settings overrides attached to an already loaded active thread. Relay received status, item, message delta and completion events from a turn initiated through another client. |
| Recent context | Actual `thread/turns/list` and descending paginated `thread/items/list` worked. Relay uses one bounded 40-item page on demand. |
| Start/control | PWA messages initiated real turns on the existing thread. `turn/steer` accepted a message during an actual seven-second command window and requires `expectedTurnId`. |
| Queue/follow-up | `thread/queue/add` requires `clientUserMessageId`. A queued message automatically started after the running turn; both markers returned through the live UI. It is Codex's queue, not a Relay scheduler. |
| Pending replay | One client initiated a harmless approval-required `printf`; the attached second Relay client received the pending server request. Reconnect/resume exposes unresolved requests. |
| Resolve elsewhere | The primary connection declined that request; Relay received `serverRequest/resolved` and withdrew its form without answering again. |
| Resolve through Relay | A subsequent real command approval was accepted once through the PWA. Codex executed it and returned to READY. WORKING → NEEDS_YOU → WORKING → READY was observed. |
| Structured input | A real plan-mode `request_user_input` offered Alpha/Beta. The PWA selected Alpha, sent the structured answer and received the completed response. |
| Local coexistence | Two clients observed/controlled the same shared-daemon test thread. Existing unrelated local sessions were listed/subscribed without sending them commands or changing their configuration. |
| Missing RPCs | No `thread/subscribe`; resume is the subscription boundary. A real `serverRequest/list` call failed as an unknown method. Relay does not depend on either. |
| Newly allocated thread | A second-client resume before the first rollout failed with `no rollout found`. After a small first turn, secondary resume/start/stream/complete worked. The optional real integration test includes that prerequisite. |
| Idle runtime lifetime | A saved idle thread can unload when its final subscriber disconnects. It then becomes INACTIVE/read-only and requires explicit operator attach. This is visible rather than pretending continuous control. |

Only isolated validation threads received commands. No unrelated thread's approvals were answered. Relay hub and agent process restarts were exercised with the real shared daemon left running; a new real message succeeded afterwards. Codex-daemon restart is covered by a fake-backend disconnection/rehydration test, not a destructive restart of the daemon serving other work.

## 2026-10-05 canonical follow-up protocol verification

Regenerated experimental JSON schemas from the installed **0.160.0** CLI before changing control flow. Rechecked official `openai/codex` queue processing; no upstream schema/code was copied into Relay. Separate harmless validation threads exercised a running turn, queue add/list/change, automatic next turn and canonical user messages.

| Official surface | Installed schema and real observation |
| --- | --- |
| `thread/queue/add` | Requires `threadId`, input and `clientUserMessageId`. Response `queuedSubmission` contains native `id`, the same `clientUserMessageId` and input. Exact identity matched the submitted Relay command ID. |
| `thread/queue/list` | Bounded paginated `data` contains queued submissions with both IDs and input. Accepted validation follow-up appeared with the exact identity. |
| `thread/queue/changed` | Contains `threadId`, not a full queue. Observed on queue changes; adapter refreshes through the official list RPC, without polling. |
| `turn/start` / `turn/steer` | Accept client identity. Steer retains `expectedTurnId`; a stale turn is a canonical TURN_CHANGED error, never a queued instruction. |
| `turn/started` | Schema permits items, but **actual items were empty** in these runs. Do not infer follow-up identity from this event or FIFO ordering. |
| `item/started`, `item/completed` | A queued canonical `userMessage` exposed `clientId` equal to the submitted `clientUserMessageId`. The started event identifies dispatch; the actual item replaces the browser outbox bubble. |
| `thread/items/list` after completion | Independently reread the completed validation thread: the follow-up userMessage retained its exact `clientId`, turn ID and item ID. Reconnect reconciliation therefore uses identity in recent history too. |

The native queue executed the follow-up after the first turn and produced two independent turn/completed events. Queue ACK alone did not change the running turn to READY. The real PWA showed IN CODA while working, survived a browser connection loss plus local hub restart with **one follow-up submission**, then displayed one canonical user message. Explicit steer and new-turn controls also reached the real daemon. No text/timestamp fallback is needed for this tested protocol because a correlatable ID exists both live and in recent history.

The adapter treats missing/false `canAcceptDirectInput` as read-only. Normalization alone cannot grant steer. Pending server requests separately grant answer capability and are withdrawn by official `serverRequest/resolved`.

## Implemented protocol surfaces

Installed schema and adapter contract tests cover `turn/start`, `turn/steer`, `turn/interrupt`, native `thread/queue/add`, command/file/permissions approval, structured user input and MCP form elicitation. Event normalization includes `thread/status/changed`, `turn/started`, `turn/completed`, agent-message streaming, command output, item/file changes, `turn/diff/updated` and `serverRequest/resolved`.

File approval, permission approval, MCP elicitation, interrupt and FAILED notification handling have contract/fake tests. They are not all claimed as exercised against real Codex. MCP URL elicitation and unsupported legacy/dynamic requests require local handling. Approval is unavailable if the proposed operation is missing or clipped; reusable grants/amendments are not exposed.

## Ownership fallback

Shared daemon: resume the already loaded thread to subscribe, without configuration overrides. Relay does not start a new runtime and can coexist with an attached local client. Historical unloaded threads require an explicit attach.

Private stdio: a process owns its own runtime. A history record visible there does not prove another TUI/desktop process's live turn or pending request is controllable. Relay marks it read-only until explicitly resumed in that private runtime and documents the concurrency boundary. Restarting a private agent restarts its owned server. No scraping, ANSI parsing, terminal automation or tmux fallback is used.

## Official comparison sources

Compared the installed protocol with the official app-server documentation and upstream `openai/codex` main at **`c2f7fe89d87ce853900d0b5cb1f5dc4863e44d73`**, commit dated 2026-10-04T16:57:01Z:

- [Official app-server documentation](https://learn.chatgpt.com/docs/app-server)
- [Official Codex repository at inspected revision](https://github.com/openai/codex/tree/c2f7fe89d87ce853900d0b5cb1f5dc4863e44d73)
- `codex-rs/app-server-transport/src/transport/unix_socket.rs`
- `codex-rs/app-server-daemon/src/client.rs`
- `codex-rs/app-server/src/request_processors/thread_processor.rs`
- `codex-rs/app-server/src/request_processors/thread_queue_processor.rs`
- `codex-rs/app-server/src/thread_state.rs`
- `codex-rs/app-server/src/outgoing_message.rs` (pending-request replay on thread attachment)

The installed generated protocol remains authoritative for this adapter. Other Codex versions, ARM hosts and macOS runtime behavior require their own acceptance checks.
