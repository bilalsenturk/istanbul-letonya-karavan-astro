import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const liveSync = await import(pathToFileURL(path.join(root, 'src/scripts/liveSync.ts')).href);
const routeMapData = await import(pathToFileURL(path.join(root, 'src/scripts/routeMapData.ts')).href);
const routeMapLoader = await import(pathToFileURL(path.join(root, 'src/scripts/routeMapLoader.ts')).href);
const pollingModule = await import(pathToFileURL(path.join(root, 'src/scripts/polling.ts')).href).catch(() => null);

assert.ok(pollingModule, 'the homepage polling scheduler should exist');

function createFakeClock() {
  let currentTime = 0;
  let nextTimerId = 1;
  const timers = new Map();

  const runDueTimers = async () => {
    while (true) {
      const next = [...timers.entries()]
        .filter(([, timer]) => timer.dueAt <= currentTime)
        .sort((left, right) => left[1].dueAt - right[1].dueAt || left[0] - right[0])[0];
      if (!next) return;
      const [id, timer] = next;
      timers.delete(id);
      await timer.callback();
    }
  };

  return {
    now: () => currentTime,
    schedule(callback, delayMs) {
      const id = nextTimerId++;
      timers.set(id, { callback, dueAt: currentTime + delayMs });
      return id;
    },
    cancel(id) {
      timers.delete(id);
    },
    async runNext() {
      const nextDueAt = Math.min(...[...timers.values()].map((timer) => timer.dueAt));
      assert.ok(Number.isFinite(nextDueAt), 'a timer should be scheduled');
      currentTime = Math.max(currentTime, nextDueAt);
      await runDueTimers();
    },
    async advance(delayMs) {
      currentTime += delayMs;
      await runDueTimers();
    },
    pendingDelays() {
      return [...timers.values()]
        .map((timer) => timer.dueAt - currentTime)
        .sort((left, right) => left - right);
    },
  };
}

{
  const clock = createFakeClock();
  let calls = 0;
  let resolveTask;
  const taskResult = new Promise((resolve) => {
    resolveTask = resolve;
  });
  const loop = pollingModule.createPollingLoop({
    task: async () => {
      calls += 1;
      await taskResult;
    },
    intervalMs: 20_000,
    maxBackoffMs: 160_000,
    now: clock.now,
    schedule: clock.schedule,
    cancel: clock.cancel,
  });

  loop.start();
  loop.start();
  assert.deepEqual(clock.pendingDelays(), [0], 'starting repeatedly should schedule only one initial poll');
  const firstRun = clock.runNext();
  await Promise.resolve();
  assert.equal(calls, 1);
  await clock.advance(20_000);
  assert.equal(calls, 1, 'an unresolved poll must not overlap');
  resolveTask();
  await firstRun;
  assert.deepEqual(clock.pendingDelays(), [20_000], 'successful polls should wait one interval after settling');
  loop.stop();
}

{
  const clock = createFakeClock();
  let calls = 0;
  const loop = pollingModule.createPollingLoop({
    task: async () => {
      calls += 1;
      if (calls < 3) throw new Error('offline');
    },
    intervalMs: 20_000,
    maxBackoffMs: 160_000,
    now: clock.now,
    schedule: clock.schedule,
    cancel: clock.cancel,
  });

  loop.start();
  await clock.runNext();
  assert.deepEqual(clock.pendingDelays(), [40_000], 'the first failure should double the polling interval');
  await clock.runNext();
  assert.deepEqual(clock.pendingDelays(), [80_000], 'consecutive failures should increase the backoff');
  await clock.runNext();
  assert.deepEqual(clock.pendingDelays(), [20_000], 'a successful retry should reset the polling interval');
  loop.stop();
}

