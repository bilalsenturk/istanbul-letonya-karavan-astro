import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import data from "../public/assets/travel-content.json" with { type: "json" };

const expected = ["sofia", "novi-sad", "budapest", "krakow", "warsaw", "riga"];
assert.deepEqual(Object.keys(data.destinations).sort(), expected.sort());

const expectedCamps = {
  sofia: ["Mega Park Vrana", "Camper Parking Sofia"],
  "novi-sad": ["Auto Camp Farma 47", "Eko Kamp Fruška Gora"],
  budapest: ["Haller Camping", "Ave Natura Camping"],
  krakow: ["Camping Smok", "Camping Clepardia"],
  warsaw: ["Camping Motel WOK", "Camper Park Venessa", "Camping Warszawa nr 184"],
  riga: ["Camping & Yachts", "Riga City Camping", "Camping Zanzibara"],
};

const expectedAttractions = {
  sofia: ["Alexander Nevsky Katedrali", "Antik Serdika ve Largo", "Vrana Parkı"],
  "novi-sad": ["Kovilj Manastırı ve Kovilj-Petrovaradin Sulak Alanı", "Petrovaradin Kalesi", "Sremski Karlovci Tarihî Merkezi"],
  budapest: ["Parlamento ve Tuna Kıyısı", "Buda Kalesi ve Balıkçı Tabyası", "Kahramanlar Meydanı ve Széchenyi Çevresi"],
  krakow: ["Wawel Tepesi", "Ana Pazar Meydanı ve Kumaş Pazarı", "Kazimierz"],
  warsaw: ["Wilanów Sarayı", "Łazienki Kraliyet Parkı", "Eski Şehir ve Kraliyet Yolu"],
  riga: ["Vecrīga / Eski Riga", "Art Nouveau Bölgesi", "Riga Merkez Pazarı"],
};

const projectRoot = fileURLToPath(new URL("..", import.meta.url));
const galleryManifest = JSON.parse(readFileSync(new URL("../public/assets/gallery/manifest.json", import.meta.url), "utf8"));
const manifestByURL = new Map(galleryManifest.map((item) => [item.file, item]));
const freshnessWindow = {
  startsAt: Date.parse("2026-07-01T00:00:00Z"),
  endsBefore: Date.parse("2026-08-01T00:00:00Z"),
};

