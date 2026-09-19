// Iter App Progressive Offline Service Worker
const CACHE_NAME = 'iter-app-cache-v1';

const STATIC_ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './favicon.ico',
  './favicon-32x32.png',
  './favicon-16x16.png',
  './icons/Icon-192.png',
  './icons/app_icon.png',
];

// Install: Cache initial app shell
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(STATIC_ASSETS).catch((err) => {
        console.warn('[SW] Failed to cache some static assets during install:', err);
      });
    }).then(() => self.skipWaiting())
  );
});

// Activate: Clean old caches and claim clients immediately
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.map((key) => {
          if (key !== CACHE_NAME) {
            return caches.delete(key);
          }
        })
      );
    }).then(() => self.clients.claim())
  );
});

// Fetch: Stale-while-revalidate for assets, Network-first with offline fallback for navigation
self.addEventListener('fetch', (event) => {
  const req = event.request;
  const url = new URL(req.url);

  // Only handle GET requests
  if (req.method !== 'GET') return;

  // Pass through non-http(s) and API mutating requests
  if (!url.protocol.startsWith('http')) return;

  // Handle Navigation requests (e.g. user opens page or reloads)
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req).catch(() => {
        return caches.match('./index.html').then((cached) => {
          return cached || caches.match('/');
        });
      })
    );
    return;
  }

  // Handle API requests: network-first, do not aggressively cache API calls in SW
  if (url.pathname.includes('/api/v1/')) {
    return;
  }

  // Handle Static Assets (wasm, js, css, images, fonts)
  const isStaticAsset =
    url.pathname.endsWith('.js') ||
    url.pathname.endsWith('.mjs') ||
    url.pathname.endsWith('.wasm') ||
    url.pathname.endsWith('.css') ||
    url.pathname.endsWith('.png') ||
    url.pathname.endsWith('.jpg') ||
    url.pathname.endsWith('.jpeg') ||
    url.pathname.endsWith('.webp') ||
    url.pathname.endsWith('.svg') ||
    url.pathname.endsWith('.ico') ||
    url.pathname.endsWith('.json') ||
    url.pathname.endsWith('.woff2') ||
    url.pathname.endsWith('.ttf');

  if (isStaticAsset) {
    event.respondWith(
      caches.match(req).then((cached) => {
        const fetchPromise = fetch(req).then((networkRes) => {
          if (networkRes && networkRes.status === 200) {
            const copy = networkRes.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(req, copy));
          }
          return networkRes;
        }).catch(() => {
          return cached;
        });

        return cached || fetchPromise;
      })
    );
  }
});
