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

Resolution is confirmed by Codex's `serverRequest/resolved`, including decisions made elsewhere. Observed unresolved requests remain canonical until Codex resolution or complete reconnect reconciliation; elapsed time alone does not resolve an upstream request. Lost command outcomes are surfaced as uncertain, never retried silently. Start and steer have current-state/turn preconditions; final enforcement remains Codex's responsibility. Unsupported requests require local handling.

A private fallback server cannot prove that an independent local UI has stopped working on the same stored thread. Do not resume the same thread concurrently in separate runtimes. Shared-daemon mode is the default and has been tested with two clients.

## Data and limits

The SQLite schema accepts only control metadata. Chat, full command/approval descriptions, request payloads and user answers stay in bounded RAM, not a transcript database. Session titles/project paths are metadata and can still be sensitive. The database contains encrypted-push subscription material and must remain private.

Secret files must be regular files with permissions 0600. The state directory is created as 0700. Do not commit `.relay`, `*.token`, `*.secret`, DB/WAL files or `.env`; they are ignored. Provision tokens through a trusted channel and remove staging copies. Keep VAPID keys stable and private across upgrades.

Logging excludes prompts, command payloads, account tokens and push endpoints. Errors delivered from Codex to the browser are deliberately generic because RPC errors can quote input. Login attempts, message sizes, fleet capacity, queues, pending requests, subscribers and ephemeral buffers are bounded. Slow subscribers are disconnected. The push service allowlist prevents arbitrary authenticated subscription URLs becoming an outbound SSRF proxy; redirects are disabled.

The Service Worker caches only the static application shell, never API responses or transcripts. The browser does not create a transcript in localStorage/IndexedDB. Privacy mode hides machine/project names on notifications by default. A notification only deep-links into the authenticated UI and cannot approve a request.

## Reporting

For sensitive issues, contact the repository owner's GitHub profile before publishing credential-bearing evidence. Public reports must omit tokens, prompts, private paths and push endpoints. This is a young privileged tool: verified paths and remaining acceptance gaps are recorded in versioned reports under docs/. Restrict ingress to trusted networks while performing initial acceptance.


## Short device pairing

Authenticated operators (or the local Hub owner via `codex-relay pair`) may mint an 8-digit random code. It is kept only as a hash in bounded Hub RAM (maximum eight pending codes), expires after five minutes, is tied to operator/agent enrollment, and is consumed atomically before credential issuance. Hub restart invalidates codes. Exchange attempts have a Hub-wide limit of 20 per minute; origin/CSRF checks apply to all requests. Anyone possessing a valid code can enroll, so display it privately. Pairing a machine never silently replaces an existing credential.

Paired operator devices receive distinct random credentials, hashed in SQLite and valid for 90 days. Native clients store them in the iOS Keychain with `ThisDeviceOnly` protection; web clients use Secure/HttpOnly/SameSite cookies. No bootstrap token goes to the phone. Operators can revoke or remove devices; connected sockets close immediately, and HTTP/command routing rejects revoked access. All paired operators have full single-user control privileges; there is no multi-user role model.

Pausing/removing an agent changes its Relay access and derived Fleet metadata. It does not stop Codex, delete its threads, log out the OpenAI account or change the machine network. Machine account data is restricted to typed supported identity, plan, usage windows, credits, limits and token counters from the authenticated local runtime; unknown authentication and workspace-routing data is discarded. OpenAI account-wide session management is outside the app-server protocol.

Optional native APNs uses an owner-supplied ES256 key, never checked in. Config and key files require mode 0600. The Hub alone signs provider requests and connects to fixed Apple APNs endpoints; agent hosts remain unaware of notifications. Registrations are bound to paired device IDs; expired/revoked devices receive no push. Private lock-screen text is the default. Apple development team, signing/provisioning and Push Notifications capability are required for real native delivery; tests with an HTTP fake are not delivery proof.

See the [trust-boundary diagram](docs/assets/architecture/trust-boundaries.svg),
[access model](docs/architecture/access.md), [notification routing](docs/architecture/notifications.md)
and [test isolation](docs/development/test-isolation.md) for current implementation details.
