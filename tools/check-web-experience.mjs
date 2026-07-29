import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const liveSync = await import(pathToFileURL(path.join(root, 'src/scripts/liveSync.ts')).href);

const sourceFiles = ['src/components/JourneyHero.astro', 'src/components/RouteMap.astro', 'src/pages/index.astro'];
const [heroSource, routeMapSource, indexSource] = await Promise.all(
  sourceFiles.map((sourceFile) => readFile(path.join(root, sourceFile), 'utf8')),
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
