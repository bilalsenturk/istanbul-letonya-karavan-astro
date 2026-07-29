const CACHE = 'trip-cache-v11';
const HASHED_ASTRO_ASSET = /^\/_astro\/.+\.[A-Za-z0-9_-]{6,}\.[A-Za-z0-9]+$/;

function strategyForRequest(request) {
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin) return 'browser';

  if (
    url.pathname.startsWith('/api/') ||
    ['/sw.js', '/kuzey-version.json', '/manifest.webmanifest', '/trip-data.json'].includes(url.pathname)
  ) {
    return 'network-only';
  }

  if (HASHED_ASTRO_ASSET.test(url.pathname)) return 'cache-first';

  const isNavigation =
    request.mode === 'navigate' ||
    (request.headers.get('accept') || '').includes('text/html');
  return isNavigation ? 'network-first' : 'browser';
}

function canStoreResponse(response) {
  return response.ok && !/(?:^|,)\s*no-store\s*(?:,|$)/i.test(response.headers.get('cache-control') || '');
}

function cacheResponse(event, request, response) {
  if (!canStoreResponse(response)) return;
  let cachedResponse;
  try {
    cachedResponse = response.clone();
  } catch {
    return;
  }
  event.waitUntil(
    caches
      .open(CACHE)
      .then((cache) => cache.put(request, cachedResponse))
      .catch(() => undefined)
  );
}

self.addEventListener('install', () => {
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
        return fetch(request).then((response) => {
          cacheResponse(event, request, response);
          return response;
        });
      })
    );
    return;
  }

  event.respondWith(
    fetch(request)
      .then((response) => {
        cacheResponse(event, request, response);
        return response;
      })
      .catch(() => caches.match(request))
  );
});
