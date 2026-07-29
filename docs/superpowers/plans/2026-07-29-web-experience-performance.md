# Web Experience and Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver Package 2: correct journey/day behavior, fresh live data, lazy maps, responsive images, accessible route state, complete metadata, and explicit cache policy while preserving the approved cinematic design.

**Architecture:** Merge `codex/mobile-live-map-hero` first and treat its `JourneyHero` as the visual baseline. Keep pure policy in testable TypeScript modules; keep DOM coordination in one bundled `homeDashboard.ts`; load Leaflet as a dynamic chunk. The service worker handles only allowlisted same-origin requests, Astro produces images/metadata, and Vercel headers control browser caching.

**Tech Stack:** Astro 7, TypeScript, Leaflet 1.9, Astro `Picture`, Node 22 contract checks, service workers, Vercel.

## Global Constraints

- Preserve the current visual language, committed Kuzey icons, and cinematic hero artifacts.
- Backward compatibility and production-data migration are unnecessary.
- Do not deploy from a dirty or partially verified tree.
- Public tracking remains limited to Kuzey; never show raw coordinates as location copy.
- Public reads use `/api/v2/public/trips/kuzey-2026/{live-location,expense-summary,published-plan,shared-journal}`; change URLs only, not response parsers.
- Do not take unrelated major dependency upgrades.
- Prefer executable policy/module tests and built-output assertions. Exact source-string checks in task examples are only hints for locating contracts; they must not replace observable behavior tests.

## File Map

- `src/scripts/homeDashboard.ts`: bundled homepage DOM orchestration and cleanup.
- `src/scripts/polling.ts`: non-overlapping, abortable scheduler.
- `src/scripts/weather.ts`: 15-minute/10-km weather policy.
- `src/scripts/routeMapData.ts`: pure journey/day selection.
- `src/scripts/routeMapLoader.ts`: near-viewport Leaflet import.
- `tools/check-web-experience.mjs`: Package 2 behavioral contracts.
- `src/assets/journey/*`: Astro-managed presentation images.
- `vercel.json`: immutable and no-store header rules.

---

### Task 1: Merge the approved hero and establish the Package 2 check

**Files:**
- Merge: `codex/mobile-live-map-hero`
- Create: `tools/check-web-experience.mjs`
- Modify: `package.json`

**Interfaces:**
- Consumes: hero commit `6bda313`.
- Produces: `JourneyHero`, compact `RouteMap`, `formatFriendlyLocation`, and `npm run check:web-experience`.

- [ ] **Step 1: Verify histories and tracked cleanliness**

```bash
git merge-base --is-ancestor 13d0ecb codex/system-hardening-experience
git merge-base --is-ancestor ad6269a codex/mobile-live-map-hero
git diff --exit-code
```

Expected: exit 0. Preserve untracked `.tmp-existing-hero-*.png`.

- [ ] **Step 2: Merge without flattening the visual history**

```bash
git merge --no-ff codex/mobile-live-map-hero -m "merge: preserve cinematic live map hero"
```

On conflict, keep the hero versions of `JourneyHero.astro`, concept PNGs, `index.astro`, `liveSync.ts`, and compact-map changes; keep current build 17, icons, service worker, and hardening spec.

- [ ] **Step 3: Create the focused check**

Create `tools/check-web-experience.mjs` with `node:assert/strict`, `node:fs`, `node:path`, and `pathToFileURL`. Add:

```json
"check:web-experience": "node --experimental-strip-types tools/check-web-experience.mjs"
```

The initial check imports `liveSync.ts`, asserts `formatFriendlyLocation` never returns coordinate-shaped text, and reads the hero/index/map sources for later contracts.

- [ ] **Step 4: Verify and commit the harness**

```bash
npm run check:web-sync
npm run check:web-experience
npm run build
git add package.json tools/check-web-experience.mjs
git commit -m "test: establish web experience contracts"
```

### Task 2: Enforce the service-worker allowlist on every page

