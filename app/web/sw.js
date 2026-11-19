// Lightweight offline shell cache (v2, 2026-11-19).
// IMPORTANT: API calls go cross-origin to api.carpsosolutions.store and must
// NEVER be answered with index.html — a failed API fetch must reach the app as
// a real network error, not as fake JSON that silently shows cached data.
const CACHE = 'dropoff-web-v2';
const SHELL = ['./', './index.html', './favicon.png', './manifest.json'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(SHELL).catch(() => {})),
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))),
  );
  self.clients.claim();
});

self.addEventListener('message', (event) => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  // Never touch cross-origin requests (the API). Let the browser handle them.
  if (url.origin !== self.location.origin) return;
  if (SHELL.includes(url.pathname)) {
    event.respondWith(
      caches.match(event.request).then((hit) => hit || fetch(event.request)),
    );
    return;
  }
  // Navigation fallback only — the app shell when offline.
  if (event.request.mode === 'navigate') {
    event.respondWith(fetch(event.request).catch(() => caches.match('./index.html')));
  }
});
