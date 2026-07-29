# Mobile Cinematic Live Map Hero Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and deploy a mobile-first homepage hero that combines a cinematic moving-caravan image with a lightweight live route map and never exposes raw coordinates.

**Architecture:** Keep the page in Astro and extract the hero into a focused `JourneyHero.astro` component. Reuse `RouteMap.astro` with a compact, non-interactive hero variant; keep the full interactive map below. Preserve the current live-data pipeline in `index.astro`, but replace coordinate fallback logic with a tested human-readable location formatter.

**Tech Stack:** Astro 7, TypeScript, Leaflet 1.9, CSS transforms, Node assertion scripts, Vercel adapter and CLI.

## Global Constraints

- Design mobile first for 360 px, 390 px, and 430 px widths.
- Use `clamp(320px, 44svh, 430px)` for the cinematic mobile image height.
- Use a 180 px compact map on mobile.
- Never render latitude or longitude as user-facing text.
- Keep the visible hero copy limited to the title, readable live place, compact departure/route state, four-point route summary, and mini map.
- Move distance, traveled distance, weather, fuel, and spending into the summary below the hero.
- Stop continuous movement under `prefers-reduced-motion: reduce`.
- Keep existing API routes, trip data, day pages, account code, and iOS code unchanged.
- Do not include unrelated dirty icon, service-worker, brand-tool, or `MainLayout.astro` changes in implementation commits.
- Deploy only committed task files from a clean archive of `HEAD`.

---

### Task 1: Create the accepted visual concept and hero asset

**Files:**
- Reference: `.tmp-existing-hero-mobile.png`
- Reference: `public/assets/follow-highway.jpg`
- Create: `docs/superpowers/concepts/2026-07-29-journey-hero-mobile.png`
- Create: `docs/superpowers/concepts/2026-07-29-journey-hero-desktop.png`
- Create: `public/assets/hero/kuzey-road-motion.webp`

**Interfaces:**
- Consumes: Approved design in `docs/superpowers/specs/2026-07-29-mobile-sinematik-canli-harita-hero-design.md`.
- Produces: Mobile and desktop concept references plus the production hero image used by `JourneyHero.astro`.

- [ ] **Step 1: Generate the mobile hero concept**

Use the installed Image Gen workflow with `.tmp-existing-hero-mobile.png` as the edit target and this brief:

```text
Use case: ui-mockup
Asset type: mobile homepage hero redesign at 390 x 844
Primary request: Redesign the existing KUZEY journey homepage hero by combining a cinematic moving-caravan scene with a compact live map. Preserve the page purpose and Turkish content hierarchy.
Structure: cinematic road image in the upper 44svh; two-line “Leyla'nın Kuzey Yolculuğu” heading; readable live place “Ümraniye, İstanbul”; supporting state “Sofya yönü · kalkışa 4 gün”; four-point route rail for İstanbul, Şu an, Sofya, Riga; 180 px live mini map; the beginning of a horizontal trip-summary rail visible below.
Visual system: dark asphalt and ink surfaces, warm dawn light, white typography, safety-orange route accent, restrained green live signal, square-to-soft 14 px corners, editorial travel photography, strong mobile hierarchy.
Interaction cues: slow image drift, flowing route line, pulsing live marker.
Constraints: code-native UI text and controls; no raw coordinates; no six-card grid in the hero; no decorative badge above the heading; no fake metrics; no neon glow; no generic dashboard chrome; practical Astro/CSS implementation.
```

Save the selected output at `docs/superpowers/concepts/2026-07-29-journey-hero-mobile.png`.

- [ ] **Step 2: Generate the desktop companion concept**

Use the mobile concept as the visual reference and this brief:

```text
Use case: ui-mockup
Asset type: desktop homepage hero at 1440 x 1000
Primary request: Extend the accepted KUZEY mobile hero into desktop without changing its information hierarchy.
Structure: title and live journey status on the left; wide cinematic caravan image on the right; compact live map attached to the lower edge of the image; four-point route rail; trip-summary rail visible below the hero.
Visual system: exactly match the mobile concept’s dark asphalt palette, dawn photography, typography personality, route accent, live marker, spacing, and corner treatment.
Constraints: one clear focal point; no full-width grid of statistic cards over the photo; no decorative badge above the heading; no raw coordinates; practical Astro/CSS implementation.
```

Save the selected output at `docs/superpowers/concepts/2026-07-29-journey-hero-desktop.png`.

- [ ] **Step 3: Create the production road image**

Edit `public/assets/follow-highway.jpg` while preserving the towing vehicle and Adria caravan:

