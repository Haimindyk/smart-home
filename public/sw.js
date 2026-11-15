// Hand-written service worker (no Workbox/next-pwa — Next.js 16 builds with
// Turbopack by default, which the webpack-based PWA plugins don't support).
// Scope: cache the app shell so the PWA opens instantly offline. All real
// data (Supabase reads/writes) is handled by the app's own IndexedDB
// snapshot + mutation queue, not by this worker — network requests to
// Supabase are deliberately left untouched (network-only) below.

const CACHE_NAME = "kh-shell-v4";
const NAVIGATE_TIMEOUT_MS = 2500;
const APP_SHELL = ["/", "/manifest.webmanifest", "/icons/icon-192.png", "/icons/icon-512.png"];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const { request } = event;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return; // never intercept Supabase/API calls

  // Personal pages are never written into the shared app-shell cache.
  if (url.pathname.startsWith("/health") || url.pathname.startsWith("/api/")) return;

  if (request.mode === "navigate") {
    // Network-first, but don't let a slow connection hold the launch hostage:
    // after NAVIGATE_TIMEOUT_MS fall back to the cached shell (the network
    // response still refreshes the cache for next time).
    const cacheKey = url.pathname;
    const network = fetch(request).then((response) => {
      if (response.ok) {
        const clone = response.clone();
        event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.put(cacheKey, clone)));
      }
      return response;
    });
    const cachedShell = () =>
      caches.match(cacheKey).then((cached) => cached || caches.match("/"));

    event.respondWith(
      new Promise((resolve) => {
        let settled = false;
        const finish = (response) => {
          if (settled || !response) return false;
          settled = true;
          resolve(response);
          return true;
        };
        const timer = setTimeout(() => {
          cachedShell().then(finish);
        }, NAVIGATE_TIMEOUT_MS);
        network
          .then((response) => {
            clearTimeout(timer);
            finish(response);
          })
          .catch(() => {
            clearTimeout(timer);
            cachedShell().then((cached) => {
              if (!finish(cached)) finish(Response.error());
            });
          });
      })
    );
    return;
  }

  event.respondWith(
    caches.match(request).then(
      (cached) =>
        cached ||
        fetch(request).then((response) => {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(request, clone));
          return response;
        })
    )
  );
});

// Web Push notifications (see supabase/functions/send-push/index.ts, which
// sends `{ title, body, url, tag, icon }` as the push message payload —
// `icon` is the acting member's uploaded photo when they have one, falling
// back to the app icon).
self.addEventListener("push", (event) => {
  if (!event.data) return;

  let payload;
  try {
    payload = event.data.json();
  } catch {
    return;
  }

  const { title, body, url, tag, icon } = payload;
  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      tag,
      icon: icon || "/icons/icon-192.png",
      badge: "/icons/icon-192.png",
      data: { url },
    })
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = event.notification.data?.url || "/";

  event.waitUntil(
    clients.matchAll({ type: "window" }).then((list) => {
      const existing = list.find((client) => client.url.includes(url));
      if (existing) return existing.focus();
      return clients.openWindow(url);
    })
  );
});
