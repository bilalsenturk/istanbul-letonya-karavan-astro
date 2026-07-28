import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const root = process.cwd();
const liveSyncUrl = pathToFileURL(path.join(root, "src/scripts/liveSync.ts")).href;
const liveSync = await import(liveSyncUrl);

const normalized = liveSync.normalizeLiveRecord({
  lat: 41.6764,
  lng: 26.5581,
  speedKmh: 82.3,
  city: "Edirne",
  journeyStarted: true,
  activeRouteStop: "Sofya",
  activeRouteCode: "BG",
  activeRouteStartedAt: "2026-07-22T08:00:00Z",
  nextStop: "Sofya",
  nextFlag: "🇧🇬",
  remainingKm: 321.4,
  remainingMin: 245,
  remainingToFinalKm: 2980.7,
  traveledKm: 194.2,
  legProgress: 142,
  altitudeMeters: 126.2,
  altitudeKind: "absolute",
  altitudeSource: "gps",
  pressureHpa: 1009.6,
  altitudeAvailable: true,
  ts: "2026-07-22T08:12:00Z",
});

assert.ok(normalized, "live records with valid coordinates should normalize");
assert.equal(normalized.routeStarted, true);
assert.equal(normalized.activeRouteStop, "Sofya");
assert.equal(normalized.nextStop, "Sofya");
assert.equal(normalized.legProgress, 100, "leg progress should be clamped");
assert.equal(normalized.altitudeMeters, 126.2);
assert.equal(normalized.pressureHpa, 1009.6);

const altitude = liveSync.formatAltitude(normalized);
assert.deepEqual(altitude, {
  label: "Rakım",
  text: "126 m",
  note: "GPS rakımı",
});

const mapDetail = liveSync.mapLiveEventDetail(normalized);
assert.equal(mapDetail.routeStarted, true);
assert.deepEqual(mapDetail.position, { lat: 41.6764, lng: 26.5581 });
assert.equal(mapDetail.activeRouteStop, "Sofya");
assert.equal(mapDetail.remainingKm, 321.4);
assert.equal(mapDetail.remainingMin, 245);

const inactive = liveSync.normalizeLiveRecord({
  lat: 41.0201024108056,
  lng: 29.099259743749787,
  speedKmh: 0,
  city: "Ümraniye",
  journeyStarted: false,
  activeRouteStop: "Sofya",
  activeRouteCode: "BG",
  activeRouteStartedAt: "2026-07-22T08:00:00Z",
  nextStop: "Sofya",
  remainingKm: 514,
  remainingToFinalKm: 3265,
  remainingMin: 385,
  traveledKm: 66,
  legProgress: 11,
});

assert.ok(inactive, "inactive records with valid coordinates should normalize");
assert.equal(inactive.routeStarted, false);
assert.equal(inactive.traveledKm, 0, "inactive journey must not show traveled distance");
assert.equal(inactive.legProgress, 0, "inactive journey must not fill current leg");
assert.equal(inactive.activeRouteStop, null, "inactive journey must not claim an active route");
assert.equal(inactive.activeRouteCode, null, "inactive journey must not claim an active route code");
assert.equal(inactive.activeRouteStartedAt, null, "inactive journey must not expose stale route start time");