```text
Use case: lighting-weather
Asset type: responsive website hero photograph
Primary request: Turn the existing highway caravan photo into a cinematic early-dawn road scene with a strong feeling of forward motion.
Invariants: preserve the white towing vehicle, white Adria caravan, camera angle, road direction, realistic proportions, tow connection, wheels, and vehicle identity.
Changes: warm low sunrise from the left; subtle road and background motion blur; crisp vehicle; deeper asphalt contrast; distant European landscape; remove the Budapest road sign and all readable signage.
Composition: keep the vehicle in the lower-left/middle safe area; leave usable dark negative space above and to the left for mobile copy; support both portrait and landscape crops.
Avoid: fake license text, extra vehicles near the tow connection, rain, city streets, neon, dramatic color wash, watermark, UI text.
```

Copy the selected image into `public/assets/hero/`, convert it to WebP as `kuzey-road-motion.webp`, and verify dimensions with:

```bash
sips -g pixelWidth -g pixelHeight public/assets/hero/kuzey-road-motion.webp
```

Expected: width at least 1400 px and height at least 900 px.

- [ ] **Step 4: Inspect all three images**

Use `view_image` on both concepts and the production asset. Reject and regenerate any result with unreadable text, broken towing geometry, a pasted-looking map, or raw coordinates.

- [ ] **Step 5: Commit the visual references and asset**

```bash
git add docs/superpowers/concepts/2026-07-29-journey-hero-mobile.png \
  docs/superpowers/concepts/2026-07-29-journey-hero-desktop.png \
  public/assets/hero/kuzey-road-motion.webp
git commit -m "design: add cinematic live-map hero concept"
```

### Task 2: Add and test friendly live-location behavior

**Files:**
- Modify: `tools/check-web-app-sync.mjs`
- Modify: `src/scripts/liveSync.ts`

**Interfaces:**
- Consumes: `NormalizedLiveRecord` and planned route stops.
- Produces: `formatFriendlyLocation(record, stops) -> string`, `heroLiveLabels(record, stops)`, and `installJourneyHeroLiveState(root)`.

- [ ] **Step 1: Write the first failing behavior test**

Add these assertions after the existing inactive-record checks:

```js
const plannedStops = [
  { name: "İstanbul", lat: 41.0082, lng: 28.9784 },
  { name: "Sofya", lat: 42.6977, lng: 23.3219 },
  { name: "Riga", lat: 56.9496, lng: 24.1052 },
];

assert.equal(typeof liveSync.formatFriendlyLocation, "function", "friendly location formatter should exist");
assert.equal(
  liveSync.formatFriendlyLocation(inactive, plannedStops),
  "Ümraniye, İstanbul",
  "a city near a planned stop should include its readable region",
);
```

- [ ] **Step 2: Run the check and verify failure**

```bash
npm run check:web-sync
```

Expected: FAIL with an assertion that `friendly location formatter should exist`.

- [ ] **Step 3: Implement the minimal formatter**

Add `PlannedStop`, a Haversine helper, and `formatFriendlyLocation` to `src/scripts/liveSync.ts`. The minimal implementation returns the city and the nearest planned stop when that stop is within 120 km and has a different name.

- [ ] **Step 4: Run the check and verify the first case passes**

```bash
npm run check:web-sync
```

Expected: PASS.

- [ ] **Step 5: Add failing no-city and route-state cases**

Add literal expectations for:

```js
assert.equal(
  liveSync.formatFriendlyLocation({ ...inactive, city: null }, plannedStops),
  "İstanbul çevresi",
);
assert.equal(
  liveSync.formatFriendlyLocation({ ...normalized, city: null }, plannedStops),
  "Sofya yönünde",
);
assert.equal(
  liveSync.formatFriendlyLocation({ ...inactive, city: null, lat: 0, lng: 0, position: { lat: 0, lng: 0 } }, plannedStops),
  "Konum güncelleniyor",
);
```

Run `npm run check:web-sync` and confirm the first unsupported branch fails.

- [ ] **Step 6: Implement route and empty-state branches**

Add `heroLiveLabels(record, stops)` returning:

```ts
interface HeroLiveLabels {
  place: string;
  state: string;
  current: string;
  next: string;
}
```

Add `installJourneyHeroLiveState(root)` that parses `root.dataset.stops`, applies labels from `window.__kuzeyLiveState`, listens for `kuzey:live-location`, and updates `live-city`, `hero-live-text`, `hero-current-place`, and `hero-next-place` inside that root.

- [ ] **Step 7: Run the completed behavior checks**

```bash
npm run check:web-sync
```

Expected: PASS with all literal location cases.

