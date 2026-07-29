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
const weatherModule = await import(pathToFileURL(path.join(root, 'src/scripts/weather.ts')).href).catch(() => null);

assert.ok(pollingModule, 'the homepage polling scheduler should exist');
assert.ok(weatherModule, 'the homepage weather cache should exist');

{
  const fetchedAt = Date.parse('2026-08-03T00:00:00Z');
  const entry = {
    lat: 41,
    lng: 29,
    fetchedAt,
    snapshot: {
      temperatureC: 24,
      weatherCode: 1,
      windKmh: 12,
      precipitationMm: 0,
    },
  };
  const nearby = { lat: 41.04, lng: 29.03 };
  const overTenKm = { lat: 41.1, lng: 29 };

  assert.equal(
    weatherModule.shouldRefreshWeather(entry, nearby, fetchedAt + 899_999),
    false,
    'a nearby snapshot must remain fresh until the 15-minute TTL expires',
  );
  assert.equal(
    weatherModule.shouldRefreshWeather(entry, nearby, fetchedAt + 900_000),
    true,
    'the weather cache must refresh at the 15-minute boundary',
  );
  assert.equal(
    weatherModule.shouldRefreshWeather(entry, overTenKm, fetchedAt + 60_000),
    true,
    'moving more than 10 km must refresh weather before the TTL',
  );

  const failed = await weatherModule.refreshWeatherCache(
    entry,
    nearby,
    async () => {
      throw new Error('offline');
    },
    fetchedAt + 900_000,
  );
  assert.equal(failed.status, 'failed');
  assert.equal(failed.entry, entry, 'a failed refresh must retain the exact original cache entry');
  assert.deepEqual(
    { lat: failed.entry.lat, lng: failed.entry.lng, fetchedAt: failed.entry.fetchedAt },
    { lat: 41, lng: 29, fetchedAt },
    'a failed refresh must not advance cached location or time',
  );

  let freshCacheFetches = 0;
  const retained = await weatherModule.refreshWeatherCache(
    entry,
    nearby,
    async () => {
      freshCacheFetches += 1;
      return { current: { temperature_2m: 99, weather_code: 99 } };
    },
    fetchedAt + 60_000,
  );
  assert.equal(retained.status, 'cached');
  assert.equal(retained.entry, entry);
  assert.equal(freshCacheFetches, 0, 'a fresh nearby cache entry must not call the fetcher');

  const refreshedAt = fetchedAt + 900_000;
  const refreshed = await weatherModule.refreshWeatherCache(
    null,
    overTenKm,
    async () => ({
      current: {
        temperature_2m: '18.6',
        weather_code: '61',
        wind_speed_10m: '14.2',
        precipitation: '0.7',
      },
    }),
    refreshedAt,
  );
  assert.equal(refreshed.status, 'fresh');
  assert.deepEqual(refreshed.entry, {
    lat: 41.1,
    lng: 29,
    fetchedAt: refreshedAt,
    snapshot: {
      temperatureC: 18.6,
      weatherCode: 61,
      windKmh: 14.2,
      precipitationMm: 0.7,
    },
  });

  const malformed = await weatherModule.refreshWeatherCache(
    null,
    nearby,
    async () => ({ current: { temperature_2m: 'warm', weather_code: null } }),
    refreshedAt,
  );
  assert.equal(malformed.status, 'failed');
  assert.equal(malformed.entry, null, 'a response without a normalized measurement must not enter the cache');
}

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
  const loop = pollingModule.createPollingLoop({
    task: async () => {
      throw new Error('offline');
    },
    intervalMs: 20_000,
    maxBackoffMs: 160_000,
    now: clock.now,
    schedule: clock.schedule,
    cancel: clock.cancel,
  });

  loop.start();
  await clock.runNext();
  assert.deepEqual(clock.pendingDelays(), [40_000]);
  await clock.runNext();
  assert.deepEqual(clock.pendingDelays(), [80_000]);
  await clock.runNext();
  assert.deepEqual(clock.pendingDelays(), [160_000]);
  await clock.runNext();
  assert.deepEqual(clock.pendingDelays(), [160_000], 'failure backoff must stay capped');
  loop.stop();
}

{
  const clock = createFakeClock();
  let calls = 0;
  const loop = pollingModule.createPollingLoop({
    task: async () => {
      calls += 1;
    },
    intervalMs: 20_000,
    maxBackoffMs: 160_000,
    now: clock.now,
    schedule: clock.schedule,
    cancel: clock.cancel,
  });

  loop.start();
  await clock.runNext();
  await clock.advance(5_000);
  loop.pause();
  await clock.advance(7_000);
  loop.resume();
  assert.deepEqual(clock.pendingDelays(), [8_000], 'fresh work should retain its remaining delay after resume');
  await clock.advance(7_999);
  assert.equal(calls, 1);
  await clock.advance(1);
  assert.equal(calls, 2);
  loop.stop();
}

