import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const liveSync = await import(pathToFileURL(path.join(root, 'src/scripts/liveSync.ts')).href);

const sourceFiles = [
  'src/components/JourneyHero.astro',
  'src/components/RouteMap.astro',
  'src/layouts/MainLayout.astro',
  'src/pages/index.astro',
  'public/sw.js',
];
const [heroSource, routeMapSource, layoutSource, indexSource, workerSource] = await Promise.all(
  sourceFiles.map((sourceFile) => readFile(path.join(root, sourceFile), 'utf8')),
);

const workerHandlers = new Map();
const workerSelf = {
  location: { origin: 'https://kuzey.test' },
  addEventListener(type, handler) {
    workerHandlers.set(type, handler);
  },
};
const workerContext = vm.createContext({
  URL,
  Request,
  Response,
  self: workerSelf,
  caches: {},
  fetch: async () => {
    throw new Error('fetch should not run while evaluating worker policy');
  },
});
new vm.Script(
  `${workerSource}\nglobalThis.__workerPolicy = { strategyForRequest, canStoreResponse };`,
  { filename: 'public/sw.js' },
).runInContext(workerContext);

const { strategyForRequest: strategy, canStoreResponse } = workerContext.__workerPolicy;
const apiRequest = new Request('https://kuzey.test/api/live');
const tripDataRequest = new Request('https://kuzey.test/trip-data.json');
const hashedAstroRequest = new Request('https://kuzey.test/_astro/app.8ce614.js');
const dayNavigation = new Request('https://kuzey.test/day/3', { headers: { accept: 'text/html' } });
const openStreetMapTile = new Request('https://tile.openstreetmap.org/4/8/5.png');
const noStoreResponse = new Response('private', { headers: { 'cache-control': 'private, no-store' } });

assert.equal(strategy(apiRequest), 'network-only', 'API requests must bypass the worker cache');
assert.equal(strategy(tripDataRequest), 'network-only', 'mutable trip data must bypass the worker cache');
assert.equal(strategy(hashedAstroRequest), 'cache-first', 'hashed Astro assets should use the cache');
assert.equal(strategy(dayNavigation), 'network-first', 'HTML navigation should prefer fresh network content');
assert.equal(strategy(openStreetMapTile), 'browser', 'cross-origin map tiles must stay under browser caching');
assert.equal(canStoreResponse(noStoreResponse), false, 'no-store responses must never be written to Cache Storage');

const fetchHandler = workerHandlers.get('fetch');
for (const request of [apiRequest, tripDataRequest, openStreetMapTile]) {
  let responsePromise;
  fetchHandler({
    request,
    respondWith(promise) {
      responsePromise = promise;
    },
  });
  assert.equal(responsePromise, undefined, `${request.url} must not be intercepted`);
}

assert.match(
  layoutSource,
  /navigator\.serviceWorker\.register\('\/sw\.js'\)/,
  'the shared layout must register the service worker for every page that uses it',
);
assert.doesNotMatch(
  indexSource,
  /navigator\.serviceWorker\.register\('\/sw\.js'\)/,
  'the homepage must not own service-worker registration',
);

assert.equal(typeof liveSync.formatFriendlyLocation, 'function', 'live location formatter should be exported');

const locations = [
  liveSync.formatFriendlyLocation(
    {
      lat: 41.0082,
      lng: 28.9784,
      city: null,
      routeStarted: false,
      activeRouteStop: null,
      nextStop: null,
    },
    [],
  ),
  liveSync.formatFriendlyLocation(
    {
      lat: 41.0082,
      lng: 28.9784,
      city: null,
      routeStarted: true,
      activeRouteStop: 'Kırklareli',
      nextStop: null,
    },
    [],
  ),
];

assert.deepEqual(
  locations,
  ['Konum güncelleniyor', 'Kırklareli yönünde'],
  'live location labels should use human-friendly fallback text',
);
for (const location of locations) {
  assert.doesNotMatch(
    location,
    /-?\d{1,2}(?:\.\d+)?\s*[,/]\s*-?\d{1,3}(?:\.\d+)?/,
    'live location labels must not expose latitude/longitude coordinates',
  );
}

assert.ok(
  heroSource.length > 0 && routeMapSource.length > 0 && indexSource.length > 0,
  'web experience sources should remain readable for subsequent contracts',
);

console.log('Web experience checks passed.');