- [ ] **Step 8: Commit the tested behavior**

```bash
git add tools/check-web-app-sync.mjs src/scripts/liveSync.ts
git commit -m "feat: format live location without coordinates"
```

### Task 3: Add a compact RouteMap variant

**Files:**
- Modify: `src/components/RouteMap.astro`
- Modify: `src/scripts/routeMap.ts`

**Interfaces:**
- Consumes: `routeStops`, `activeFrom`, `activeTo`, and `window.__kuzeyLiveState`.
- Produces: `RouteMap` prop `variant?: 'default' | 'hero'`; `data-compact="true"` for the hero; a non-interactive map that still follows live location.

- [ ] **Step 1: Add the typed variant and compact markup**

Update `Props` and defaults:

```ts
interface Props {
  title: string;
  routeStops: Stop[];
  activeFrom: string;
  activeTo: string;
  height?: string;
  variant?: 'default' | 'hero';
}

const {
  title,
  routeStops,
  activeFrom,
  activeTo,
  height = '360px',
  variant = 'default',
} = Astro.props;
const compact = variant === 'hero';
```

Render `data-compact={compact ? 'true' : 'false'}` on `.route-map`, add `route-map-card--hero` to the section, hide the visual heading in the hero variant, load its fallback image eagerly, and add a unique `Haritayı aç` link to `#harita`.

- [ ] **Step 2: Disable map gestures only in compact mode**

Replace the Leaflet initialization with:

```ts
const compact = container.dataset.compact === 'true';
const map = L.map(container, {
  zoomControl: false,
  scrollWheelZoom: false,
  dragging: !compact,
  touchZoom: !compact,
  doubleClickZoom: !compact,
  boxZoom: !compact,
  keyboard: !compact,
});
if (!compact) L.control.zoom({ position: 'bottomright' }).addTo(map);
```

Use tighter fit padding and `maxZoom: 8` in compact mode. Keep the existing live marker, route progress, fallback image, and full-map behavior.

- [ ] **Step 3: Style the hero map as an unframed route window**

Add component-scoped rules for `.route-map-card--hero`: no visible card heading, 14 px radius, clipped overflow, 180 px minimum height, a compact live-status label, hidden Leaflet attribution on the compact surface, and a 44 px `Haritayı aç` link.

- [ ] **Step 4: Run the source contract**

```bash
npm run check:web-sync
```

Expected: PASS.

- [ ] **Step 5: Commit the compact map**

```bash
git add src/components/RouteMap.astro src/scripts/routeMap.ts
git commit -m "feat: add compact live route map"
```

### Task 4: Build the mobile-first JourneyHero component

**Files:**
- Create: `src/components/JourneyHero.astro`

**Interfaces:**
- Consumes: `routeStops: { name: string; lat: number; lng: number }[]`, `totalKm: number`, and `installJourneyHeroLiveState`.
- Produces: Existing live DOM IDs used by `index.astro`, four route roles, the compact `RouteMap`, and the summary rail.

- [ ] **Step 1: Create the component structure**

Use this prop and component boundary:

```astro
---
import RouteMap from './RouteMap.astro';

interface Stop { name: string; lat: number; lng: number }
interface Props { routeStops: Stop[]; totalKm: number }
const { routeStops, totalKm } = Astro.props;
---

<section class="journey-hero" aria-label="Leyla'nın Kuzey Yolculuğu">
  <div class="journey-hero__media">
    <img
      class="journey-hero__image"
      src="/assets/hero/kuzey-road-motion.webp"
      alt="Günün ilk ışıklarında kuzeye ilerleyen otomobil ve Adria karavan"
      fetchpriority="high"
    />
    <div class="journey-hero__scrim" aria-hidden="true"></div>
    <section class="journey-countdown" aria-live="polite" aria-label="Kalkış durumu">
      <span id="hero-countdown-label">Kalkışa</span>
      <strong><b id="countdown-days">--</b> gün</strong>
      <small><span id="countdown-hours">--</span>:<span id="countdown-minutes">--</span>:<span id="countdown-seconds">--</span></small>
    </section>
    <div class="journey-hero__copy">
      <h1>Leyla'nın<br />Kuzey Yolculuğu</h1>
      <div class="journey-live" aria-live="polite">
        <span class="journey-live__dot" id="live-dot" aria-hidden="true"></span>
        <span class="journey-live__copy"><small>Şu an</small><strong id="live-city">Konum güncelleniyor</strong><span id="hero-live-text">Kalkış hazırlığı</span><time id="live-updated">Bekleniyor</time></span>
      </div>
      <div class="journey-route" aria-label="Rota özeti">
        <span class="journey-route__rail"><span id="hero-route-fill"></span></span>
        <ol>
          <li data-hero-role="start"><i></i><small>İstanbul</small></li>
          <li data-hero-role="current"><i></i><small id="hero-current-place">Şu an</small></li>
          <li data-hero-role="next"><i></i><small id="hero-next-place">Sofya</small></li>
          <li data-hero-role="end"><i></i><small>Riga</small></li>
        </ol>
      </div>
    </div>
  </div>
  <div class="journey-hero__map">
    <RouteMap title="Canlı rota" routeStops={routeStops} activeFrom="İstanbul" activeTo="Riga" height="180px" variant="hero" />
  </div>
</section>
```

