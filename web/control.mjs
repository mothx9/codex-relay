// Ephemeral operator state. Never serialized to browser storage or a Relay database.
export function messageKind(session, advanced = false) {
  if (session.status === "NEEDS_YOU") return "answer";
  if (session.status === "READY") return "new_turn";
  if (session.status === "WORKING") return advanced ? "steer" : "follow_up";
  return "";
}

export function canSend(session, kind) {
  const cap = session.capabilities || {};
  if (kind === "answer") return !!cap.can_answer;
  if (session.read_only) return false;
  if (kind === "new_turn") return session.status === "READY" && !!cap.can_send;
  if (kind === "follow_up")
    return session.status === "WORKING" && !!cap.can_follow_up;
  if (kind === "steer")
    return session.status === "WORKING" && !!session.turn_id && !!cap.can_steer;
  return false;
}

export class Outbox {
  constructor() {
    this.items = new Map();
  }
  add(id, session, kind, text, now = Date.now()) {
    if (this.items.has(id)) return this.items.get(id);
    const pending = [...this.items.values()].filter(
      (v) => v.phase !== "MATERIALIZED",
    );
    if (
      pending.length >= 32 ||
      pending.reduce((n, v) => n + v.text.length, 0) + text.length > 131072
    )
      throw new Error("Outbox pieno. Risolvi o scarta i messaggi precedenti.");
    const item = { id, session, kind, text, phase: "LOCAL", at: now };
    this.items.set(id, item);
    while (this.items.size > 128) {
      const old = [...this.items.values()].find(
        (v) => v.phase === "MATERIALIZED",
      );
      if (!old) break;
      this.items.delete(old.id);
    }
    return item;
  }
  sending(id) {
    const v = this.items.get(id);
    if (!v) return;
    v.phase = v.kind === "steer" ? "STEERING" : "SENDING";
  }
  result(result) {
    const v = this.items.get(result.id);
    if (!v || v.phase === "MATERIALIZED" || v.phase === "DISPATCHED") return;
    if (v.phase === "QUEUED" && !result.ok) return;
    if (result.ok) {
      v.phase =
        v.kind === "follow_up"
          ? "QUEUED"
          : v.kind === "steer"
            ? "APPLIED"
            : "ACCEPTED";
      v.queueId = result.queue_id;
      v.error = "";
      v.errorCode = "";
    } else {
      v.phase = "FAILED";
      v.errorCode = result.error_code;
      v.error = result.error;
    }
  }
  dispatched(session, clientId) {
    const v = this.items.get(clientId);
    if (v?.session === session && v.phase !== "MATERIALIZED")
      v.phase = "DISPATCHED";
  }
  materialize(session, activity) {
    if (!activity.client_id || activity.kind !== "userMessage") return;
    const v = this.items.get(activity.client_id);
    if (v?.session !== session) return;
    v.phase = "MATERIALIZED";
    v.text = "";
    v.error = "";
  }
  queue(session, entries) {
    for (const q of entries || []) {
      if (!q.client_id || !q.text) continue;
      let v = this.items.get(q.client_id);
      if (v && v.session !== session) continue;
      if (!v) {
        try {
          v = this.add(q.client_id, session, "follow_up", q.text);
        } catch {
          break;
        }
      }
      if (["MATERIALIZED", "DISPATCHED"].includes(v.phase)) continue;
      v.phase = "QUEUED";
      v.queueId = q.id;
      v.error = "";
      v.errorCode = "";
    }
    // Absence is not dispatch: the queue can also be deleted by another client.
    // A canonical turn/userMessage with clientId establishes dispatch/materialization.
  }
  disconnected() {
    for (const v of this.items.values()) {
      if (["SENDING", "STEERING"].includes(v.phase)) {
        v.phase = "FAILED";
        v.errorCode = "UNKNOWN_OUTCOME";
        v.error =
          "Esito sconosciuto. Verifica il thread Codex prima di reinviare.";
      }
    }
  }
  visible(session) {
    return [...this.items.values()].filter(
      (v) => v.session === session && v.phase !== "MATERIALIZED",
    );
  }
  prune(active = "", now = Date.now()) {
    for (const [id, v] of this.items)
      if (v.session !== active && now - v.at > 300000) this.items.delete(id);
  }
  clear() {
    this.items.clear();
  }
}

export function reconcileActivity(chat, activity) {
  const i = chat.findIndex(
    (v) =>
      v.id === activity.id ||
      (activity.client_id && v.client_id === activity.client_id),
  );
  if (i < 0) chat.push(activity);
  else chat[i] = activity;
}
