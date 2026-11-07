// Lightweight offline fallback: cache what we can and show a styled splash.
const CACHE = 'dropoff-web-v1';
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

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (SHELL.includes(url.pathname)) {
    event.respondWith(
      caches.match(event.request).then((hit) => hit || fetch(event.request)),
    );
    return;
  }
  event.respondWith(
    fetch(event.request).catch(() => caches.match('./index.html')),
  );
});
