# Task 3 report — explicit map modes and lazy Leaflet

## RED

Command:

```bash
npm run check:web-experience
```

Result: failed as expected with `ERR_MODULE_NOT_FOUND` for
`src/scripts/routeMapData.ts`. The new contract test imports this module before
exercising day/journey selectors, so the failure proved the requested API was
not present.

## GREEN

Implemented:

- `RouteMapMode`, Turkish base-sensitive stop matching, and day/journey stop and
  geometry selectors.
- A near-viewport `IntersectionObserver` loader (`300px 0px`, `0.01`) that
  dynamically imports the Leaflet runtime and avoids duplicate initialization.
- Required `mode` and `live` map props, data attributes, and live-status markup
  only for live maps.
- Exact day-leg stop data, matching geometry leg rendering, and no route-map live
  event subscription for static day maps.
- Tile-load-only readiness plus tile-error fallback recovery.

Commands and results:

```bash
npm run check:web-experience
# Web experience checks passed.

npm run check:web-sync
# Web/app sync checks passed.

npm run check
# 0 errors, 0 warnings, 2 pre-existing hints in tools/check-latvian-pack.mjs.

npm run build
# Astro build completed successfully; all six day pages and the homepage prerendered.

git diff --check
# no output (clean)
```

The web-experience check executes the new selector contracts and a fake
`IntersectionObserver` loader harness. Source assertions remain secondary checks
for the dynamic-import boundary and page wiring.

## Files

- `src/scripts/routeMapData.ts` (new)
- `src/scripts/routeMapLoader.ts` (new)
- `src/scripts/routeMap.ts`
- `src/components/RouteMap.astro`
- `src/components/JourneyHero.astro`
- `src/components/LiveDashboard.astro`
- `src/pages/index.astro`
- `src/pages/day/[slug].astro`
- `tools/check-web-experience.mjs`

## Concerns

No functional blockers found. The Leaflet JavaScript runtime is in the dynamic
route-map chunk and is imported only when a map enters the near viewport.

## Fix Round 1

### RED

Tile-batch recovery test:

```bash
npm run check:web-experience
```

Failed as expected:

```text
TypeError: routeMapData.createTileReadinessController is not a function
```

This proved there was no production boundary capable of retaining a tile error
across Leaflet's later aggregate `load` event.

After the tile controller was green, the driven lazy-loader test failed as
expected:

```text
AssertionError [ERR_ASSERTION]: repeated intersecting entries must import the map runtime once
0 !== 1
```

This proved `registerRouteMaps` ignored the injected importer and that the old
test never exercised the observer callback or deferred initialization.

### GREEN

- Added and executed `createTileReadinessController`: `loading` begins a clean
  batch, `tileError` restores the fallback and marks that batch failed, and the
  aggregate `load` only enables the map when the batch had no errors. A later
  error-free batch visibly recovers.
- Added a production `RouteMapImporter` seam with the real dynamic import as its
  default. The observer harness now drives false, true, and repeated entries and
  proves zero imports outside the near viewport, then one import and one init.
- Added selector cases for `İSTANBUL`/`istanbul`, `IĞDIR`/`ığdır`, `Çeşme`/
  `ÇEŞME`, and `NOVİ SAD`/`Novi Sad`.

Final commands and results:

```bash
npm run check:web-experience
# Web experience checks passed.

npm run check:web-sync
# Web/app sync checks passed.

NO_COLOR=1 npm run check
# Result (58 files): 0 errors, 0 warnings, 2 hints.

npm run build
# Complete; homepage, six day pages, and trip-data route prerendered.

git diff --check
# no output (clean)
```

The two pre-existing hints are exactly:

```text
tools/check-latvian-pack.mjs:509:41 - ts(6133): 'unused' is declared but its value is never read.
tools/check-latvian-pack.mjs:481:65 - ts(6133): 'unused' is declared but its value is never read.
```

No new diagnostics or known blockers were introduced in Fix Round 1.