function haversineKm(from, to) {
  const radians = (value) => (value * Math.PI) / 180;
  const latitudeDelta = radians(to.latitude - from.latitude);
  const longitudeDelta = radians(to.longitude - from.longitude);
  const a = Math.sin(latitudeDelta / 2) ** 2
    + Math.cos(radians(from.latitude)) * Math.cos(radians(to.latitude))
    * Math.sin(longitudeDelta / 2) ** 2;
  return 6_371.0088 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function assertProvenance(item) {
  assert.ok(item.source.name?.trim(), `${item.name}: non-empty source name required`);
  assert.match(item.source.url, /^https:\/\//, `${item.name}: HTTPS source required`);

  const verifiedAt = Date.parse(item.verifiedAt);
  assert.ok(Number.isFinite(verifiedAt), `${item.name}: verifiedAt must be a real ISO date`);
  assert.match(item.verifiedAt, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/, `${item.name}: verifiedAt must be an ISO-8601 UTC timestamp`);
  assert.ok(
    verifiedAt >= freshnessWindow.startsAt && verifiedAt < freshnessWindow.endsBefore,
    `${item.name}: verifiedAt must be within the July 2026 research window`,
  );
}

function assertMedia(item, kind) {
  assert.ok(item.media.credit && item.media.license && item.media.url, `${item.name}: complete media attribution required`);
  assert.match(item.media.source.url, /^https:\/\/commons\.wikimedia\.org\/wiki\/File:/, `${item.name}: direct Commons license page required`);

  if (kind === "camp") {
    assert.equal(item.media.role, "nearbyDestination", `${item.name}: camp media must be labelled as a nearby-destination image`);
    assert.equal(item.media.depictsCampground, false, `${item.name}: representative image must not claim to depict the campground`);
    assert.match(item.media.alt, /kamp alanını göstermez/i, `${item.name}: Turkish alt text must disclose that the image does not show the campground`);
    assert.match(item.media.disclosure, /temsili.*kamp alanını göstermez/i, `${item.name}: Turkish representative-image disclosure required`);
  }
}

function findCamp(bundle, destinationKey, campID) {
  const camp = bundle.destinations[destinationKey].camps.find((item) => item.id === campID);
  assert.ok(camp, `${destinationKey}/${campID}: critical camp missing`);
  return camp;
}

function assertCriticalRestrictions(bundle) {
  const wok = findCamp(bundle, "warsaw", "camping-motel-wok");
  assert.equal(wok.maximumLengthMeters, 8, "Camping Motel WOK: 8 m limit changed");
  assert.match(wok.warning, /8 metreden uzun.*kabul etmiyor/, "Camping Motel WOK: 8 m warning changed");

  const campingYachts = findCamp(bundle, "riga", "camping-yachts");
  assert.equal(campingYachts.maximumLengthMeters, 7.5, "Camping & Yachts: 7.5 m limit changed");
  assert.match(campingYachts.warning, /7,5 metreden uzun.*önceden teyit/, "Camping & Yachts: 7.5 m warning changed");

  const aveNatura = findCamp(bundle, "budapest", "ave-natura-camping");
  assert.equal(aveNatura.maximumLengthMeters, 6, "Ave Natura Camping: 6 m hairpin limit changed");
  assert.match(aveNatura.warning, /6 metre.*keskin viraj/i, "Ave Natura Camping: 6 m hairpin warning changed");

  const clepardia = findCamp(bundle, "krakow", "camping-clepardia");
  assert.match(clepardia.openingPeriod, /09:00-21:00/, "Camping Clepardia: current reception hours changed");
  assert.match(clepardia.reservationMethod, /Haziran-ağustos.*sınırlı olabilir/i, "Camping Clepardia: summer pitch guidance changed");
  assert.match(clepardia.warning, /21:00.*iletişim/i, "Camping Clepardia: after-hours contact guidance changed");

  const rigaCity = findCamp(bundle, "riga", "riga-city-camping");
  assert.match(rigaCity.openingPeriod, /15 Mayıs-15 Eylül/, "Riga City Camping: published season changed");
  assert.match(rigaCity.warning, /15 Eylül.*kapalı/i, "Riga City Camping: seasonal warning changed");

  const farma47 = findCamp(bundle, "novi-sad", "auto-camp-farma-47");
  assert.equal(farma47.location.latitude, 45.3886068, "Auto Camp Farma 47: official embedded-map latitude changed");
  assert.equal(farma47.location.longitude, 19.8197356, "Auto Camp Farma 47: official embedded-map longitude changed");
  assert.equal(farma47.supportsCaravan, false, "Auto Camp Farma 47: unsupported caravan claim reintroduced");
  assert.equal(farma47.hasWater, null, "Auto Camp Farma 47: unsupported current water claim reintroduced");
  assert.equal(farma47.hasWastewaterDisposal, null, "Auto Camp Farma 47: unsupported current wastewater claim reintroduced");
}

for (const [key, destination] of Object.entries(data.destinations)) {
  assert.ok(destination.camps.length >= 2, `${key}: two camp alternatives required`);
  assert.ok(destination.attractions.length >= 3, `${key}: three attractions required`);
  assert.deepEqual(destination.camps.map((item) => item.name), expectedCamps[key], `${key}: approved camp set changed`);
  assert.deepEqual(destination.attractions.map((item) => item.name), expectedAttractions[key], `${key}: approved attraction set changed`);
  assert.equal(destination.policy.type, "city", `${key}: must use city distance policy`);
  assert.equal(destination.policy.maximumKm, 25, `${key}: city limit must remain 25 km`);

  for (const item of [...destination.camps, ...destination.attractions]) {
    assertProvenance(item);
    assertMedia(item, destination.camps.includes(item) ? "camp" : "attraction");
    assert.ok(item.recommendation.length >= 60, `${item.name}: useful Turkish recommendation required`);

    if (item.media.url.startsWith("/")) {
      assert.ok(existsSync(`${projectRoot}/public${item.media.url}`), `${item.name}: local media file missing`);
    }

    const manifestItem = manifestByURL.get(item.media.url);
    assert.ok(manifestItem, `${item.name}: media missing from gallery manifest`);
    assert.equal(manifestItem.credit, item.media.credit, `${item.name}: manifest credit mismatch`);
    assert.equal(manifestItem.license, item.media.license, `${item.name}: manifest license mismatch`);
    assert.equal(manifestItem.source.url, item.media.source.url, `${item.name}: manifest source mismatch`);
  }

  for (const camp of destination.camps) {
    const distanceKm = haversineKm(destination.cityCenter, camp.location);
    assert.ok(distanceKm <= destination.policy.maximumKm, `${key}/${camp.name}: ${distanceKm.toFixed(2)} km exceeds 25 km`);
    assert.match(camp.websiteURL, /^https:\/\//, `${camp.name}: official HTTPS website required`);
    assert.ok(camp.address && camp.recommendation && camp.reservationMethod, `${camp.name}: researched stay detail required`);
  }
}

assertCriticalRestrictions(data);

const negativeChecks = [
  ["invalid freshness date", (copy) => { copy.destinations.sofia.attractions[0].verifiedAt = "2026-07-99T00:00:00Z"; }, (copy) => assertProvenance(copy.destinations.sofia.attractions[0])],
  ["missing camp-media role", (copy) => { delete copy.destinations.sofia.camps[0].media.role; }, (copy) => assertMedia(copy.destinations.sofia.camps[0], "camp")],
  ["WOK length corruption", (copy) => { copy.destinations.warsaw.camps.find((item) => item.id === "camping-motel-wok").maximumLengthMeters = 9; }, assertCriticalRestrictions],
  ["Camping & Yachts warning deletion", (copy) => { delete copy.destinations.riga.camps.find((item) => item.id === "camping-yachts").warning; }, assertCriticalRestrictions],
  ["Ave Natura limit deletion", (copy) => { delete copy.destinations.budapest.camps.find((item) => item.id === "ave-natura-camping").maximumLengthMeters; }, assertCriticalRestrictions],
  ["Clepardia hours corruption", (copy) => { copy.destinations.krakow.camps.find((item) => item.id === "camping-clepardia").openingPeriod = "09:00-20:00"; }, assertCriticalRestrictions],
  ["Riga season deletion", (copy) => { delete copy.destinations.riga.camps.find((item) => item.id === "riga-city-camping").openingPeriod; }, assertCriticalRestrictions],
  ["Farma 47 caravan claim", (copy) => { copy.destinations["novi-sad"].camps.find((item) => item.id === "auto-camp-farma-47").supportsCaravan = true; }, assertCriticalRestrictions],
];

for (const [label, mutate, validate] of negativeChecks) {
  const copy = structuredClone(data);
  mutate(copy);
  assert.throws(() => validate(copy), `${label}: validator self-test must fail`);
}

console.log(`travel-content: ${expected.length} destinations, ${Object.values(data.destinations).reduce((sum, value) => sum + value.camps.length, 0)} camps, 18 attractions and ${negativeChecks.length} negative checks validated`);
