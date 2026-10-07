import { Outbox, messageKind, canSend, reconcileActivity } from "/control.mjs";
const outbox = new Outbox();
const $ = (id) => document.getElementById(id);
const names = {
  NEEDS_YOU: "Needs you",
  WORKING: "Working",
  READY: "Ready",
  INACTIVE: "Inactive",
  FAILED: "Failed",
};
const priorities = ["NEEDS_YOU", "WORKING", "READY", "FAILED", "INACTIVE"];
const state = {
  machines: new Map(),
  sessions: new Map(),
  requests: new Map(),
  chat: [],
  filter: "all",
  group: "status",
  selected: "",
  steerMode: false,
  steerTurnId: "",
  socket: null,
  online: false,
  authenticated: false,
  retry: 0,
  commands: new Map(),
  index: 0,
  loading: false,
  publicKey: "",
};
let reconnectTimer,
  backgroundTimer,
  toastTimer,
  renderFrame,
  pendingSignature = "",
  hiddenAt = 0;
function node(tag, text, cls) {
  const n = document.createElement(tag);
  if (text != null) n.textContent = text;
  if (cls) n.className = cls;
  return n;
}
function toast(text) {
  $("toast").textContent = text;
  $("toast").hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => ($("toast").hidden = true), 6500);
}
async function api(path, body) {
  const response = await fetch(path, {
    method: body === undefined ? "GET" : "POST",
    headers:
      body === undefined
        ? {}
        : { "Content-Type": "application/json", "X-Relay-CSRF": "1" },
    body: body === undefined ? undefined : JSON.stringify(body),
    credentials: "same-origin",
    cache: "no-store",
  });
  if (!response.ok) {
    const error = new Error(await response.text());
    error.status = response.status;
    throw error;
  }
  return response.json();
}
function send(message) {
  if (state.socket?.readyState !== WebSocket.OPEN) {
    toast("Connessione non disponibile. Il messaggio non è stato inviato.");
    return false;
  }
  try {
    state.socket.send(JSON.stringify(message));
  } catch {
    return false;
  }
  return true;
}
function command(kind, extra = {}, id = crypto.randomUUID()) {
  if (state.commands.size >= 128) {
    toast("Troppe richieste in corso.");
    return "";
  }
  if (
    !send({
      type: "command",
      command: { id, kind, session_id: state.selected, ...extra },
    })
  )
    return "";
  state.commands.set(id, { kind, session: state.selected });
  return id;
}
function elapsed(value) {
  if (!value || value.startsWith("0001")) return "—";
  const seconds = Math.max(0, (Date.now() - Date.parse(value)) / 1000);
  if (seconds < 60) return "ora";
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h`;
  return `${Math.floor(seconds / 86400)}d`;
}
function machine(session) {
  return state.machines.get(session.machine_id);
}
function dot(status) {
  return node(
    "span",
    status === "NEEDS_YOU" ? "!" : status === "FAILED" ? "×" : "●",
    `dot ${status.toLowerCase()}`,
  );
}
function scheduleRender() {
  if (renderFrame) return;
  renderFrame = requestAnimationFrame(() => {
    renderFrame = 0;
    render();
  });
}
function render() {
  $("connection").textContent = !state.authenticated
    ? "Accesso richiesto"
    : state.online
      ? "Live · " +
        [...state.machines.values()].filter((m) => m.status === "ONLINE")
          .length +
        " macchine online"
      : "Offline · riconnessione";
  $("logout").hidden = !state.authenticated;
  $("settings-toggle").hidden = !state.authenticated;
  $("devices-toggle").hidden = !state.authenticated;
  if (!state.authenticated) { $("devices").hidden = true; $("settings").hidden = true; $("device-code").textContent = ""; }
  $("login-view").hidden = state.authenticated;
  $("fleet-view").hidden = !state.authenticated || !!state.selected;
  $("detail-view").hidden = !state.authenticated || !state.selected;
  if (!state.authenticated) return;
  if (state.selected) renderDetail();
  else renderFleet();
}
function renderFleet() {
  const sessions = [...state.sessions.values()];
  $("tabs").replaceChildren();
  for (const [value, label] of [
    ["all", "All"],
    ...priorities.map((s) => [s, names[s]]),
  ]) {
    const b = node("button", label, value === state.filter ? "active" : "");
    b.append(
      node(
        "span",
        value === "all"
          ? sessions.length
          : sessions.filter((s) => s.status === value).length,
        "count",
      ),
    );
    b.onclick = () => {
      state.filter = value;
      state.index = 0;
      renderFleet();
    };
    $("tabs").append(b);
  }
  const query = $("search").value.toLowerCase();
  const visible = sessions.filter(
    (s) =>
      (state.filter === "all" || s.status === state.filter) &&
      `${s.title} ${s.project} ${s.cwd} ${machine(s)?.name || s.machine_id}`
        .toLowerCase()
        .includes(query),
  );
  const groups = new Map();
  for (const s of visible) {
    const key =
      state.group === "status"
        ? s.status
        : state.group === "machine"
          ? machine(s)?.name || s.machine_id
          : s.project;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(s);
  }
  const keys = [...groups.keys()].sort((a, b) =>
    state.group === "status"
      ? priorities.indexOf(a) - priorities.indexOf(b)
      : a.localeCompare(b),
  );
  $("fleet").replaceChildren();
  let index = 0;
  for (const key of keys) {
    $("fleet").append(
      node(
        "h2",
        state.group === "status" ? names[key].toUpperCase() : key.toUpperCase(),
        "group-label",
      ),
    );
    const ul = node("ul");
    for (const s of groups
      .get(key)
      .sort((a, b) => Date.parse(b.updated_at) - Date.parse(a.updated_at))) {
      const li = node("li"),
        b = node(
          "button",
          null,
          "session-row" + (index === state.index ? " selected" : ""),
        );
      b.dataset.session = s.id;
      b.dataset.index = index++;
      const m = node("div", null, "machine");
      m.append(dot(s.status), node("span", machine(s)?.name || s.machine_id));
      const title = node("div");
      title.append(
        node("div", s.title, "row-title"),
        node(
          "div",
          s.project + (s.branch ? " / " + s.branch : ""),
          "row-project",
        ),
      );
      const status = node("div", null, "row-state");
      status.append(
        node(
          "span",
          machine(s)?.status === "OFFLINE"
            ? "Offline"
            : names[s.status] || s.status,
        ),
        node(
          "span",
          s.status === "WORKING"
            ? elapsed(s.turn_started)
            : elapsed(s.updated_at),
        ),
      );
      b.append(m, title, status);
      b.onclick = () => openSession(s.id);
      li.append(b);
      ul.append(li);
    }
    $("fleet").append(ul);
  }
  if (!visible.length)
    $("fleet").append(
      node(
        "p",
        sessions.length
          ? "Nessuna sessione corrisponde ai filtri."
          : "In attesa di un agent. Registra una macchina e avvia codex-relay agent.",
        "empty",
      ),
    );
}
function renderDetail() {
  const s = state.sessions.get(state.selected);
  $("detail-heading").replaceChildren();
  $("detail-meta").replaceChildren();
  if (!s) {
    $("detail-heading").append(node("h1", "Sessione non disponibile"));
    $("composer").hidden = true;
    return;
  }
  const m = machine(s),
    connected = state.online && m?.status === "ONLINE";
  $("detail-heading").append(
    node("div", `${m?.name || s.machine_id} · ${s.project}`, "eyebrow"),
    node("h1", s.title),
  );
  const status = node("div", null, "muted");
  status.append(
    dot(s.status),
    node(
      "span",
      `${names[s.status] || s.status} · ${s.status === "WORKING" ? elapsed(s.turn_started) : elapsed(s.updated_at)}${!connected ? " · macchina offline" : ""}`,
    ),
  );
  $("detail-heading").append(status);
  for (const [key, value] of [
    ["Macchina", m?.name || s.machine_id],
    ["Progetto", s.project],
    ["Branch", s.branch || "—"],
    ["cwd", s.cwd],
    ["Thread", s.thread_id],
    ["Adapter", m?.adapter || "—"],
  ]) {
    $("detail-meta").append(node("dt", key), node("dd", value));
  }
  $("detail-connection").textContent = connected
    ? "Live"
    : "Connessione non disponibile";
  $("readonly").hidden = !s.read_only;
  $("attach").disabled = !connected;
  const working = s.status === "WORKING",
    needs = s.status === "NEEDS_YOU";
  const kind = state.steerMode ? "steer" : messageKind(s),
    cap = s.capabilities || {};
  $("composer").hidden =
    s.read_only || needs || !["READY", "WORKING"].includes(s.status);
  $("advanced").hidden = s.read_only || !(working || needs || state.steerMode);
  $("steer").hidden = !working && !state.steerMode;
  $("steer").disabled =
    !state.steerMode && (!connected || !cap.can_steer || !s.turn_id);
  $("steer").textContent = state.steerMode
    ? "Torna al normale invio"
    : "Steer turno corrente";
  $("interrupt").disabled = !connected || !cap.can_interrupt || !s.turn_id;
  $("message").disabled = !connected;
  $("message").placeholder = state.steerMode
    ? "Correggi il lavoro in corso…"
    : working
      ? "Aggiungi un follow-up…"
      : "Scrivi a Codex…";
  $("send").textContent = state.steerMode
    ? "Invia Steer"
    : working
      ? "Invia follow-up"
      : "Invia";
  $("send").disabled =
    !connected ||
    !canSend(s, kind) ||
    [...state.commands.values()].some(
      (c) =>
        c.session === s.id &&
        ["new_turn", "steer", "follow_up"].includes(c.kind),
    );
  $("composer-hint").textContent = state.steerMode
    ? working
      ? "Steer modifica il lavoro ATTUALMENTE in corso."
      : "Il turno è cambiato. Torna al normale invio per scegliere un nuovo turno."
    : working
      ? "Follow-up: Codex lo eseguirà dopo il lavoro corrente."
      : "Il messaggio avvia un nuovo turno.";
  renderPending(s, connected);
  renderChat();
  $("history-status").textContent = state.loading
    ? "Carico il contesto recente da Codex…"
    : "Ultimi item · nessun transcript nel database Relay";
}
function renderChat() {
  const nearBottom =
    $("chat").scrollHeight - $("chat").scrollTop - $("chat").clientHeight < 80;
  $("chat").replaceChildren();
  const visible = [
    ...state.chat,
    ...outbox.visible(state.selected).map((v) => ({
      id: v.id,
      kind: "userMessage",
      text: v.text,
      timestamp: new Date(v.at).toISOString(),
      outbox: v,
    })),
  ];
  visible.sort(
    (a, b) => Date.parse(a.timestamp || 0) - Date.parse(b.timestamp || 0),
  );
  for (const a of visible) {
    const article = node("article", null, "activity " + a.kind);
    const label =
      {
        agentMessage: "Codex",
        delta: "Codex",
        userMessage: "Me",
        commandExecution: "Comando",
        command_output: "Output",
        diff: "Diff",
        fileChange: "File",
      }[a.kind] || a.kind;
    article.append(node("p", label, "activity-label"), node("pre", a.text));
    if (a.progress) article.append(node("p", a.progress, "activity-label"));
    if (a.result_summary) article.append(node("pre", a.result_summary));
    if (a.outbox) {
      const v = a.outbox;
      const phases = {
        LOCAL: "LOCALE",
        SENDING: "INVIO",
        QUEUED: "IN CODA",
        DISPATCHED: "AVVIATO",
        ACCEPTED: "ACCETTATO",
        STEERING: "STEERING",
        APPLIED: "APPLICATO",
        FAILED: "FALLITO",
      };
      const action =
        v.kind === "follow_up"
          ? "FOLLOW-UP"
          : v.kind === "steer"
            ? "STEER"
            : "NEW TURN";
      article.append(
        node(
          "p",
          action + " · " + (phases[v.phase] || v.phase),
          "activity-label",
        ),
      );
      if (v.phase === "FAILED") {
        article.append(
          node(
            "p",
            v.error || "Invio fallito. Il testo resta disponibile.",
            "muted",
          ),
        );
        const actions = node("div", null, "actions"),
          session = state.sessions.get(v.session);
        const choices =
          v.kind === "steer" && v.errorCode === "TURN_CHANGED"
            ? ["follow_up", "new_turn"]
            : [
                v.kind,
                ...(v.kind === "steer" ? ["follow_up", "new_turn"] : []),
              ];
        for (const kind of choices) {
          if (!session || !canSend(session, kind)) continue;
          const text =
            kind === v.kind
              ? v.errorCode === "UNKNOWN_OUTCOME"
                ? "Reinvia dopo aver verificato"
                : "Riprova"
              : kind === "follow_up"
                ? "Invia come follow-up"
                : "Invia come nuovo turno";
          const button = node("button", text);
          button.type = "button";
          button.disabled =
            !state.online || machine(session)?.status !== "ONLINE";
          button.onclick = () => {
            if (submitMessage(kind, v.text)) outbox.items.delete(v.id);
            renderDetail();
          };
          actions.append(button);
        }
        const discard = node("button", "Scarta");
        discard.type = "button";
        discard.onclick = () => {
          outbox.items.delete(v.id);
          renderDetail();
        };
        actions.append(discard);
        article.append(actions);
      }
    }
    $("chat").append(article);
  }
  if (nearBottom) $("chat").scrollTop = $("chat").scrollHeight;
}
function addActivity(a) {
  if (!a || (!a.text && !a.progress && !a.result_summary)) return;
  outbox.materialize(state.selected, a);
  const existing = state.chat.find((v) => v.id === a.id);
  a = {
    ...a,
    timestamp: existing?.timestamp || a.timestamp || new Date().toISOString(),
    text: (a.text || "").slice(0, 16384),
    progress: a.progress?.slice(0, 1024),
    result_summary: a.result_summary?.slice(0, 4096),
  };
  reconcileActivity(state.chat, a);
  while (
    state.chat.length > 50 ||
    state.chat.reduce((n, a) => n + a.text.length + (a.progress?.length || 0) + (a.result_summary?.length || 0), 0) > 131072
  )
    state.chat.shift();
}
function applyChat(e) {
  if (e.kind === "follow_up_queue") outbox.queue(e.session_id, e.follow_ups);
  if (["turn_started", "message_dispatched"].includes(e.kind) && e.client_id)
    outbox.dispatched(e.session_id, e.client_id);
  if (e.activity) {
    addActivity(e.activity);
    return;
  }
  if (["tool_progress", "terminal_interaction"].includes(e.kind)) {
    const previous = state.chat.find((a) => a.id === e.item_id);
    if (previous && previous.state && previous.state !== "running") return;
    addActivity({ ...previous, id: e.item_id,
      kind: e.kind === "tool_progress" ? "mcpToolCall" : "commandExecution",
      state: "running", text: previous?.text || "", progress: (e.text || "").slice(0, 1024) });
    return;
  }
  if (!["delta", "command_output", "diff"].includes(e.kind)) return;
  const id = e.item_id || e.turn_id + "/" + e.kind;
  const previous = state.chat.find((a) => a.id === id);
  addActivity({
    id,
    kind: e.kind,
    timestamp: e.timestamp,
    text: e.kind === "diff" ? e.text : (previous?.text || "") + (e.text || ""),
  });
}
function renderPending(s, connected) {
  const signature = JSON.stringify([
    s.id,
    connected,
    s.capabilities?.can_answer,
    [...state.requests.values()].filter((r) => r.session_id === s.id),
  ]);
  if (signature === pendingSignature) return;
  pendingSignature = signature;
  $("pending").replaceChildren();
  for (const r of state.requests.values()) {
    if (r.session_id !== s.id) continue;
    const box = node("section", null, "pending-request");
    box.append(
      node(
        "h2",
        {
          command_approval: "Approval comando",
          file_approval: "Approval modifica file",
          permissions_approval: "Permessi per questo turno",
          user_input: "Codex ha bisogno di te",
          mcp_elicitation: "Richiesta MCP",
        }[r.kind] || "Richiesta da risolvere in Codex locale",
      ),
      node(
        "p",
        `${machine(s)?.name || s.machine_id} · ${s.project} · ${r.cwd || s.cwd} · thread ${s.thread_id}`,
        "context",
      ),
      node("p", r.description),
      node("pre", r.operation || "", "operation"),
    );
    let payload = {};
    try {
      payload = JSON.parse(
        typeof r.payload === "string"
          ? r.payload
          : JSON.stringify(r.payload || {}),
      );
    } catch {}
    if (r.kind === "permissions_approval")
      box.append(
        node("pre", JSON.stringify(payload.permissions || {}, null, 2)),
      );
    const form = node("form");
    const fields = new Map();
    for (const q of r.questions || []) {
      const label = node("label", q.question);
      let input;
      if (q.options?.length) {
        input = node("select");
        for (const o of q.options) {
          const option = node(
            "option",
            o.label + (o.description ? " — " + o.description : ""),
          );
          option.value = o.label;
          input.append(option);
        }
        const free = node("option", "Risposta libera…");
        free.value = "__free__";
        input.append(free);
        const extra = node("input");
        extra.hidden = true;
        extra.placeholder = "La tua risposta";
        label.append(input, extra);
        fields.set(q.id, () =>
          input.value === "__free__" ? extra.value : input.value,
        );
        input.onchange = () => (extra.hidden = input.value !== "__free__");
      } else {
        input = node("input");
        input.type = q.secret ? "password" : "text";
        input.required = true;
        input.maxLength = 16384;
        label.append(input);
        fields.set(q.id, () => input.value);
      }
      form.append(label);
    }
    let mcp;
    if (r.kind === "mcp_elicitation") {
      box.append(
        node("pre", JSON.stringify(payload.input_schema || {}, null, 2)),
      );
      mcp = node("textarea");
      mcp.placeholder = "Risposta JSON conforme allo schema MCP";
      form.append(mcp);
    }
    const actions = node("div", null, "actions");
    if (r.can_approve) {
      const approve = node(
        "button",
        r.kind === "user_input"
          ? "Invia risposta"
          : r.kind === "permissions_approval"
            ? "APPROVA PER QUESTO TURNO"
            : "APPROVA UNA VOLTA",
        "approve",
      );
      approve.type = "submit";
      approve.disabled = !connected || !s.capabilities?.can_answer;
      actions.append(approve);
    }
    if (r.kind !== "unsupported") {
      const reject = node("button", "RIFIUTA");
      reject.type = "button";
      reject.disabled = !connected || !s.capabilities?.can_answer;
      reject.onclick = () => respond(r, "reject");
      actions.append(reject);
    }
    form.append(actions);
    form.onsubmit = (e) => {
      e.preventDefault();
      const answers = Object.fromEntries(
        [...fields].map(([id, read]) => [id, [read()]]),
      );
      let content;
      if (mcp) {
        try {
          content = JSON.parse(mcp.value);
        } catch {
          return toast("Inserisci una risposta JSON valida.");
        }
      }
      respond(r, "approve", { answers, content });
    };
    box.append(form);
    $("pending").append(box);
  }
}
function respond(r, decision, extra = {}) {
  if (command("answer", { request_id: r.request_id, decision, ...extra }))
    toast("Risposta inviata. Attendo la conferma da Codex.");
}
function openSession(id, push = true) {
  state.selected = id;
  $("message").value = "";
  pendingSignature = "";
  state.chat = [];
  state.loading = true;
  state.steerMode = false;
  outbox.prune(id);
  if (push) history.pushState({}, "", `/session/${encodeURIComponent(id)}`);
  send({ type: "watch", session_id: id });
  render();
}
function closeSession(push = true) {
  send({ type: "watch", session_id: "" });
  state.selected = "";
  state.chat = [];
  state.steerMode = false;
  outbox.prune();
  if (push) history.pushState({}, "", "/");
  render();
}
function route() {
  const match = location.pathname.match(/^\/session\/([^/]+)$/);
  if (match) {
    try {
      openSession(decodeURIComponent(match[1]), false);
    } catch {
      closeSession(false);
    }
  } else closeSession(false);
}
function connect() {
  clearTimeout(reconnectTimer);
  if (!state.authenticated || document.hidden) return;
  state.socket = new WebSocket(
    `${location.protocol === "https:" ? "wss" : "ws"}://${location.host}/api/ui`,
  );
  const socket = state.socket;
  let firstSnapshot = true;
  socket.onopen = () => {
    state.retry = 0;
    render();
  };
  socket.onmessage = (e) => {
    let m;
    try {
      m = JSON.parse(e.data);
    } catch {
      return;
    }
    if (m.type === "devices_changed" && !$("devices").hidden) refreshDevices();
    if (m.type === "snapshot") {
      state.online = true;
      state.machines = new Map(m.snapshot.machines.map((v) => [v.id, v]));
      state.sessions = new Map(m.snapshot.sessions.map((v) => [v.id, v]));
      state.requests = new Map(
        m.snapshot.requests.map((v) => [v.request_id, v]),
      );
      if (firstSnapshot && state.selected) {
        state.loading = true;
        send({ type: "watch", session_id: state.selected });
      }
      firstSnapshot = false;
    }
    if ((m.type === "event" || m.type === "pending") && m.event) {
      const e = m.event;
      if (e.session) state.sessions.set(e.session.id, e.session);
      if (e.request) state.requests.set(e.request.request_id, e.request);
      if (e.kind === "request_resolved") state.requests.delete(e.request_id);
      if (e.session_id === state.selected) applyChat(e);
    }
    if (m.type === "result") {
      const r = m.result,
        c = state.commands.get(r.id);
      state.commands.delete(r.id);
      outbox.result(r);
      if (!r.ok) toast(r.error || "Il comando non è riuscito.");
      if (r.session_id === state.selected) {
        if (r.follow_ups) outbox.queue(r.session_id, r.follow_ups);
        if (r.history) {
          for (const a of r.history) addActivity(a);
        }
        if (!c || c.kind === "history") state.loading = false;
      }
    }
    scheduleRender();
  };
  socket.onerror = () => socket.close();
  socket.onclose = () => {
    if (socket !== state.socket) return;
    state.online = false;
    outbox.disconnected();
    state.commands.clear();
    render();
    if (state.authenticated && !document.hidden) {
      const delay =
        Math.min(30000, 1000 * 2 ** Math.min(state.retry++, 5)) *
        (0.5 + Math.random() * 0.5);
      reconnectTimer = setTimeout(async () => {
        try {
          await api("/api/bootstrap");
          connect();
        } catch (e) {
          if (e.status === 401) {
            state.authenticated = false;
            render();
          } else {
            connect();
          }
        }
      }, delay);
    }
  };
}
$("login-form").onsubmit = async (e) => {
  e.preventDefault();
  try {
    await api("/api/login", { token: $("login-token").value.trim() });
    $("login-token").value = "";
    await bootstrap();
  } catch (e) {
    $("login-error").textContent = e.message;
  }
};
$("logout").onclick = async () => {
  try {
    await api("/api/logout", {});
  } catch {}
  state.authenticated = false;
  state.chat = [];
  outbox.clear();
  state.commands.clear();
  state.requests.clear();
  state.socket?.close();
  render();
};
$("back").onclick = () => closeSession();
document.querySelector(".brand").onclick = (e) => {
  e.preventDefault();
  closeSession();
};
window.onpopstate = route;
$("settings-toggle").onclick = () =>
  ($("settings").hidden = !$("settings").hidden);
