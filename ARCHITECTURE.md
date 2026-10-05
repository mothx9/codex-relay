# Architecture

Codex Relay is a transport/control plane, not another AI runtime.

- **Codex thread = source of truth.** History and queued messages stay in Codex. Relay calls official app-server RPCs and never reconstructs a conversation as a separate thread.
- **Relay state = derived/control state.** ONLINE/OFFLINE/DEGRADED machines and NEEDS_YOU/WORKING/READY/INACTIVE/FAILED sessions are canonical UI states. Raw method/status names are debugging hints, not UI state proliferation.
- **Agent = Codex adapter host.** All RPC names, transport framing, capability boundaries and pending response shapes live in `internal/codex`. The agent handles only the stable backend interface and canonical Relay messages. The preferred transport is an existing shared daemon's WebSocket-over-Unix socket.
- **Hub = routing.** One Go HTTP server routes authenticated agent/operator WebSockets, serializes metadata updates, gates one-shot decisions and sends notifications. It never executes inference or shell commands itself.
- **PWA = operator client.** Static HTML/CSS/ES modules are embedded in the binary. A PWA never connects directly to Codex. Authentication uses a server-side session and HttpOnly cookie. No JS server runtime is deployed.
- **SQLite = metadata only.** WAL, one database connection, bound parameters and transactional snapshot replacement. Persist machine/session metadata, request routing identity, token hashes, push subscriptions, bounded audit/dedupe. Request descriptions, commands, payloads, chat and answers are excluded from writes.
- **Chat = ephemeral.** Fetch at most 40 recent Codex items on demand; use bounded 50-item/128-KiB RAM windows, a five-minute TTL and at most 64 hub buffers. Completed item IDs replace streamed deltas. Last viewer close drops the buffer. Browser caches shell assets only.
- **Push = notification channel.** The hub owns VAPID and subscriptions. Semantic identities (session/turn/item) dedupe replay across Relay restart. A push message contains a privacy-conscious summary and deep link; never execution authority. Open the authenticated PWA to act.
- **Network = transport agnostic.** LAN, Tailscale or other IP routing can carry HTTPS/WSS. Relay implements no VPN; the binary and installer do not modify routing or Wi-Fi. Host network setup is a separate deployment operation. Keep production ingress HTTPS and Codex local.

## One reference deployment

A hub can technically run on any supported host. The reference installation uses one canonical always-on **Zima hub**, with outbound Exon, Spark and MacBook agents beside their existing shared Codex daemons. The actual cutover remains pending trusted Zima access; [VALIDATION.md](VALIDATION.md) records the observed deployment status. The Exon loopback validation hub is a temporary rollback environment and is stopped only after the Zima control path passes real acceptance. There must never be two production hubs, databases or fleets.

```text
              iPhone / Browser
                     |
                 HTTPS / WSS
                     |
          ZIMA: Hub + PWA + Web Push
          routing + metadata SQLite
                     ^
            outbound Agent WebSockets
          +----------+----------+
          |          |          |
         EXON       SPARK     MACBOOK
         Agent      Agent      Agent
          |          |          |
        local      local       local
        Codex      Codex       Codex
```

Zima executes no Codex inference. Codex credentials stay on the agent hosts.

## Canonical message controls

```text
Message
  New Turn   READY      -> turn/start
  Follow-up  WORKING    -> thread/queue/add (normal submit)
  Answer     NEEDS_YOU  -> matching server request response
  Steer      explicit   -> turn/steer with expectedTurnId
Interrupt    explicit   -> turn/interrupt
```

FOLLOW-UP and STEER are different instructions. A normal WORKING composer submit always means follow-up, never a current-turn intervention. Steer requires ONLINE machine, writable session, WORKING state, explicit `can_steer`, and an active turn ID. Follow-up requires `can_follow_up` but not an active turn ID. Answer uses `can_answer` from an outstanding server request; direct-input permission alone does not revoke an already-addressed request. Machine offline state disables controls. The browser does not derive these capabilities from status alone.

