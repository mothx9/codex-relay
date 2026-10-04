# Security

Relay can ask Codex to execute actions with the user's local privileges. Treat its operator and machine credentials as privileged access.

## Boundaries

- Codex login credentials stay entirely with local Codex. Relay uses its authenticated local daemon connection and does not read credential files or forward account secrets.
- Every agent has a distinct high-entropy bearer token. SQLite stores SHA-256 token hashes, not raw tokens. Rotation/revocation is machine-specific. Revoked agents cannot route new commands; existing sockets close during the next maintenance pass (15 seconds maximum).
- A high-entropy bootstrap token is exchanged for a 12-hour random server-side operator session. Cookies are HttpOnly, SameSite=Strict, and Secure for HTTPS public origins. No admin token in browser localStorage.
- Mutating HTTP requests require exact Origin, JSON and `X-Relay-CSRF: 1`. Operator WebSockets require both a current cookie and exact nonempty Origin. Agent sockets require bearer authentication and reject browser Origin headers. No cross-origin API permission is granted.
- Production requires HTTPS/WSS. The hub listener defaults to loopback; plaintext external use requires an explicit `--insecure-http` development flag. Reverse proxies must preserve WebSocket upgrades and use the exact configured public origin.
- The adapter's Unix socket defaults to the existing local daemon; explicit Codex TCP endpoints are limited to loopback. The agent exposes no Internet listener.

## Actions and uncertainty

Approval IDs are one-shot and scoped to the machine/thread. Both hub and adapter prevent repeat submission. Only accept-once/reject are exposed for command/file approvals. Permission grants are limited to the requested profile and **this turn**, explicitly labelled as such. No session grants, reusable execution-policy amendment or approval bypass is offered. File approvals without proposed-file context cannot be approved.

Resolution is confirmed by Codex's `serverRequest/resolved`, including decisions made elsewhere. Requests expire locally after 24 hours; resolve any remaining upstream request through local Codex. Lost command outcomes are surfaced as uncertain, never retried silently. Start and steer have current-state/turn preconditions; final enforcement remains Codex's responsibility. Unsupported requests require local handling.

A private fallback server cannot prove that an independent local UI has stopped working on the same stored thread. Do not resume the same thread concurrently in separate runtimes. Shared-daemon mode is the default and has been tested with two clients.

## Data and limits

The SQLite schema accepts only control metadata. Chat, full command/approval descriptions, request payloads and user answers stay in bounded RAM, not a transcript database. Session titles/project paths are metadata and can still be sensitive. The database contains encrypted-push subscription material and must remain private.

Secret files must be regular files with permissions 0600. The state directory is created as 0700. Do not commit `.relay`, `*.token`, `*.secret`, DB/WAL files or `.env`; they are ignored. Provision tokens through a trusted channel and remove staging copies. Keep VAPID keys stable and private across upgrades.

Logging excludes prompts, command payloads, account tokens and push endpoints. Errors delivered from Codex to the browser are deliberately generic because RPC errors can quote input. Login attempts, message sizes, fleet capacity, queues, pending requests, subscribers and ephemeral buffers are bounded. Slow subscribers are disconnected. The push service allowlist prevents arbitrary authenticated subscription URLs becoming an outbound SSRF proxy; redirects are disabled.

The Service Worker caches only the static application shell, never API responses or transcripts. The browser does not create a transcript in localStorage/IndexedDB. Privacy mode hides machine/project names on notifications by default. A notification only deep-links into the authenticated UI and cannot approve a request.

## Reporting

For sensitive issues, contact the repository owner's GitHub profile before publishing credential-bearing evidence. Public reports must omit tokens, prompts, private paths and push endpoints. This is a young privileged tool: verified paths and remaining acceptance gaps are recorded in VALIDATION.md. Restrict ingress to trusted networks while performing initial acceptance.