$("search").oninput = () => {
  state.index = 0;
  renderFleet();
};
$("group").onchange = () => {
  state.group = $("group").value;
  state.index = 0;
  renderFleet();
};
$("steer").onclick = () => {
  state.steerMode = !state.steerMode;
  state.steerTurnId = state.steerMode
    ? state.sessions.get(state.selected)?.turn_id || ""
    : "";
  renderDetail();
  $("message").focus();
};
function submitMessage(kind, text) {
  const session = state.sessions.get(state.selected);
  if (!session || !canSend(session, kind) || !text) return false;
  const id = crypto.randomUUID();
  try {
    outbox.add(id, session.id, kind, text);
  } catch (e) {
    toast(e.message);
    return false;
  }
  outbox.sending(id);
  if (
    !command(
      kind,
      {
        text,
        turn_id:
          kind === "steer" && state.steerMode
            ? state.steerTurnId
            : session.turn_id || "",
      },
      id,
    )
  ) {
    outbox.result({
      id,
      ok: false,
      error_code: "MACHINE_OFFLINE",
      error:
        "Connessione Relay non disponibile. Il messaggio non è stato inviato.",
    });
    renderDetail();
    return false;
  }
  state.steerMode = false;
  renderDetail();
  return true;
}
$("composer").onsubmit = (e) => {
  e.preventDefault();
  const session = state.sessions.get(state.selected),
    text = $("message").value.trim();
  if (!session || !text) return;
  if (submitMessage(state.steerMode ? "steer" : messageKind(session), text))
    $("message").value = "";
};
$("message").onkeydown = (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
    $("composer").requestSubmit();
    e.preventDefault();
  }
};
$("interrupt").onclick = () => {
  const s = state.sessions.get(state.selected);
  if (s) command("interrupt", { turn_id: s.turn_id || "" });
};
$("attach").onclick = () => command("attach");
document.addEventListener("keydown", (e) => {
  if (["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement.tagName))
    return;
  if (e.key === "Escape") {
    closeSession();
    return;
  }
  if (state.selected) return;
  const rows = [...document.querySelectorAll(".session-row")];
  if (["j", "ArrowDown", "k", "ArrowUp"].includes(e.key)) {
    e.preventDefault();
    state.index = Math.max(
      0,
      Math.min(
        rows.length - 1,
        state.index + (["j", "ArrowDown"].includes(e.key) ? 1 : -1),
      ),
    );
    renderFleet();
    document
      .querySelector(".session-row.selected")
      ?.scrollIntoView({ block: "nearest" });
  }
  if (e.key === "Enter") rows[state.index]?.click();
  if (e.key === "/") {
    e.preventDefault();
    $("search").focus();
  }
  if (e.key === "g") {
    const groups = ["status", "machine", "project"];
    state.group = groups[(groups.indexOf(state.group) + 1) % 3];
    $("group").value = state.group;
    renderFleet();
  }
});
document.addEventListener("visibilitychange", () => {
  clearTimeout(backgroundTimer);
  if (document.hidden) {
    hiddenAt = Date.now();
    backgroundTimer = setTimeout(() => {
      state.chat = [];
      outbox.clear();
      state.socket?.close();
    }, 300000);
  } else if (state.authenticated) {
    if (hiddenAt && Date.now() - hiddenAt > 300000) {
      state.chat = [];
      outbox.clear();
    }
    if (state.socket?.readyState === WebSocket.OPEN && state.selected) {
      send({ type: "watch", session_id: state.selected });
    } else connect();
  }
});
window.addEventListener("pagehide", () => {
  state.chat = [];
  outbox.clear();
});
function publicKeyBytes(key) {
  return Uint8Array.from(atob(key.replace(/-/g, "+").replace(/_/g, "/")), (c) =>
    c.charCodeAt(0),
  );
}
async function registration() {
  if (!("serviceWorker" in navigator) || !("PushManager" in window))
    throw new Error(
      "Web Push non disponibile. Su iPhone apri la PWA dalla schermata Home.",
    );
  return Promise.race([
    navigator.serviceWorker.ready,
    new Promise((_, reject) =>
      setTimeout(
        () =>
          reject(new Error("Service Worker non disponibile. Ricarica la PWA.")),
        10000,
      ),
    ),
  ]);
}
$("push-enable").onclick = async () => {
  try {
    if (!state.publicKey) throw new Error("VAPID non configurato sul Hub.");
    const permission = await Notification.requestPermission();
    const r = await registration();
    if (permission !== "granted")
      throw new Error("Permesso notifiche non concesso.");
    const subscription =
      (await r.pushManager.getSubscription()) ||
      (await r.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: publicKeyBytes(state.publicKey),
      }));
    await api("/api/push/subscribe", {
      subscription: subscription.toJSON(),
      privacy: $("privacy").checked,
    });
    $("push-status").textContent =
      "Web Push attivo. Funziona anche quando la PWA è chiusa.";
  } catch (e) {
    $("push-status").textContent = e.message;
  }
};
$("push-test").onclick = async () => {
  try {
    await api("/api/push/test", {});
    $("push-status").textContent = "Notifica accodata al servizio push.";
  } catch (e) {
    $("push-status").textContent = e.message;
  }
};
$("push-disable").onclick = async () => {
  try {
    const r = await registration(),
      s = await r.pushManager.getSubscription();
    if (s) {
      await api("/api/push/unsubscribe", { endpoint: s.endpoint });
      await s.unsubscribe();
    }
    $("push-status").textContent =
      "Web Push disabilitato su questo dispositivo.";
  } catch (e) {
    $("push-status").textContent = e.message;
  }
};
$("privacy").onchange = async () => {
  try {
    const r = await registration(),
      s = await r.pushManager.getSubscription();
    if (s)
      await api("/api/push/subscribe", {
        subscription: s.toJSON(),
        privacy: $("privacy").checked,
      });
  } catch (e) {
    toast(e.message);
  }
};
async function bootstrap() {
  try {
    const b = await api("/api/bootstrap");
    state.publicKey = b.push_public_key;
    state.authenticated = true;
    const match = location.pathname.match(/^\/session\/([^/]+)$/);
    state.selected = match ? decodeURIComponent(match[1]) : "";
    connect();
  } catch {
    state.authenticated = false;
  }
  render();
}
if ("serviceWorker" in navigator)
  navigator.serviceWorker.register("/sw.js").catch(() => {});