The ephemeral browser outbox shows LOCAL → SENDING → QUEUED → DISPATCHED → MATERIALIZED, or FAILED. Steer has STEERING → APPLIED/FAILED. A command ACK is independent of turn completion. A failed command retains its text and offers explicit retry/alternative submission; a stale steer reports TURN_CHANGED and never becomes follow-up automatically. A selected steer retains its original turn identity if the turn changes while composing.

Codex's `clientUserMessageId` is the Relay command ID. Native queued submissions expose this identity and their own queue ID. Live and recent canonical userMessage items expose it as `clientId`; reconciliation replaces the optimistic item without copying a transcript to SQLite. `thread/queue/changed` triggers one bounded, event-driven `thread/queue/list` read. Queue removal alone does not prove dispatch: an exact userMessage identity does. On 0.160.0, `turn/started` has empty items in the observed runs; `item/started` provides the dispatch identity before materialization.

The outbox is bounded to 32 pending items / 128 KiB and 128 entries including materialized correlation metadata, with a five-minute inactive TTL. It is never stored in a DB, localStorage, IndexedDB or Service Worker cache. A reconnect fetches Codex-owned queue/recent items, never recreates submissions. UNKNOWN_OUTCOME stays unknown until canonical Codex evidence or an explicit operator decision. Safe Relay error codes preserve command/session identity; raw backend messages do not reach the browser.

Source-of-truth boundaries remain: Codex owns history, execution, follow-up queue and approvals; Relay derives fleet/session status, owns machine authentication and push subscriptions, and holds only ephemeral chat RAM. No transcript database exists.

## Ordering and reconnect

The adapter emits a random connection epoch and monotonically increasing sequence. Every event has its own ID, machine/session IDs, UTC timestamp, kind and sequence. A snapshot captures a sequence watermark while holding the adapter state lock. Events at or below that watermark are already reflected in its state and are discarded after announce. The hub rejects duplicate/reordered sequence numbers and stale snapshots within an epoch. WebSocket frames preserve ordering within a connection; reconnect always reconstructs a fresh Codex snapshot.

Agent-to-hub queues are bounded, with 128 outbound messages and 32 inbound commands. The Codex event queue is 256 messages. Overflow closes a connection and forces rehydration. The agent retains Codex connectivity through hub failures; transient conversation deltas can be discarded while disconnected because recent context is fetched from Codex again. There is no permanent Relay event log.

Command outcomes are cached in bounded agent RAM (1024 IDs, no history). `clientUserMessageId` is passed to Codex's start/steer/queue APIs. Controls are never automatically retried across uncertainty. A hub command timeout or lost connection reports unknown outcome. Approvals use an additional hub reservation plus an adapter sent flag, and are retired only after `serverRequest/resolved`. A request answered by another client is retired identically.

## Shared versus private ownership

Loaded threads on the shared daemon can be resumed with no settings overrides to atomically subscribe. Metadata-only reads and bounded history avoid full-history hydration. The tested server accepts control from the second attached client and replays unresolved requests. Saved unloaded threads need an explicit operator attach. Newly allocated zero-turn threads need their first rollout before another client can resume them.

An independent app-server has its own runtime. It may list history created by another process without owning its live turn. Private mode therefore requires explicit resume and does not claim coexistence with another non-shared UI. Restarting that private agent interrupts its owned process; the shared mode's restart leaves the daemon and local work alive.

## Resource bounds

Default fleet limits and retention are documented in README. SQL audit is capped at 1000 entries; push dedupe at 8192. There is no per-token DB write. Local discovery refresh is every two minutes as reconciliation alongside live subscriptions; heartbeat is every 25 seconds and stale connections time out after 75 seconds. Maintenance wakes every 15 seconds. No network polling exists in the UI; its minute timer updates labels only.

## Why no Telegram

A chat service would create an additional identity, message-history store and execution surface for privileged machine controls. An installed PWA with standard Web Push provides OS notifications and a direct authenticated control view without copying prompts and approvals to a third-party chat channel. Push services transport encrypted notification payloads; they do not carry Codex credentials or control commands.