**Files:**
- Modify: `public/sw.js`
- Modify: `src/layouts/MainLayout.astro`
- Modify: `src/pages/index.astro`
- Test: `tools/check-web-experience.mjs`

**Interfaces:**
- Produces in `sw.js`: `strategyForRequest(request): 'network-only' | 'network-first' | 'cache-first' | 'browser'` and `canStoreResponse(response): boolean`.

- [ ] **Step 1: Add failing VM-based policy tests**

Evaluate `sw.js` with `node:vm` and mocked `self.addEventListener`. Assert:

```js
assert.equal(strategy(apiRequest), "network-only");
assert.equal(strategy(tripDataRequest), "network-only");
assert.equal(strategy(hashedAstroRequest), "cache-first");
assert.equal(strategy(dayNavigation), "network-first");
assert.equal(strategy(openStreetMapTile), "browser");
assert.equal(context.canStoreResponse(noStoreResponse), false);
```

- [ ] **Step 2: Prove red**

```bash
npm run check:web-experience
```

Expected: FAIL because both policy functions are absent.

- [ ] **Step 3: Implement the allowlist**

Use cache `trip-cache-v11`. Make `/api/*`, `/sw.js`, `/kuzey-version.json`, `/manifest.webmanifest`, and `/trip-data.json` network-only; same-origin `/_astro/*` cache-first; HTML navigation network-first with a per-URL offline fallback. Do not call `respondWith` for cross-origin or other assets. Permit `cache.put` only when `response.ok` and Cache-Control lacks `no-store`.

- [ ] **Step 4: Register from the shared layout**

```astro
<script>
  if ('serviceWorker' in navigator && location.protocol === 'https:') {
    navigator.serviceWorker.register('/sw.js').catch(() => undefined);
  }
</script>
```

Remove homepage-only registration.

- [ ] **Step 5: Verify and commit**

```bash
npm run check:web-experience
npm run check:web-sync
git add public/sw.js src/layouts/MainLayout.astro src/pages/index.astro tools/check-web-experience.mjs
git commit -m "fix: keep mutable web data out of caches"
```

### Task 3: Add explicit map modes and lazy Leaflet

**Files:**
- Create: `src/scripts/routeMapData.ts`
- Create: `src/scripts/routeMapLoader.ts`
- Modify: `src/components/RouteMap.astro`, `src/components/JourneyHero.astro`
- Modify: `src/scripts/routeMap.ts`
- Modify: `src/pages/index.astro`, `src/pages/day/[slug].astro`
- Test: `tools/check-web-experience.mjs`

**Interfaces:**
- Produces: `type RouteMapMode = 'journey' | 'day'`; `selectRouteStops(stops, from, to, mode): Stop[]`; `selectGeometryLegs(geometry, from, to, mode): Leg[]`; `registerRouteMaps(root?: ParentNode): () => void`; `initRouteMap(container: HTMLElement): void`.

- [ ] **Step 1: Add failing selector/loader tests**

```js
assert.deepEqual(selectRouteStops(stops, "Sofya", "Novi Sad", "day").map(s => s.name), ["Sofya", "Novi Sad"]);
assert.equal(selectGeometryLegs(geometry, "Sofya", "Novi Sad", "day").length, 1);
assert.equal(selectGeometryLegs(geometry, "İstanbul", "Riga", "journey").length, geometry.legs.length);
assert.match(loaderSource, /rootMargin:\\s*['"]300px 0px['"]/);
assert.match(loaderSource, /import\\(['"]\\.\\/routeMap['"]\\)/);
assert.doesNotMatch(routeMapComponent, /import\\s*\\{\\s*initRouteMap/);
```

- [ ] **Step 2: Prove red**

```bash
npm run check:web-experience
```

- [ ] **Step 3: Implement mode selection and props**

Normalize names with Turkish base sensitivity. Day mode returns the exact origin/destination and matching geometry leg; journey mode returns all. Require `mode: RouteMapMode` and `live: boolean` in `RouteMap`; emit `data-mode`/`data-live`; render live status only when `live`.

- [ ] **Step 4: Implement lazy loading and fallback recovery**

