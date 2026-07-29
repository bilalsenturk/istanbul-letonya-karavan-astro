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