{
  const clock = createFakeClock();
  const signals = [];
  let calls = 0;
  let resolveFirst;
  const firstResult = new Promise((resolve) => {
    resolveFirst = resolve;
  });
  const loop = pollingModule.createPollingLoop({
    task: async (signal) => {
      calls += 1;
      signals.push(signal);
      if (calls === 1) await firstResult;
    },
    intervalMs: 20_000,
    maxBackoffMs: 160_000,
    now: clock.now,
    schedule: clock.schedule,
    cancel: clock.cancel,
  });

  loop.start();
  const firstRun = clock.runNext();
  await Promise.resolve();
  loop.pause();
  assert.equal(signals[0].aborted, true, 'pausing should abort an active request');
  await clock.advance(20_000);
  loop.resume();
  resolveFirst();
  await firstRun;
  assert.equal(calls, 2, 'resuming stale work should schedule exactly one immediate run');
  assert.deepEqual(clock.pendingDelays(), [20_000], 'an aborted run should not increase the failure backoff');
  loop.stop();
  loop.stop();
  await clock.advance(160_000);
  assert.equal(calls, 2, 'stopping repeatedly should leave no scheduled work');
}

const sourceFiles = [
  'src/components/JourneyHero.astro',
  'src/components/CampActions.astro',
  'src/components/DayCameraSection.astro',
  'src/components/RouteStepper.astro',
  'src/components/RouteMap.astro',
  'src/layouts/MainLayout.astro',
  'src/pages/index.astro',
  'src/pages/day/[slug].astro',
  'src/scripts/routeMapLoader.ts',
  'src/scripts/homeDashboard.ts',
  'public/sw.js',
];
const [heroSource, campActionsSource, cameraSectionSource, stepperSource, routeMapSource, layoutSource, indexSource, daySource, loaderSource, homeRuntimeSource, workerSource] = await Promise.all(
  sourceFiles.map((sourceFile) => readFile(path.join(root, sourceFile), 'utf8')),
);

const stops = [
  { name: 'İstanbul', lat: 41, lng: 29 },
  { name: 'Sofya', lat: 42, lng: 23 },
  { name: 'Novi Sad', lat: 45, lng: 20 },
  { name: 'Riga', lat: 57, lng: 24 },
];
const geometry = {
  legs: [
    { from: 'İstanbul', to: 'Sofya', distance: 1, duration: 1, coords: [[41, 29], [42, 23]] },
    { from: 'Sofya', to: 'Novi Sad', distance: 1, duration: 1, coords: [[42, 23], [45, 20]] },
    { from: 'Novi Sad', to: 'Riga', distance: 1, duration: 1, coords: [[45, 20], [57, 24]] },
  ],
};

assert.deepEqual(
  routeMapData.selectRouteStops(stops, 'Sofya', 'Novi Sad', 'day').map((stop) => stop.name),
  ['Sofya', 'Novi Sad'],
  'day maps should show their exact origin and destination only',
);
assert.deepEqual(
  routeMapData.selectRouteStops(
    [
      { name: 'İSTANBUL', lat: 41, lng: 29 },
      { name: 'Sofya', lat: 42, lng: 23 },
    ],
    'istanbul',
    'SOFYA',
    'day',
  ).map((stop) => stop.name),
  ['İSTANBUL', 'Sofya'],
  'Turkish dotted-I and base/case variants should select the same route stops',
);
assert.deepEqual(
  routeMapData.selectRouteStops(
    [
      { name: 'IĞDIR', lat: 39, lng: 44 },
      { name: 'Çeşme', lat: 38, lng: 27 },
    ],
    'ığdır',
    'ÇEŞME',
    'day',
  ).map((stop) => stop.name),
  ['IĞDIR', 'Çeşme'],
  'Turkish dotless-I and diacritic case variants should match',
);
assert.equal(
  routeMapData.selectGeometryLegs(geometry, 'Sofya', 'Novi Sad', 'day').length,
  1,
  'day maps should draw one matching geometry leg',
);
assert.equal(
  routeMapData.selectGeometryLegs(geometry, 'sofya', 'NOVİ SAD', 'day').length,
  1,
  'geometry leg matching should honor Turkish base/case variants',
);
assert.equal(
  routeMapData.selectGeometryLegs(geometry, 'İstanbul', 'Riga', 'journey').length,
  geometry.legs.length,
  'journey maps should retain every geometry leg',
);

const readinessTransitions = [];
const tileReadiness = routeMapData.createTileReadinessController((ready) => {
  readinessTransitions.push(ready);
});
tileReadiness.loading();
tileReadiness.tileError();
tileReadiness.load();
assert.deepEqual(
  readinessTransitions,
  [false],
  'an aggregate load must not hide the fallback after a tile failed in the same batch',
);
tileReadiness.loading();
tileReadiness.load();
assert.deepEqual(
  readinessTransitions,
  [false, true],
  'a later error-free tile batch should recover the interactive map',
);