Add `data-journey-hero` and `data-stops={JSON.stringify(routeStops)}` to the root section. Add a bundled component script:

```astro
<script>
  import { installJourneyHeroLiveState } from '../scripts/liveSync';

  document.querySelectorAll<HTMLElement>('[data-journey-hero]').forEach((root) => {
    installJourneyHeroLiveState(root);
  });
</script>
```

Add the summary rail immediately after the hero and preserve these update IDs: `remaining-distance`, `remaining-note`, `live-traveled`, `journey-progress-note`, `spend-amount`, `spend-note`, `fuel-used`, `fuel-note`, `weather-now`, and `weather-detail`.

- [ ] **Step 2: Implement the approved visual system**

Create component-scoped CSS with:

- Dark asphalt background `#080b0f`.
- Warm route accent `#ff9b50` and live green `#58e69a`.
- Mobile image height `clamp(320px, 44svh, 430px)`.
- Mobile two-line heading `clamp(2.55rem, 12vw, 3.5rem)`.
- 180 px mini map.
- Horizontally scrollable summary rail with 78vw cards on mobile and a five-column open rail on desktop.
- Desktop two-column hero with a maximum content width of 1280 px.
- A slow `transform: scale(1.045) translate3d(-1.5%, 0, 0)` image drift and animated route-dash background.
- A complete `@media (prefers-reduced-motion: reduce)` rule that sets animation to `none` and transform to `none`.

- [ ] **Step 3: Run the contract**

```bash
npm run check:web-sync
```

Expected: PASS.

- [ ] **Step 4: Commit the component**

```bash
git add src/components/JourneyHero.astro
git commit -m "feat: build mobile-first journey hero"
```

### Task 5: Integrate the hero and remove coordinate fallback

**Files:**
- Modify: `src/pages/index.astro`

**Interfaces:**
- Consumes: `JourneyHero`, `mapStops`, current live API record, route timeline, and `kuzey:live-location`.
- Produces: Updated hero state without competing direct location writes, unchanged downstream map and detail sections.

- [ ] **Step 1: Replace the old hero markup**

Import the component:

```astro
import JourneyHero from '../components/JourneyHero.astro';
```

Replace the old `.follow-hero` section with:

```astro
<JourneyHero routeStops={mapStops} totalKm={tripData.totalKm} />
```

Keep route timeline, full map, road details, expenses, and gallery in their existing order. Remove the old hero-only CSS blocks from `index.astro`; keep downstream section styles.

- [ ] **Step 2: Stop the old script from overwriting friendly labels**

In `updateLiveUi`, remove the coordinate fallback and these direct writes:

```js
const next = live.activeRouteStop || live.nextStop || '-';
```

`JourneyHero.astro` owns those four labels through the tested live-sync helper. Keep `live-updated` in the page script.

Update `updateHeroRoute` to toggle `is-passed`, `is-active`, and `is-next` on the four `data-hero-role` elements. Preserve `hero-route-fill` as the total route percentage.

- [ ] **Step 3: Remove obsolete source checks**

Delete `tools/check-web-app-sync.mjs` assertions that require the old eight-stop hero rail, the old 3:2 mobile image, the old large countdown overlay, or exact hero asset filenames. The behavior tests for `formatFriendlyLocation` remain.

- [ ] **Step 4: Run checks**

```bash
npm run check:web-sync
npm run check
npm run lint
npm run build
```

Expected: all commands exit 0. If an existing unrelated dirty file fails lint, rerun ESLint against `src/pages/index.astro`, `src/components/JourneyHero.astro`, `src/components/RouteMap.astro`, and `src/scripts/routeMap.ts`, then record the unrelated file separately.

- [ ] **Step 5: Commit the integration and updated regression script**

```bash
git add src/pages/index.astro tools/check-web-app-sync.mjs
git commit -m "feat: integrate cinematic live-map hero"
```

### Task 6: Verify visual fidelity and mobile behavior

