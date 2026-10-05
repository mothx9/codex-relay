import test from "node:test";
import assert from "node:assert/strict";
import { Outbox, messageKind, canSend, reconcileActivity } from "./control.mjs";

const working = {
  status: "WORKING",
  turn_id: "turn",
  capabilities: { can_follow_up: true, can_steer: true },
};
test("context selects New Turn, Follow-up and Answer; Steer is explicit", () => {
  assert.equal(messageKind({ status: "READY" }), "new_turn");
  assert.equal(messageKind(working), "follow_up");
  assert.equal(messageKind(working, true), "steer");
  assert.equal(messageKind({ status: "NEEDS_YOU" }), "answer");
});
test("WORKING grants no capability; follow-up does not require a turn ID", () => {
  assert.equal(canSend({ status: "WORKING", turn_id: "turn" }, "steer"), false);
  assert.equal(canSend({ ...working, turn_id: "" }, "steer"), false);
  assert.equal(canSend({ ...working, turn_id: "" }, "follow_up"), true);
  assert.equal(
    canSend({ read_only: true, capabilities: { can_answer: true } }, "answer"),
    true,
  );
});
test("follow-up LOCAL -> SENDING -> QUEUED -> DISPATCHED -> MATERIALIZED", () => {
  const box = new Outbox(),
    v = box.add("cmd", "session", "follow_up", "after this");
  assert.equal(v.phase, "LOCAL");
  box.sending(v.id);
  assert.equal(v.phase, "SENDING");
  box.result({ id: v.id, ok: true, queue_id: "native" });
  assert.equal(v.phase, "QUEUED");
  assert.equal(v.text, "after this"); // ACK is not completion or materialization.
  box.disconnected();
  assert.equal(v.phase, "QUEUED");
  box.dispatched("session", "cmd");
  assert.equal(v.phase, "DISPATCHED");
  box.materialize("session", { kind: "userMessage", client_id: "cmd" });
  assert.equal(v.phase, "MATERIALIZED");
  assert.equal(box.visible("session").length, 0);
});
test("canonical materialization before RPC ACK never regresses", () => {
  const box = new Outbox(),
    v = box.add("cmd", "session", "follow_up", "text");
  box.materialize("session", { kind: "userMessage", client_id: "cmd" });
  box.result({ id: "cmd", ok: true });
  box.queue("session", [{ id: "q", client_id: "cmd", text: "text" }]);
  assert.equal(v.phase, "MATERIALIZED");
});
test("failed queue and stale Steer retain text and never resend or convert", () => {
  const box = new Outbox();
  for (const kind of ["follow_up", "steer"]) {
    const v = box.add(kind, "session", kind, "keep this");
    box.sending(kind);
    box.result({
      id: kind,
      ok: false,
      error_code: "TURN_CHANGED",
      error: "safe",
    });
    assert.equal(v.phase, "FAILED");
    assert.equal(v.text, "keep this");
    assert.equal(v.kind, kind);
  }
  assert.equal(box.items.size, 2);
});
test("disconnect marks uncertain sends UNKNOWN_OUTCOME without retry", () => {
  const box = new Outbox(),
    v = box.add("cmd", "session", "follow_up", "keep");
  box.sending("cmd");
  box.disconnected();
  assert.equal(v.errorCode, "UNKNOWN_OUTCOME");
  assert.equal(v.text, "keep");
  assert.equal(box.items.size, 1);
});
test("restart rehydrates native queue, never creates a submission", () => {
  const box = new Outbox(),
    queue = [{ id: "native", client_id: "cmd", text: "owned by Codex" }];
  box.queue("session", queue);
  box.queue("session", queue);
  assert.equal(box.visible("session").length, 1);
  assert.equal(box.visible("session")[0].phase, "QUEUED");
});
test("userMessage item replay and repeated client ID produce one canonical bubble", () => {
  const chat = [];
  reconcileActivity(chat, { id: "item", client_id: "cmd", text: "canonical" });
  reconcileActivity(chat, { id: "item", client_id: "cmd", text: "canonical" });
  reconcileActivity(chat, {
    id: "item-again",
    client_id: "cmd",
    text: "canonical",
  });
  assert.equal(chat.length, 1);
});
test("bounded outbox rejects overflow, has TTL, no cross-thread matching", () => {
  const box = new Outbox();
  for (let i = 0; i < 32; i++)
    box.add(String(i), "session", "follow_up", "pending", 0);
  assert.throws(() => box.add("overflow", "session", "follow_up", "more"));
  box.materialize("different-thread", { kind: "userMessage", client_id: "0" });
  assert.equal(box.visible("session").length, 32);
  box.prune("", 300001);
  assert.equal(box.items.size, 0);
});
