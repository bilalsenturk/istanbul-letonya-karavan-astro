const CACHE = 'trip-cache-v11';
const ASSETS = [
  '/favicon.ico',
  '/favicon.svg',
];

function strategyForRequest(request) {
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin) return 'browser';

  if (
    url.pathname.startsWith('/api/') ||
    ['/sw.js', '/kuzey-version.json', '/manifest.webmanifest', '/trip-data.json'].includes(url.pathname)
  ) {
    return 'network-only';
  }

  if (url.pathname.startsWith('/_astro/')) return 'cache-first';

  const isNavigation =
    request.mode === 'navigate' ||
    (request.headers.get('accept') || '').includes('text/html');
  return isNavigation ? 'network-first' : 'browser';
}

function canStoreResponse(response) {
  return response.ok && !/(?:^|,)\s*no-store\s*(?:,|$)/i.test(response.headers.get('cache-control') || '');
}

async function cacheResponse(request, response) {
  if (!canStoreResponse(response)) return;
  const cache = await caches.open(CACHE);
  await cache.put(request, response.clone());
}

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(ASSETS)));
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  const strategy = strategyForRequest(request);

  if (strategy === 'browser' || strategy === 'network-only') return;

  if (strategy === 'cache-first') {
    event.respondWith(
      caches.match(request).then((cached) => {
        if (cached) return cached;
        return fetch(request).then(async (response) => {
          await cacheResponse(request, response);
          return response;
        });
      })
    );
    return;
  }

  event.respondWith(
    fetch(request)
      .then(async (response) => {
        await cacheResponse(request, response);
        return response;
      })
      .catch(() => caches.match(request))
  );
});
