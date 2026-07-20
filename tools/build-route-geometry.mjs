#!/usr/bin/env node
// Gerçek sürüş rotasını (yolları takip eden) OSRM'den çekip web haritası için kaydeder.
//   node tools/build-route-geometry.mjs
// Çıktı: public/assets/route-geometry.json  { legs: [{from,to,distance,duration,coords:[[lat,lng]…]}] }
//
// Neden derleme zamanı: sayfa açılışında dış servise bağımlı kalmasın, hızlı ve
// kesintisiz olsun. Duraklar değişirse bu script'i tekrar çalıştır.
import fs from 'node:fs';

const trip = JSON.parse(fs.readFileSync('src/data/tripData.json', 'utf8'));
const stops = trip.stops;
const coordParam = stops.map((s) => `${s.lng},${s.lat}`).join(';');

const url =
  `https://router.project-osrm.org/route/v1/driving/${coordParam}` +
  `?overview=full&geometries=geojson&steps=false`;

console.log(`${stops.length} durak → OSRM sorgusu…`);
const res = await fetch(url, { headers: { 'User-Agent': 'KuzeyTripApp/1.0' } });
const data = await res.json();
if (data.code !== 'Ok') {
  console.error('OSRM hatası:', data.code, data.message || '');
  process.exit(1);
}

const route = data.routes[0];

/** Rotayı ~hedef nokta sayısına seyrelt (şekli bozmadan, uçları koruyarak). */
function decimate(coords, target) {
  if (coords.length <= target) return coords;
  const step = coords.length / target;
  const out = [];
  for (let i = 0; i < coords.length; i += step) out.push(coords[Math.floor(i)]);
  const last = coords[coords.length - 1];
  const tail = out[out.length - 1];
  if (!tail || tail[0] !== last[0] || tail[1] !== last[1]) out.push(last);
  return out;
}

// OSRM tüm rotayı tek geometri olarak verir; etaplara bölmek için her bacağın
// bitiş durağına en yakın noktayı bularak kesiyoruz.
const all = route.geometry.coordinates; // [lng, lat]
const nearestIndex = (lng, lat, from) => {
  let best = from, bestD = Infinity;
  for (let i = from; i < all.length; i++) {
    const d = (all[i][0] - lng) ** 2 + (all[i][1] - lat) ** 2;
    if (d < bestD) { bestD = d; best = i; }
  }
  return best;
};

const legs = [];
let cursor = 0;
for (let i = 0; i < stops.length - 1; i++) {
  const end = i === stops.length - 2
    ? all.length - 1
    : nearestIndex(stops[i + 1].lng, stops[i + 1].lat, cursor);
  const slice = all.slice(cursor, end + 1);
  const perLeg = Math.max(60, Math.round(1400 / (stops.length - 1)));
  legs.push({
    from: stops[i].name,
    to: stops[i + 1].name,
    distance: Math.round(route.legs[i]?.distance ?? 0),
    duration: Math.round(route.legs[i]?.duration ?? 0),
    coords: decimate(slice, perLeg).map(([lng, lat]) => [
      Number(lat.toFixed(5)),
      Number(lng.toFixed(5)),
    ]),
  });
  cursor = end;
}

const out = {
  source: 'OSRM (project-osrm.org) · gerçek sürüş rotası',
  generatedAt: new Date().toISOString(),
  totalDistanceKm: Math.round(route.distance / 1000),
  totalDurationH: Number((route.duration / 3600).toFixed(1)),
  legs,
};

fs.mkdirSync('public/assets', { recursive: true });
fs.writeFileSync('public/assets/route-geometry.json', JSON.stringify(out));
const kb = Math.round(fs.statSync('public/assets/route-geometry.json').size / 1024);
console.log(`✓ ${legs.length} etap · ${legs.reduce((s, l) => s + l.coords.length, 0)} nokta · ${out.totalDistanceKm} km · ${out.totalDurationH} sa · ${kb}KB`);
legs.forEach((l) => console.log(`   ${l.from} → ${l.to}: ${Math.round(l.distance / 1000)} km, ${l.coords.length} nokta`));