{
  const clock = createFakeClock();
  const signals = [];
  let resolveTask;
  const taskResult = new Promise((resolve) => {
    resolveTask = resolve;
  });
  const loop = pollingModule.createPollingLoop({
    task: async (signal) => {
      signals.push(signal);
      await taskResult;
    },
    intervalMs: 20_000,
    maxBackoffMs: 160_000,
    now: clock.now,
    schedule: clock.schedule,
    cancel: clock.cancel,
  });

  loop.start();
  const activeRun = clock.runNext();
  await Promise.resolve();
  loop.stop();
  assert.equal(signals[0].aborted, true, 'stop should abort an active signal');
  resolveTask();
  await activeRun;
  assert.deepEqual(clock.pendingDelays(), [], 'an active task settling after stop must not reschedule');
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
  'src/scripts/routeMap.ts',
  'src/scripts/routeMapLoader.ts',
  'src/scripts/homeDashboard.ts',
  'public/sw.js',
];
const [heroSource, campActionsSource, cameraSectionSource, stepperSource, routeMapSource, layoutSource, indexSource, daySource, routeMapRuntimeSource, loaderSource, homeRuntimeSource, workerSource] = await Promise.all(
  sourceFiles.map((sourceFile) => readFile(path.join(root, sourceFile), 'utf8')),
);
const robotsSource = await readFile(path.join(root, 'public/robots.txt'), 'utf8');
const vercelConfig = JSON.parse(
  await readFile(path.join(root, 'vercel.json'), 'utf8').catch(() => '{}'),
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
      if (selector === '.fallback-map-image') return [];
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

{
  let errorHandler;
  const addedClasses = [];
  const fallbackImage = {
    dataset: {},
    complete: false,
    naturalWidth: 0,
    addEventListener(type, handler, options) {
      assert.equal(type, 'error');
      assert.deepEqual(options, { once: true });
      errorHandler = handler;
    },
    closest(selector) {
      assert.equal(selector, '.fallback-map');
      return { classList: { add: (value) => addedClasses.push(value) } };
    },
  };
  routeMapLoader.registerRouteMapFallbacks({
    querySelectorAll(selector) {
      assert.equal(selector, '.fallback-map-image');
      return [fallbackImage];
    },
  });
  errorHandler();
  assert.deepEqual(addedClasses, ['fallback-map--failed'], 'a failed static map should reveal its text fallback');
}

assert.match(loaderSource, /rootMargin:\s*['"]300px 0px['"]/);
assert.match(loaderSource, /import\(['"]\.\/routeMap['"]\)/);
assert.doesNotMatch(routeMapSource, /import\s*\{\s*initRouteMap/);
assert.doesNotMatch(indexSource, /<script\s+is:inline/);
assert.doesNotMatch(homeRuntimeSource, /setInterval\s*\(/);
assert.match(indexSource, /mode="journey"\s+live=\{true\}/, 'homepage maps should be live journey maps');
assert.match(daySource, /mode="day"\s+live=\{false\}/, 'day maps should be static day maps');
assert.match(
  routeMapRuntimeSource,
  /\.leaflet-control-zoom a,[\s\S]*?width:\s*44px\s*!important;[\s\S]*?height:\s*44px\s*!important;/,
  'Leaflet zoom controls should expose 44px touch targets',
);
assert.match(
  routeMapSource,
  /class="fallback-map-message"/,
  'map fallbacks should explain a failed static image instead of showing a broken image icon',
);
assert.match(
  loaderSource,
  /fallback-map-image[\s\S]*?fallback-map--failed/,
  'the map loader should expose static fallback failures to the component',
);
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

const heroPicture = heroSource.match(/<Picture\b[\s\S]*?\/>/)?.[0] ?? '';
assert.match(
  heroSource,
  /import\s*\{\s*Picture\s*\}\s*from\s*['"]astro:assets['"]/,
  'the hero should use Astro Picture',
);
assert.match(
  heroSource,
  /import\s+heroImage\s+from\s+['"]\.\.\/assets\/journey\/kuzey-road-motion\.webp['"]/,
  'the hero image should live in the Astro asset pipeline',
);
assert.match(heroPicture, /widths=\{\[640,\s*960,\s*1440,\s*1920\]\}/, 'the hero should request its responsive widths');
assert.match(heroPicture, /formats=\{\['avif',\s*'webp'\]\}/, 'the hero should offer AVIF and WebP');
assert.match(heroPicture, /fallbackFormat="jpg"/, 'the hero should use a compact JPEG fallback');
assert.match(heroPicture, /\bpriority\b/, 'the above-the-fold hero should be high priority');
assert.match(heroPicture, /class="journey-hero__image"/, 'the hero should retain its visual class');
assert.match(
  heroPicture,
  /alt="Günün ilk ışıklarında kuzeye ilerleyen otomobil ve Adria karavan"/,
  'the hero should retain its descriptive alt text',
);

const galleryPicture = indexSource.match(/<Picture\b[\s\S]*?loading="lazy"[\s\S]*?\/>/)?.[0] ?? '';
assert.match(
  indexSource,
  /import\s*\{\s*Picture\s*\}\s*from\s*['"]astro:assets['"]/,
  'the gallery should use Astro Picture',
);
assert.match(
  indexSource,
  /from\s+['"]\.\.\/assets\/journey\/follow-(?:highway|budapest|sofia)\.(?:jpg|png)['"]/,
  'gallery photos should live in the Astro asset pipeline',
);
assert.match(galleryPicture, /widths=\{\[420,\s*720,\s*1080\]\}/, 'gallery photos should request their responsive widths');
assert.match(galleryPicture, /formats=\{\['avif',\s*'webp'\]\}/, 'gallery photos should offer AVIF and WebP');
assert.match(galleryPicture, /fallbackFormat="jpg"/, 'gallery photos should use compact JPEG fallbacks');
assert.match(galleryPicture, /loading="lazy"/, 'below-the-fold gallery photos should load lazily');
assert.doesNotMatch(
  `${heroSource}\n${indexSource}`,
  /src=["']\/assets\/(?:hero\/kuzey-road-motion\.webp|follow-(?:highway\.jpg|budapest\.jpg|sofia\.png))["']/,
  'journey images should no longer bypass Astro image optimization',
);

assert.match(layoutSource, /image\?:\s*string/, 'the layout should accept a social image');
assert.match(layoutSource, /type\?:\s*'website'\s*\|\s*'article'/, 'the layout should accept website and article types');
assert.match(
  layoutSource,
  /new URL\(Astro\.url\.pathname,\s*Astro\.site\)/,
  'canonical URLs should be derived from the production site and current pathname',
);
assert.match(layoutSource, /new URL\(image,\s*Astro\.site\)/, 'social images should be absolute');
assert.match(layoutSource, /<link\s+rel="canonical"\s+href=\{canonical\}/, 'the layout should emit a canonical link');
for (const property of ['og:type', 'og:title', 'og:description', 'og:url', 'og:image']) {
  assert.match(layoutSource, new RegExp(`property=["']${property}["']`), `the layout should emit ${property}`);
}
for (const name of ['twitter:card', 'twitter:title', 'twitter:description', 'twitter:image']) {
  assert.match(layoutSource, new RegExp(`name=["']${name}["']`), `the layout should emit ${name}`);
}
assert.doesNotMatch(
  layoutSource,
  /rel="preconnect"[^>]+(?:unpkg\.com|fonts\.googleapis\.com|fonts\.gstatic\.com)/,
  'the layout should not preconnect to unused hosts',
);
assert.match(indexSource, /<MainLayout[\s\S]*description="[^"]+"[\s\S]*image=\{heroSocialImage\.src\}/, 'home should define distinct social metadata');
assert.match(daySource, /<MainLayout[^>]*description=\{dayDescription\}[^>]*image=\{dayImage\}[^>]*type="article"/, 'day pages should define article metadata');

assert.equal(
  robotsSource.trim(),
  'User-agent: *\nAllow: /\n\nSitemap: https://istanbul-letonya-karavan-astro.vercel.app/sitemap-index.xml',
  'robots.txt should advertise the production sitemap',
);
const headerValueFor = (source, key) => vercelConfig.headers
  ?.find((rule) => rule.source === source)
  ?.headers?.find((header) => header.key.toLowerCase() === key.toLowerCase())
  ?.value;
const cacheControlFor = (source) => headerValueFor(source, 'cache-control');
for (const source of ['/_astro/(.*)', '/assets/letonca/ses/(.*)']) {
  assert.equal(cacheControlFor(source), 'public, max-age=31536000, immutable', `${source} should be immutable for one year`);
}
for (const source of ['/api/(.*)', '/sw.js', '/kuzey-version.json', '/manifest.webmanifest', '/trip-data.json']) {
  assert.equal(cacheControlFor(source), 'no-store, max-age=0', `${source} should never be cached`);
}
const securityHeaders = {
  'content-security-policy': "frame-ancestors 'none'",
  'permissions-policy': 'camera=(self), geolocation=(self), microphone=(self), payment=(), usb=()',
  'referrer-policy': 'strict-origin-when-cross-origin',
  'x-content-type-options': 'nosniff',
  'x-frame-options': 'DENY',
};
for (const [key, value] of Object.entries(securityHeaders)) {
  assert.equal(headerValueFor('/(.*)', key), value, `${key} should protect every response`);
}

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
