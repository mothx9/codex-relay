# Provider boundary audit

Codex Relay supports Codex. M2 does not add another provider, rename the project
or introduce an abstract provider framework without a concrete implementation.
The useful boundary is the existing local adapter.

| Concept | Classification | Boundary |
| --- | --- | --- |
| Machine, connection freshness, epoch, snapshot, capability | Generic Relay | Canonical protocol/Hub |
| Session identity, running activity, command/tool/file/diff | Generic Relay presentation | Normalized before routing |
| Pending request, one-shot decision, resolution | Generic control semantics | Hub canonical request store |
| Account identity, usage window, source/freshness | Generic derived metadata | Typed allowlist from runtime |
| Thread/turn IDs and Codex queue identity | Codex-backed canonical identifiers | Kept for correct reconciliation, not renamed speculatively |
| `turn/steer`, `thread/queue/update`, `serverRequest/resolved` | Codex-specific RPC | `internal/codex` |
| Raw upstream event label | Codex-specific diagnostic metadata | Never a UI label or client dispatch contract |

Concrete M2 mappings normalize MCP progress, terminal input interaction and file
patch updates inside the adapter. Terminal stdin is replaced with a generic
operational indication; it is not forwarded. Tool result transport keeps bounded
text summary and discards arbitrary structured/auth fields. Account registry and
native screens consume typed Relay fields rather than calling OpenAI or Codex
RPCs directly.

Compatibility fields such as `thread_id`, `turn_id`, `raw_status` and `raw_event`
remain where existing consumers/reconciliation need them. They do not justify
coupling new presentation logic to raw app-server enum spelling. A future provider
must first demonstrate compatible command/currentness/pending-request semantics;
there is no claim that existing Codex control can be universally substituted.

The final coherence pass adds no upstream RPC dispatch to native views. Live
question hints consume normalized Relay Activity questions and event turn identity;
choosing an option only prepares an ordinary composer draft. The Hub pending store
and adapter boundary are unchanged.

Image input maps to Codex data URLs only inside the adapter; the Relay contract
accepts bounded typed bytes. Codex async-reply envelopes are decoded there into
generic question/answer presentation metadata. Native views do not parse Codex
XML/JSON wrappers and do not infer a pending lifecycle from them.