const routeMapSource = fs.readFileSync(path.join(root, "src/scripts/routeMap.ts"), "utf8");
assert.match(routeMapSource, /kuzey:live-location/, "map should listen to live app state");
assert.match(routeMapSource, /liveMarker/, "map should render a live vehicle marker");
assert.match(routeMapSource, /applyLiveState/, "map should re-style active route from live state");
assert.match(routeMapSource, /passat-adria-map-icon\.svg/, "map should use the supplied Passat + Adria SVG icon");
assert.match(routeMapSource, /L\.control\.zoom\(\{\s*position:\s*['"]bottomright['"]\s*\}\)\.addTo\(map\)/, "map should expose Leaflet zoom in and zoom out controls");
assert.match(routeMapSource, /leaflet-control-zoom-out/, "map should style the zoom out control explicitly");

const homeSource = fs.readFileSync(path.join(root, "src/pages/index.astro"), "utf8");
assert.match(homeSource, /live-altitude/, "home should expose app altitude");
assert.match(homeSource, /live-pressure/, "home should expose app pressure");
assert.match(homeSource, /roadfeed-fuel/, "home should mirror iOS road feed");
assert.match(homeSource, /kuzey:live-location/, "home should dispatch live state to the map");
assert.match(homeSource, /follow-riga-hero\.jpg/, "home hero should use the Riga caravan image");
assert.match(homeSource, /follow-highway\.jpg/, "home should include the highway caravan image");
assert.match(homeSource, /follow-budapest\.jpg/, "home should include the Budapest caravan image");
assert.match(homeSource, /follow-sofia\.png/, "home should include the Sofia caravan image");
assert.match(homeSource, /follow-gallery/, "home should render a dedicated image gallery");
assert.match(homeSource, /follow-gallery__track/, "home gallery should be swipeable");
assert.match(homeSource, /data-gallery-scroll/, "home gallery should expose carousel controls");
assert.match(homeSource, /hero-countdown/, "home hero should show the app departure countdown");
assert.match(homeSource, /\/api\/plan/, "home hero countdown should use the published app plan");
assert.match(homeSource, /hero-route-timeline/, "home hero should expose a live stop timeline");
assert.match(homeSource, /data-hero-route-stop/, "home hero timeline should include every stop");
assert.match(homeSource, /<details\s+class="route-timeline-section"[\s\S]*?<summary\s+class="route-timeline-head"/, "route timeline should be collapsible");
assert.match(homeSource, /data-route-details/, "route timeline should expose a details hook");
assert.match(homeSource, /routeDetails\.open\s*=\s*!isMobileRouteSummary/, "route timeline should start collapsed on mobile");
assert.match(homeSource, /routeDetails\.classList\.toggle\('is-started'/, "route timeline summary should reflect started state with color");
assert.match(homeSource, /\.route-timeline-head::before\s*\{[\s\S]*?content:\s*none/, "route timeline summary should suppress the global details marker");
assert.match(homeSource, /aspect-ratio:\s*3\s*\/\s*2/, "mobile hero should preserve the hero photo ratio");
assert.match(homeSource, /grid-row:\s*2/, "mobile hero content should sit below the photo");
assert.doesNotMatch(homeSource, /padding-top:\s*min\(56svh,\s*440px\)/, "mobile hero should not crop the photo with a fixed top spacer");
assert.doesNotMatch(homeSource, /@media\s*\(max-width:\s*760px\)[\s\S]*?\.hero-route-timeline__track\s*\{[\s\S]*?min-width:\s*640px/, "mobile hero stop timeline must not force page overflow");
assert.match(homeSource, /@media\s*\(max-width:\s*760px\)[\s\S]*?\.hero-route-timeline__track\s*\{[\s\S]*?grid-template-columns:\s*repeat\(8,\s*minmax\(0,\s*1fr\)\)/, "mobile hero timeline should keep all stops visible on one line");
assert.doesNotMatch(homeSource, /@media\s*\(max-width:\s*760px\)[\s\S]*?\.hero-countdown\s*\{[\s\S]*?left:\s*12px[\s\S]*?width:\s*auto/, "mobile countdown must not create a full-width dark strip over the hero photo");
assert.match(homeSource, /@media\s*\(max-width:\s*760px\)[\s\S]*?\.hero-countdown\s*\{[\s\S]*?rgba\(5,\s*8,\s*12,\s*0\.7[0-9]\)/, "mobile countdown should use a readable compact dark glass layer");
assert.match(homeSource, /@media\s*\(max-width:\s*760px\)[\s\S]*?\.hero-countdown__grid strong\s*\{[\s\S]*?text-shadow:/, "mobile countdown numbers should stay readable on bright photos");

console.log("Web/app sync checks passed.");