const priorWindow = globalThis.window;
const priorIntersectionObserver = globalThis.IntersectionObserver;
let observerOptions;
let disconnected = false;
let observerCallback;
const observed = [];
const initializedContainers = [];
let importCount = 0;
class LoaderIntersectionObserver {
  constructor(callback, options) {
    observerCallback = callback;
    observerOptions = options;
  }

  observe(target) {
    observed.push(target);
  }

  unobserve() {}

  disconnect() {
    disconnected = true;
  }
}
const initializedMap = { dataset: { mapInitialized: 'true' } };
const pendingMap = { dataset: {} };
try {
  globalThis.window = { IntersectionObserver: LoaderIntersectionObserver };
  globalThis.IntersectionObserver = LoaderIntersectionObserver;
  const unregister = routeMapLoader.registerRouteMaps({
    querySelectorAll(selector) {
      assert.equal(selector, '.route-map');
      return [initializedMap, pendingMap];
    },
  }, async () => {
    importCount += 1;
    return {
      initRouteMap(container) {
        initializedContainers.push(container);
      },
    };
  });
  assert.deepEqual(observerOptions, { rootMargin: '300px 0px', threshold: 0.01 });
  assert.deepEqual(observed, [pendingMap], 'already initialized maps must not be observed again');
  assert.equal(importCount, 0, 'the map runtime must stay unloaded outside the near viewport');

  observerCallback([{ target: pendingMap, isIntersecting: false }]);
  assert.equal(importCount, 0, 'a non-intersecting entry must not load the map runtime');

  observerCallback([{ target: pendingMap, isIntersecting: true }]);
  observerCallback([{ target: pendingMap, isIntersecting: true }]);
  await Promise.resolve();
  assert.equal(importCount, 1, 'repeated intersecting entries must import the map runtime once');
  assert.deepEqual(initializedContainers, [pendingMap], 'the visible map must initialize once');

  unregister();
  assert.equal(disconnected, true, 'unregister should release the observer');
} finally {
  globalThis.window = priorWindow;
  globalThis.IntersectionObserver = priorIntersectionObserver;
}