Observe `.route-map` with `{ rootMargin: '300px 0px', threshold: 0.01 }`, guard with `data-map-initialized`, then dynamically import `./routeMap`. Add `.ready` only on tile-layer `load`; remove it on `tileerror`. Subscribe to live events only when enabled.

- [ ] **Step 5: Wire call sites, verify, commit**

Use `mode="journey" live={true}` on homepage/hero maps and `mode="day" live={false}` on day pages. Day pages pass `selectRouteStops(tripData.stops, day.origin, day.destination, 'day')`.

```bash
npm run check:web-experience
npm run check:web-sync
npm run check
git add src/scripts/routeMapData.ts src/scripts/routeMapLoader.ts src/scripts/routeMap.ts src/components/RouteMap.astro src/components/JourneyHero.astro src/pages/index.astro src/pages/day/'[slug].astro' tools/check-web-experience.mjs
git commit -m "perf: lazy load exact route maps"
```

### Task 4: Repair journey/day UX and route accessibility

**Files:**
- Modify: `src/pages/index.astro`, `src/pages/day/[slug].astro`
- Modify: `src/components/JourneyHero.astro`, `src/components/RouteStepper.astro`
- Modify: `src/layouts/MainLayout.astro`
- Test: `tools/check-web-experience.mjs`

**Interfaces:**
- Produces: timeline `slug`; exact camp directions; semantic timer/progress/current step; Serbia `RS`/`🇷🇸`; stop-count CSS variable.

- [ ] **Step 1: Add failing source contracts**

```js
assert.match(homeSource, /slug:\\s*day\\.slug/);
assert.match(homeSource, /Gün planını aç/);
assert.match(daySource, /Kesin kamp rotasını aç/);
assert.match(daySource, /day\\.cityCameras\\.length\\s*>\\s*0/);
assert.match(heroSource, /role="timer"[\\s\\S]*aria-live="off"/);
assert.match(heroSource, /role="progressbar"[\\s\\S]*aria-valuenow="0"/);
assert.match(stepperSource, /aria-current=\\{state === 'active' \\? 'step' : undefined\\}/);
assert.match(homeSource, /Sırbistan:\\s*'RS'/);
```

- [ ] **Step 2: Prove red**

```bash
npm run check:web-experience
```

- [ ] **Step 3: Implement journey and camp actions**

Add `slug: day.slug` and a 44px `/day/${leg.slug}` “Gün planını aç” action. Build primary camp directions from `arrivalTarget.latitude/longitude`, falling back to `camp.place`. Show “Kamp web sitesi” only for `arrivalTarget.websiteURL` or a non-Google `camp.link`. Hide the entire camera section when empty.

- [ ] **Step 4: Implement semantic route state**

Use `role="timer" aria-live="off"`; add one hidden `role="status" aria-live="polite"` updated only when route-start/target changes. Add progressbar bounds/value, `aria-current="step"`, and `--route-stop-count: ${stops.length}`. Add Serbia data. Restore day heading order (`h1` then section `h2`, child `h3`), underline inline content links, retain a 3px focus outline, and enforce 44px interactive targets.

- [ ] **Step 5: Verify and commit**

```bash
npm run check:web-experience
npm run check:travel-content
npm run check
npm run lint
git add src/pages/index.astro src/pages/day/'[slug].astro' src/components/JourneyHero.astro src/components/RouteStepper.astro src/layouts/MainLayout.astro tools/check-web-experience.mjs
git commit -m "fix: connect and clarify the journey experience"
```

### Task 5: Bundle the runtime and replace overlapping polls

**Files:**
- Create: `src/scripts/polling.ts`, `src/scripts/homeDashboard.ts`
- Modify: `src/pages/index.astro`
- Test: `tools/check-web-experience.mjs`

**Interfaces:**
- Produces: `createPollingLoop(options): { start(): void; pause(): void; resume(): void; stop(): void }`; `initHomeDashboard(root?: HTMLElement): () => void`.

- [ ] **Step 1: Add fake-clock and source tests**