// This timer updates relative labels only; no network polling.
setInterval(() => {
  outbox.prune(document.hidden ? "" : state.selected);
  if (state.authenticated && !document.hidden) scheduleRender();
}, 60000);
await bootstrap();

$("pair-form").onsubmit = async (event) => {
  event.preventDefault();
  try {
    await api("/api/pairing/exchange", { code: $("pair-code").value, kind: "operator" });
    $("pair-code").value = "";
    await bootstrap();
  } catch (error) { $("login-error").textContent = error.message; }
};
async function refreshDevices() {
  try {
    const registry = await api("/api/devices");
    const list = $("devices-list"); list.replaceChildren();
    for (const {machine, access} of registry.machines) {
      const row = node("section");
      row.append(node("h3", `${machine.name} · ${machine.status}`), node("p", `${access} · Codex ${machine.codex_version || "—"}`));
      if (machine.account) row.append(node("p", `${machine.account.email || machine.account.kind} · ${machine.account.plan || ""}`));
      if (access !== "REVOKED") {
        const toggle = node("button", access === "PAUSED" ? "Ricollega" : "Scollega");
        toggle.onclick = async () => { try { await api(`/api/machines/${encodeURIComponent(machine.id)}/${access === "PAUSED" ? "resume" : "pause"}`, {}); await refreshDevices(); } catch (error) { toast(error.message); } }; row.append(toggle);
      }
      const remove = node("button", "Elimina e revoca");
      remove.onclick = async () => { if (!confirm(`Eliminare ${machine.name} dal Hub? Codex continuerà localmente; per ricollegare la macchina servirà un nuovo codice.`)) return; try { await api(`/api/machines/${encodeURIComponent(machine.id)}/remove`, {}); await refreshDevices(); } catch (error) { toast(error.message); } }; row.append(remove); list.append(row);
    }
    for (const device of registry.operators) {
      const row = node("section"); row.append(node("h3", device.name + (device.id === registry.current_device_id ? " · questo dispositivo" : "")), node("p", device.revoked ? "Revocato" : `Accesso valido fino al ${device.expires_at.slice(0,10)}`));
      for (const action of device.revoked ? ["remove"] : ["revoke", "remove"]) {
        const b = node("button", action === "remove" ? "Elimina" : "Revoca accesso");
        b.onclick = async () => { if (!confirm(`${action === "remove" ? "Eliminare" : "Revocare"} ${device.name}?`)) return; try { await api(`/api/devices/${encodeURIComponent(device.id)}/${action}`, {}); await refreshDevices(); } catch (error) { toast(error.message); } }; row.append(b);
      } list.append(row);
    }
  } catch (error) { toast(error.message); }
}
$("devices-toggle").onclick = () => { $("devices").hidden = !$("devices").hidden; if (!$("devices").hidden) refreshDevices(); };
$("device-code-form").onsubmit = async (event) => {
  event.preventDefault();
  try { const pair = await api("/api/pairing/code", { kind: $("device-kind").value, name: $("device-name").value, machine: $("device-machine").value }); $("device-code").textContent = `${pair.code.slice(0,4)} ${pair.code.slice(4)} · scade ${new Date(pair.expires_at).toLocaleTimeString()}`; setTimeout(() => { $("device-code").textContent = ""; }, 300000); } catch (error) { toast(error.message); }
};