assert.match(loaderSource, /rootMargin:\s*['"]300px 0px['"]/);
assert.match(loaderSource, /import\(['"]\.\/routeMap['"]\)/);
assert.doesNotMatch(routeMapSource, /import\s*\{\s*initRouteMap/);
assert.doesNotMatch(indexSource, /<script\s+is:inline/);
assert.doesNotMatch(homeRuntimeSource, /setInterval\s*\(/);
assert.match(indexSource, /mode="journey"\s+live=\{true\}/, 'homepage maps should be live journey maps');
assert.match(daySource, /mode="day"\s+live=\{false\}/, 'day maps should be static day maps');
assert.match(indexSource, /slug:\s*day\.slug/, 'each route timeline leg should link to its day plan');
assert.match(indexSource, /Gün planını aç/, 'each route timeline leg should expose a day-plan action');
assert.match(campActionsSource, /Kesin kamp rotasını aç/, 'day plans should offer exact camp directions');
assert.match(cameraSectionSource, /cameras\.length\s*>\s*0/, 'empty camera sections should not render');
assert.match(cameraSectionSource, /<CameraPlayer\s+camera=\{camera\}\s+headingLevel=\{3\}/, 'day cameras should render h3 child headings');
assert.match(daySource, /<DayCameraSection\s+cameras=\{day\.cityCameras\}/, 'day pages should use the tested camera-section boundary');
assert.match(heroSource, /role="timer"[\s\S]*aria-live="off"/, 'countdowns should not announce every second');
assert.match(heroSource, /role="progressbar"[\s\S]*aria-valuenow="0"/, 'route progress should expose an initial value');
assert.match(stepperSource, /aria-current=\{state === 'active' \? 'step' : undefined\}/, 'the current route stop should be announced');
assert.match(indexSource, /Sırbistan:\s*'RS'/, 'Serbia should be included in the route country codes');

function createWorkerHarness({ fetchImpl, matchImpl, openImpl, putImpl } = {}) {
  const handlers = new Map();
  const calls = {
    fetchUrls: [],
    matchUrls: [],
    openNames: [],
    putUrls: [],
    skipWaitingCount: 0,
  };
  const cache = {
    async put(request, response) {
      calls.putUrls.push(request.url);
      return putImpl?.(request, response);
    },
  };
  const workerCaches = {
    async match(request) {
      calls.matchUrls.push(request.url);
      return matchImpl?.(request);
    },
    async open(name) {
      calls.openNames.push(name);
      if (openImpl) return openImpl(name, cache);
      return cache;
    },
    async keys() {
      return [];
    },
    async delete() {
      return true;
    },
  };
  const workerSelf = {
    location: { origin: 'https://kuzey.test' },
    clients: { async claim() {} },
    skipWaiting() {
      calls.skipWaitingCount += 1;
    },
    addEventListener(type, handler) {
      handlers.set(type, handler);
    },
  };
  const workerContext = vm.createContext({
    URL,
    Request,
    Response,
    self: workerSelf,
    caches: workerCaches,
    async fetch(request) {
      calls.fetchUrls.push(request.url);
      if (!fetchImpl) throw new Error(`unexpected network request: ${request.url}`);
      return fetchImpl(request);
    },
  });
  new vm.Script(
    `${workerSource}\nglobalThis.__workerPolicy = { strategyForRequest, canStoreResponse };`,
    { filename: 'public/sw.js' },
  ).runInContext(workerContext);

  return {
    calls,
    handlers,
    policy: workerContext.__workerPolicy,
    dispatchFetch(request) {
      /** @type {Promise<Response> | undefined} */
      let responsePromise;
      const lifetimePromises = [];
      handlers.get('fetch')({
        request,
        respondWith(promise) {
          responsePromise = Promise.resolve(promise);
        },
        waitUntil(promise) {
          lifetimePromises.push(Promise.resolve(promise));
        },
      });
      return { responsePromise, lifetimePromises };
    },
  };
}

const workerFailures = [];
async function checkWorkerBehavior(name, check) {
  try {
    await check();
  } catch (error) {
    workerFailures.push(error);
    console.error(`FAIL: ${name}`);
    console.error(error instanceof Error ? error.message : error);
  }
}

await checkWorkerBehavior('only content-hashed Astro assets are cache-first', () => {
  const { policy } = createWorkerHarness();
  assert.equal(
    policy.strategyForRequest(new Request('https://kuzey.test/_astro/app.8ce614.js')),
    'cache-first',
  );
  assert.equal(
    policy.strategyForRequest(new Request('https://kuzey.test/_astro/runtime.js')),
    'browser',
  );
});

await checkWorkerBehavior('every mutable or non-allowlisted request bypasses the fetch handler', () => {
  const harness = createWorkerHarness();
  const bypassUrls = [
    'https://kuzey.test/api/live',
    'https://kuzey.test/trip-data.json',
    'https://kuzey.test/sw.js',
    'https://kuzey.test/kuzey-version.json',
    'https://kuzey.test/manifest.webmanifest',
    'https://kuzey.test/assets/photo.jpg',
    'https://kuzey.test/_astro/runtime.js',
    'https://tile.openstreetmap.org/4/8/5.png',
  ];

  for (const url of bypassUrls) {
    const { responsePromise } = harness.dispatchFetch(new Request(url));
    responsePromise?.catch(() => undefined);
    assert.equal(responsePromise, undefined, `${url} must not be intercepted`);
  }
  assert.deepEqual(harness.calls.matchUrls, []);
  assert.deepEqual(harness.calls.fetchUrls, []);
  assert.deepEqual(harness.calls.putUrls, []);
});

await checkWorkerBehavior('install activation does not depend on an unreachable precache', async () => {
  const harness = createWorkerHarness();
  const lifetimePromises = [];
  const installHandler = harness.handlers.get('install');
  assert.equal(typeof installHandler, 'function', 'the worker should still activate updates immediately');
  installHandler({
    waitUntil(promise) {
      lifetimePromises.push(Promise.resolve(promise));
    },
  });

  await Promise.all(lifetimePromises);
  assert.equal(harness.calls.skipWaitingCount, 1);
  assert.deepEqual(harness.calls.openNames, []);
});

await checkWorkerBehavior('cache-first returns a cached hashed asset without using the network', async () => {
  const harness = createWorkerHarness({
    matchImpl: async () => new Response('cached asset'),
  });
  const request = new Request('https://kuzey.test/_astro/app.8ce614.js');
  const { responsePromise } = harness.dispatchFetch(request);

  assert.equal(await (await responsePromise).text(), 'cached asset');
  assert.deepEqual(harness.calls.fetchUrls, []);
  assert.deepEqual(harness.calls.putUrls, []);
});

await checkWorkerBehavior('cache-first returns a network miss before persistence completes', async () => {
  let finishPut;
  const pendingPut = new Promise((resolve) => {
    finishPut = resolve;
  });
  const harness = createWorkerHarness({
    matchImpl: async () => undefined,
    fetchImpl: async () => new Response('fresh asset'),
    putImpl: async () => pendingPut,
  });
  const request = new Request('https://kuzey.test/_astro/app.8ce614.js');
  const { responsePromise, lifetimePromises } = harness.dispatchFetch(request);

  try {
    const outcome = await Promise.race([
      responsePromise.then((response) => ({ type: 'response', response })),
      new Promise((resolve) => setTimeout(() => resolve({ type: 'blocked' }), 0)),
    ]);
    assert.equal(outcome.type, 'response', 'cache persistence must not block the network response');
    assert.equal(await outcome.response.text(), 'fresh asset');
  } finally {
    finishPut();
  }
  await Promise.all(lifetimePromises);
  assert.deepEqual(harness.calls.putUrls, [request.url]);
});

await checkWorkerBehavior('cache failure cannot replace a successful cache-first network response', async () => {
  const harness = createWorkerHarness({
    matchImpl: async () => undefined,
    fetchImpl: async () => new Response('fresh asset'),
    openImpl: async () => {
      throw new Error('cache unavailable');
    },
  });
  const { responsePromise, lifetimePromises } = harness.dispatchFetch(
    new Request('https://kuzey.test/_astro/app.8ce614.js'),
  );

  assert.equal(await (await responsePromise).text(), 'fresh asset');
  await Promise.all(lifetimePromises);
});

await checkWorkerBehavior('network-first returns fresh navigation when cache persistence fails', async () => {
  const harness = createWorkerHarness({
    fetchImpl: async () => new Response('fresh page'),
    matchImpl: async () => new Response('stale page'),
    openImpl: async () => {
      throw new Error('cache unavailable');
    },
  });
  const request = new Request('https://kuzey.test/day/3?lang=tr', {
    headers: { accept: 'text/html' },
  });
  const { responsePromise, lifetimePromises } = harness.dispatchFetch(request);

  assert.equal(await (await responsePromise).text(), 'fresh page');
  await Promise.all(lifetimePromises);
  assert.deepEqual(harness.calls.matchUrls, []);
});

await checkWorkerBehavior('network-first failure falls back with the exact navigation URL', async () => {
  const harness = createWorkerHarness({
    fetchImpl: async () => {
      throw new Error('offline');
    },
    matchImpl: async () => new Response('exact offline page'),
  });
  const request = new Request('https://kuzey.test/day/3?lang=tr', {
    headers: { accept: 'text/html' },
  });
  const { responsePromise } = harness.dispatchFetch(request);

  assert.equal(await (await responsePromise).text(), 'exact offline page');
  assert.deepEqual(harness.calls.matchUrls, [request.url]);
});

await checkWorkerBehavior('no-store and unsuccessful responses never reach cache.put', async () => {
  for (const response of [
    new Response('private', { headers: { 'cache-control': 'private, no-store' } }),
    new Response('unavailable', { status: 503 }),
  ]) {
    const harness = createWorkerHarness({
      matchImpl: async () => undefined,
      fetchImpl: async () => response,
    });
    const { responsePromise, lifetimePromises } = harness.dispatchFetch(
      new Request('https://kuzey.test/_astro/app.8ce614.js'),
    );

    await responsePromise;
    await Promise.all(lifetimePromises);
    assert.deepEqual(harness.calls.putUrls, []);
  }
});

if (workerFailures.length > 0) {
  throw new AggregateError(workerFailures, `${workerFailures.length} service-worker checks failed`);
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