**Files:**
- Create temporarily: `.tmp-hero-mobile-final.png`
- Create temporarily: `.tmp-hero-desktop-final.png`
- Remove before handoff: `.tmp-existing-hero-desktop.png`, `.tmp-existing-hero-mobile.png`, `.tmp-hero-mobile-final.png`, `.tmp-hero-desktop-final.png`

**Interfaces:**
- Consumes: Local Astro server at `http://localhost:4322/`, accepted concept PNGs.
- Produces: Browser-verified mobile and desktop implementation with no overflow, raw coordinates, clipped content, or inert map link.

- [ ] **Step 1: Reload the running Astro server**

Confirm the background server with:

```bash
./node_modules/.bin/astro dev status
```

Use the in-app Browser at `http://localhost:4322/` and reload after the implementation changes.

- [ ] **Step 2: Verify 390 x 844**

Set the browser viewport to 390 x 844. Capture the first viewport and verify:

```text
1. The road image, title, readable current place, four-point route rail, and mini map appear in the opening flow.
2. No coordinate-shaped “41.0000, 29.0000” string is visible.
3. The old six-card overlay is gone.
4. The page width equals the viewport width.
5. The “Haritayı aç” link is at least 44 px high and scrolls to #harita.
6. The next summary section is visibly beginning below the hero.
```

Save `.tmp-hero-mobile-final.png`.

- [ ] **Step 3: Verify 360 px and 430 px widths**

At 360 x 800 and 430 x 932, check `document.body.scrollWidth === window.innerWidth`, title line breaks, summary scrolling, and mini-map height.

- [ ] **Step 4: Verify 1440 x 1000**

Set 1440 x 1000, reload, and save `.tmp-hero-desktop-final.png`. Verify the title/live copy and cinematic image form one composition, the map attaches to the media area, and the summary uses one desktop rail.

- [ ] **Step 5: Verify live states and motion preference**

Use the local fallback record and browser evaluation to confirm the friendly place reads `Ümraniye, İstanbul`. Emulate or inspect reduced-motion CSS and confirm the image and route animations stop. Check console logs for errors.

- [ ] **Step 6: Compare concepts and renders with `view_image`**

Use `view_image` on:

```text
docs/superpowers/concepts/2026-07-29-journey-hero-mobile.png
.tmp-hero-mobile-final.png
docs/superpowers/concepts/2026-07-29-journey-hero-desktop.png
.tmp-hero-desktop-final.png
```

Record a fidelity ledger covering copy, composition, typography, palette, image treatment, map placement, spacing, mobile overflow, and motion. Fix every actionable mismatch before continuing.

- [ ] **Step 7: Remove temporary QA files**

Move the four `.tmp-*.png` files to Trash or delete only those exact files after visual QA.

### Task 7: Deploy the committed implementation to Vercel

**Files:**
- Read: `.vercel/project.json`
- Do not deploy: unrelated uncommitted workspace changes

**Interfaces:**
- Consumes: Clean committed `HEAD`, linked Vercel project `istanbul-letonya-karavan-astro`.
- Produces: Production deployment URL and live mobile/desktop verification.

- [ ] **Step 1: Verify the final commit and dirty-file boundary**

```bash
git status --short
git log -5 --oneline
```

Confirm every hero implementation file is committed. Confirm unrelated icon, `MainLayout.astro`, service-worker, and `tools/brand/` changes remain outside the implementation commits.

- [ ] **Step 2: Build a clean deployment archive**

```bash
deploy_dir="$(mktemp -d)"
git archive --format=tar HEAD | tar -x -C "$deploy_dir"
mkdir -p "$deploy_dir/.vercel"
cp .vercel/project.json "$deploy_dir/.vercel/project.json"
```

- [ ] **Step 3: Validate the clean archive**

```bash
npm ci --prefix "$deploy_dir"
npm run build --prefix "$deploy_dir"
```

Expected: Astro production build exits 0.

- [ ] **Step 4: Deploy production**

Run from the clean archive:

```bash
npx vercel --prod --yes
```

Capture the production URL returned by Vercel. This action is authorized by the user's explicit request to deploy.

- [ ] **Step 5: Verify the production URL**

Open the production URL in the in-app Browser. Check the hero at 390 x 844 and 1440 x 1000, confirm the production image and map tiles load, confirm the friendly place contains no coordinates, and test `Haritayı aç`.

- [ ] **Step 6: Final completion checks**

```bash
npm run check:web-sync
npm run check
npm run build
```

Report the deployment URL, concept paths, viewport sizes, fidelity ledger summary, live interaction path, and any intentional deviations.