```js
const loop = createPollingLoop({ task, intervalMs: 20_000, maxBackoffMs: 160_000, now, schedule, cancel });
loop.start(); await clock.runNext();
assert.equal(calls, 1);
await clock.advance(20_000);
assert.equal(calls, 1, "an unresolved poll must not overlap");
assert.doesNotMatch(homeSource, /<script\\s+is:inline/);
assert.doesNotMatch(homeRuntimeSource, /setInterval\\s*\\(/);
```

- [ ] **Step 2: Prove red**

```bash
npm run check:web-experience
```

- [ ] **Step 3: Implement the scheduler**

Track one timer, one `AbortController`, `running`, `paused`, `stopped`, `failures`, and `nextDueAt`. Await `task(signal)` before scheduling; reset after success; use `min(intervalMs * 2 ** failures, maxBackoffMs)` after failure; pause cancels/aborts; resume runs only stale work; stop is idempotent.

- [ ] **Step 4: Move the inline IIFE into one bundled module**

Move existing DOM helpers, route progress, fuel/expense rendering, gallery, and countdown bodies into `initHomeDashboard`. Import normalization/map detail/altitude from `liveSync.ts`. Read configuration from `[data-home-dashboard]`. Use:

```ts
const PUBLIC_TRIP = '/api/v2/public/trips/kuzey-2026';
const urls = {
  live: `${PUBLIC_TRIP}/live-location`,
  expenses: `${PUBLIC_TRIP}/expense-summary`,
  plan: `${PUBLIC_TRIP}/published-plan`,
  roadfeed: '/api/roadfeed',
};
```

Create loops at 20s, 60s, 5m, and 30m. Pause/resume on visibility, stop on `pagehide`, and replace countdown interval with aligned recursive `setTimeout`. Keep response parsers unchanged.

- [ ] **Step 5: Verify and commit**

```bash
npm run check:web-experience
npm run check:web-sync
npm run build
git add src/scripts/polling.ts src/scripts/homeDashboard.ts src/pages/index.astro tools/check-web-experience.mjs
git commit -m "perf: bundle and serialize live journey updates"
```

### Task 6: Add the 15-minute/10-km weather cache

**Files:**
- Create: `src/scripts/weather.ts`
- Modify: `src/scripts/homeDashboard.ts`
- Test: `tools/check-web-experience.mjs`

**Interfaces:**
- Produces: `shouldRefreshWeather(entry, location, now, ttlMs = 900_000, movementKm = 10): boolean`; `refreshWeatherCache(existing, location, fetcher, now): Promise<WeatherRefreshResult>`.

- [ ] **Step 1: Add failing cache tests**

```js
assert.equal(shouldRefreshWeather(entry, nearby, entry.fetchedAt + 899_999), false);
assert.equal(shouldRefreshWeather(entry, overTenKm, entry.fetchedAt + 60_000), true);
assert.equal(shouldRefreshWeather(entry, nearby, entry.fetchedAt + 900_000), true);
const failed = await refreshWeatherCache(entry, nearby, async () => { throw new Error("offline"); }, entry.fetchedAt + 900_000);
assert.equal(failed.entry, entry);
```

- [ ] **Step 2: Prove red**

```bash
npm run check:web-experience
```

- [ ] **Step 3: Implement and integrate**

Use Haversine distance. Store `{ lat, lng, fetchedAt, snapshot }` only after successful Open-Meteo normalization. On failure retain the entry and render its value with “Bağlantı kesildi · <age>”; abort on page hide. A failed request must not update cache position/time.

- [ ] **Step 4: Verify and commit**

```bash
npm run check:web-experience
npm run check:web-sync
git add src/scripts/weather.ts src/scripts/homeDashboard.ts tools/check-web-experience.mjs
git commit -m "perf: bound weather refresh frequency"
```

### Task 7: Optimize images, metadata, and browser headers

