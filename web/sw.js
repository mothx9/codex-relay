const CACHE = "relay-shell-v2";
const SHELL = [
  "/",
  "/app.css",
  "/app.js",
  "/control.mjs",
  "/manifest.webmanifest",
  "/icon.svg",
  "/icon-192.png",
  "/icon-512.png",
];
self.addEventListener("install", (e) =>
  e.waitUntil(
    caches
      .open(CACHE)
      .then((c) => c.addAll(SHELL))
      .then(() => self.skipWaiting()),
  ),
);
self.addEventListener("activate", (e) =>
  e.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)),
        ),
      )
      .then(() => self.clients.claim()),
  ),
);
self.addEventListener("fetch", (e) => {
  const u = new URL(e.request.url);
  if (
    u.origin !== self.location.origin ||
    e.request.method !== "GET" ||
    u.pathname.startsWith("/api/") ||
    u.pathname === "/healthz"
  )
    return;
  const isShell = SHELL.includes(u.pathname),
    navigation = e.request.mode === "navigate";
  if (!isShell && !navigation) return;
  e.respondWith(
    fetch(e.request)
      .then((r) => {
        if (isShell && r.ok) {
          const copy = r.clone();
          caches.open(CACHE).then((c) => c.put(e.request, copy));
        }
        return r;
      })
      .catch(() => caches.match(navigation ? "/" : e.request)),
  );
});
self.addEventListener("push", (e) => {
  let p = {};
  try {
    p = e.data?.json() || {};
  } catch {}
  const target =
    typeof p.url === "string" && p.url.startsWith("/session/") ? p.url : "/";
  e.waitUntil(
    self.registration.showNotification(p.title || "Codex Relay", {
      body: [p.subtitle, p.body || "Codex needs attention."].filter(Boolean).join("\n"),
      tag: p.tag || "relay",
      icon: "/icon-192.png",
      badge: "/icon-192.png",
      data: { url: target },
    }),
  );
});
self.addEventListener("notificationclick", (e) => {
  e.notification.close();
  const target = new URL(e.notification.data?.url || "/", self.location.origin);
  if (target.origin !== self.location.origin) return;
  e.waitUntil(
    self.clients
      .matchAll({ type: "window", includeUncontrolled: true })
      .then(async (clients) => {
        for (const c of clients) {
          if (new URL(c.url).origin === self.location.origin) {
            await c.navigate(target.href);
            return c.focus();
          }
        }
        return self.clients.openWindow(target.href);
      }),
  );
});
