# Codex compatibility discovery

Local CLI and managed daemon: **0.160.0**. Discovery performed 2026-10-04.

Commands examined: `codex --version`, `codex --help`, `codex app-server --help`, `daemon version`, `proxy --help`, `queue --help`, and `generate-json-schema --experimental`.

The installed daemon was already running. It was not restarted. Official transports include stdio, WebSocket and WebSocket over Unix sockets. Important: `app-server proxy` forwards **raw transport bytes**; it is not a JSON-lines RPC client for the shared daemon. Relay will connect with a WebSocket handshake over the Unix socket. Private supervised app-server stdio is an explicit fallback only.

Read-only experiments against a second connection:

- `initialize` succeeds with experimental capability.
- `thread/list` returns existing CLI and VS Code sessions, including active ones. List results omit `canAcceptDirectInput`; a metadata `thread/read` exposes it for loaded sessions.
- `thread/loaded/list` returned five existing loaded threads.
- `thread/read` reports real active/idle state.
- `thread/resume` with `excludeTurns: true`, with no config overrides, succeeds on an already active thread and reports `canAcceptDirectInput: true`.
- `thread/turns/list` returns its actual `inProgress` turn; `thread/items/list` supports bounded descending retrieval.
- There is no `thread/subscribe` RPC. Resume is the subscription boundary.
- There is no `serverRequest/list` RPC: a real call returns unknown-method error. Pending replay on resume and live cross-client resolution require a separate experiment before being claimed.

Verified in generated installed schema: `turn/start`, `turn/steer` (requires `expectedTurnId`), `turn/interrupt`, `thread/queue/add` (requires `clientUserMessageId`), `thread/queue/list`, `thread/queue/start`; status and turn notifications; agent message, command output and diff notifications; command/file/permissions approval, structured user input, MCP elicitation, `serverRequest/resolved`.

An unloaded saved thread is inactive and read-only until the operator explicitly attaches/resumes it. A private app-server cannot prove ownership of a session running in a different process; Relay must mark that boundary read-only.

Sources examined (the installed generated schema is authoritative for this adapter):

- https://developers.openai.com/codex/app-server
- https://github.com/openai/codex
- `codex-rs/app-server-transport/src/transport/unix_socket.rs`
- `codex-rs/app-server-daemon/src/client.rs`

Generated schemas and local session data are not committed.