**Files:**
- Move: four hero/gallery sources into `src/assets/journey/`
- Create: `vercel.json`
- Modify: `src/components/JourneyHero.astro`, `src/pages/index.astro`
- Modify: `src/layouts/MainLayout.astro`, `src/pages/day/[slug].astro`, `public/robots.txt`
- Test: `tools/check-web-experience.mjs`

**Interfaces:**
- Produces: responsive AVIF/WebP; layout `image?: string`, `type?: 'website' | 'article'`; canonical/OG/Twitter metadata; explicit Vercel headers.

- [ ] **Step 1: Add failing image/SEO/header contracts**

Assert `Picture` comes from `astro:assets`; hero is eager/high-priority; gallery is lazy; layout has canonical/OG/Twitter tags; robots uses `https://istanbul-letonya-karavan-astro.vercel.app/sitemap-index.xml`; headers are immutable for `/_astro/(.*)` and `/assets/letonca/ses/(.*)`, and no-store for APIs, worker, manifests, and trip data.

- [ ] **Step 2: Prove red**

```bash
npm run check:web-experience
```

- [ ] **Step 3: Move and render images**

Use `git mv` for `kuzey-road-motion.webp`, `follow-highway.jpg`, `follow-budapest.jpg`, and `follow-sofia.png`. Hero widths: `[640, 960, 1440, 1920]`; gallery widths: `[420, 720, 1080]`; formats: `['avif', 'webp']`. Preserve crops, alts, ordering, and visual classes.

- [ ] **Step 4: Implement metadata and caching**

Build canonical from `new URL(Astro.url.pathname, Astro.site)`; make social images absolute; give home/day distinct title/description/image and day `type="article"`. Remove unused unpkg/Google preconnects. Add one-year immutable headers for the two hashed sources and `no-store, max-age=0` for `/api/(.*)`, `/sw.js`, `/kuzey-version.json`, `/manifest.webmanifest`, and `/trip-data.json`. Fix robots.

- [ ] **Step 5: Verify and commit**

```bash
npm run check:web-experience
npm run build
find dist/_astro -type f \\( -name '*.avif' -o -name '*.webp' \\) | grep -q .
git add src/assets/journey src/components/JourneyHero.astro src/pages/index.astro src/layouts/MainLayout.astro src/pages/day/'[slug].astro' public/robots.txt vercel.json tools/check-web-experience.mjs
git commit -m "perf: optimize journey assets and metadata"
```

### Task 8: Run full Package 2 acceptance

**Files:**
- Verify only: Package 2 files
- Remove after QA: only `.tmp-web-package2-*.png`

**Interfaces:**
- Produces: committed, browser-accepted Package 2 ready for final cross-package deployment.

- [ ] **Step 1: Run all server/web checks**

```bash
npm run check:web-experience
npm run check:web-sync
npm run check:travel-content
npm run check:trip-api
npm run check:account-auth
npm run check:accounts
npm run check:latvian-pack
npm run check
npm run lint
npm run build
npm audit --omit=dev
```

Expected: every command exits 0.

- [ ] **Step 2: Start the mandated background server**

```bash
npm exec astro dev -- --background
npm exec astro dev -- status
```

- [ ] **Step 3: Verify 390×844 and 1440×900**

In the in-app Browser confirm no overflow/console errors; every day action opens the matching slug; day maps contain one leg and no live badge; focus is visible; controls are at least 44px; headings and inline-link underlines are correct.

- [ ] **Step 4: Verify network behavior**

Confirm below-fold Leaflet/tile requests begin only near the map; hide/show creates no duplicate polls; repeated movement under 10 km within 15 minutes creates one weather request; offline mutable API reads show disconnected age and are never served from service-worker cache.

- [ ] **Step 5: Inspect output and clean up**

Inspect `dist/index.html`, one day page, `dist/_astro`, `dist/sw.js`, and sitemap. Delete only Task 8's temporary screenshots, preserve unrelated untracked files, then:

```bash
npm exec astro dev -- stop
git status --short
git log --oneline -10
```

Expected: server stopped, no QA temp remains, all Package 2 changes committed. Deployment occurs only after Packages 1 and 3 pass the master verification.
