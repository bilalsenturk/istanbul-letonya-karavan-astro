# Kamp, Gezi, Profil ve Hazır İletişim Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Altı İstanbul–Riga geceleme durağına kaynaklı yakın kamp ve gezi içeriği eklemek; hesap geneli seyahat profilini konaklama formuna bağlamak; ETA'yı otomatik üretmek; WhatsApp, Mesajlar ve E-posta uygulamalarını hazır alıcı ve metinle açmak.

**Architecture:** Sürümlü bir JSON içerik paketi kamp ve gezi önerilerini taşır; saf Swift modelleri paketi doğrular, mesafe filtresini uygular ve gün ekranına sunar. Özel seyahat profili mevcut hesap kaydında saklanır ve `/api/v2/me` üzerinden okunup güncellenir. Saf ETA ve mesaj üreticileri rota türüne göre taslak oluşturur; SwiftUI yalnız sistem MessageUI bileşenlerini ve dış WhatsApp bağlantısını sunar.

**Tech Stack:** Swift 5.9, SwiftUI, MapKit, MessageUI, Astro 7 API routes, TypeScript, Vercel Private Blob, JSON içerik manifestleri, shell tabanlı Swift davranış kontrolleri.

## Global Constraints

- Şehir kampı hedef şehir merkezinden en fazla 25 km uzakta olabilir.
- Transit kamp planlanan rota geometrisinden en fazla 10 km sapabilir.
- Mevcut altı geceleme şehir durağı sayılır.
- Uçak ve yürüyüş rotalarında araç, karavan, toplam uzunluk ve elektrik cümleleri mesajdan çıkarılır.
- Profil, telefon, e-posta ve konaklama ayrıntıları herkese açık API'lere girmez.
- WhatsApp, Mesajlar ve E-posta gerçek konuşma geçmişi olarak gösterilmez.
- Kanal eylemi kullanıcı onayı olmadan mesaj göndermez.
- Kanal eylemi hazır metni panoya kopyalar.
- Mevcut kirli çalışma ağacındaki ilgisiz değişiklikler korunur.

---

### Task 1: Küratörlü Kamp ve Gezi İçerik Modeli

**Files:**
- Create: `ios/Karavan/TravelContent.swift`
- Create: `ios/Tests/travel-content-check.swift`
- Create: `ios/Tests/run-travel-content-check.sh`
- Modify: `ios/project.yml`

**Interfaces:**
- Produces: `TravelContentBundle`, `CuratedCamp`, `NearbyAttraction`, `TravelMedia`, `TravelSource`, `CampDistancePolicy`, `ContentFreshness`, `DestinationKey`.
- Produces: `TravelContentBundle.content(forDestination:)`, `CampDistancePolicy.accepts(candidate:destination:routeDistanceKm:)`.

- [ ] **Step 1: Write the failing content behavior check**

```swift
let sofia = GeoPoint(latitude: 42.6977, longitude: 23.3219)
let nearby = GeoPoint(latitude: 42.7236, longitude: 23.2679)
let far = GeoPoint(latitude: 42.10, longitude: 24.30)
check("şehir kampı 25 km içinde kabul edilir",
      CampDistancePolicy.city(maximumKm: 25).accepts(candidate: nearby, destination: sofia, routeDistanceKm: nil))
check("uzak şehir kampı reddedilir",
      !CampDistancePolicy.city(maximumKm: 25).accepts(candidate: far, destination: sofia, routeDistanceKm: nil))
check("transit kamp 10 km sapmada kabul edilir",
      CampDistancePolicy.transit(maximumDetourKm: 10).accepts(candidate: nearby, destination: sofia, routeDistanceKm: 9.8))
let iso = ISO8601DateFormatter()
let verified = iso.date(from: "2026-04-01T00:00:00Z")!
let day91 = iso.date(from: "2026-07-01T00:00:01Z")!
check("90 günü aşan kayıt teyit ister",
      ContentFreshness.requiresReverification(verifiedAt: verified, on: day91))
check("hedef Türkçe karakterlerden bağımsız çözülür",
      DestinationKey.resolve("Kraków") == "krakow")
```

- [ ] **Step 2: Run the check and verify RED**

Run: `./ios/Tests/run-travel-content-check.sh`

Expected: compilation fails because `TravelContentBundle` and `CampDistancePolicy` do not exist.

- [ ] **Step 3: Implement the pure content model**

```swift
struct GeoPoint: Codable, Hashable {
    let latitude: Double
    let longitude: Double
}

enum CampDistancePolicy: Equatable {
    case city(maximumKm: Double)
    case transit(maximumDetourKm: Double)

    func accepts(candidate: GeoPoint, destination: GeoPoint, routeDistanceKm: Double?) -> Bool {
        switch self {
        case .city(let maximum): candidate.distanceKm(to: destination) <= maximum
        case .transit(let maximum): routeDistanceKm.map { $0 <= maximum } ?? false
        }
    }
}

struct CuratedCamp: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let location: GeoPoint
    let address: String
    let phone: String?
    let email: String?
    let websiteURL: URL
    let supportsCaravan: Bool
    let hasElectricity: Bool?
    let maximumLengthMeters: Double?
    let recommendation: String
    let warning: String?
    let media: TravelMedia
    let source: TravelSource
    let verifiedAt: Date
}
```

Use the haversine formula for `distanceKm(to:)`. Decode dates with ISO 8601. Normalize destination keys with case and diacritic folding. Treat a record as stale when `calendar.dateComponents([.day], from: verifiedAt, to: now).day > 90`.

- [ ] **Step 4: Run the content checks and verify GREEN**

Run: `./ios/Tests/run-travel-content-check.sh`

Expected: every content, distance, freshness and destination matching check passes.

- [ ] **Step 5: Regenerate the Xcode project and commit the domain unit**

Run: `cd ios && xcodegen generate`

```bash
git add ios/Karavan/TravelContent.swift ios/Tests/travel-content-check.swift ios/Tests/run-travel-content-check.sh ios/project.yml ios/Kuzey.xcodeproj/project.pbxproj
git commit -m "feat: model curated travel content"
```

### Task 2: Araştırılmış İçerik Paketi ve Görsel Manifesti

**Files:**
- Create: `public/assets/travel-content.json`
- Create: `tools/check-travel-content.mjs`
- Modify: `public/assets/gallery/manifest.json`
- Modify: `ios/Karavan/Resources/trip.json`
- Modify: `src/data/tripData.json`
- Modify: `package.json`

**Interfaces:**
- Consumes: JSON shape produced by Task 1.
- Produces: `/assets/travel-content.json` with keys `sofia`, `novi-sad`, `budapest`, `krakow`, `warsaw`, `riga`.
- Produces: `npm run check:travel-content`.

- [ ] **Step 1: Write a failing package validator**

```js
import assert from 'node:assert/strict';
import data from '../public/assets/travel-content.json' with { type: 'json' };

const expected = ['sofia', 'novi-sad', 'budapest', 'krakow', 'warsaw', 'riga'];
assert.deepEqual(Object.keys(data.destinations).sort(), expected.sort());
for (const [key, destination] of Object.entries(data.destinations)) {
  assert.ok(destination.camps.length >= 2, `${key}: two camp alternatives required`);
  assert.ok(destination.attractions.length >= 3, `${key}: three attractions required`);
  for (const item of [...destination.camps, ...destination.attractions]) {
    assert.match(item.source.url, /^https:\/\//);
    assert.match(item.verifiedAt, /^2026-07-/);
    assert.ok(item.media.credit && item.media.license && item.media.url);
  }
}
```

- [ ] **Step 2: Run the validator and verify RED**

Run: `node tools/check-travel-content.mjs`

Expected: module loading fails because `travel-content.json` does not exist.

- [ ] **Step 3: Add the six-destination content package**

Populate the exact candidates approved in the design:

```json
{
  "version": 1,
  "generatedAt": "2026-07-27T00:00:00Z",
  "destinations": {
    "sofia": { "cityName": "Sofya", "policy": { "type": "city", "maximumKm": 25 }, "camps": [], "attractions": [] },
    "novi-sad": { "cityName": "Novi Sad", "policy": { "type": "city", "maximumKm": 25 }, "camps": [], "attractions": [] },
    "budapest": { "cityName": "Budapeşte", "policy": { "type": "city", "maximumKm": 25 }, "camps": [], "attractions": [] },
    "krakow": { "cityName": "Kraków", "policy": { "type": "city", "maximumKm": 25 }, "camps": [], "attractions": [] },
    "warsaw": { "cityName": "Varşova", "policy": { "type": "city", "maximumKm": 25 }, "camps": [], "attractions": [] },
    "riga": { "cityName": "Riga", "policy": { "type": "city", "maximumKm": 25 }, "camps": [], "attractions": [] }
  }
}
```

Use official coordinates and contact data from the sources named in the design. Add the approved camp pairs and three attractions per city. Add only images whose manifest entry includes a concrete credit and license. Store optimized WebP files under the existing `/assets/gallery/<city>/` hierarchy when the license permits local hosting; otherwise store the stable official image URL in the content package.

- [ ] **Step 4: Add cross-file and distance validation**

Extend `tools/check-travel-content.mjs` to calculate haversine distance from each city coordinate and assert `distanceKm <= 25`. Assert that every local media URL exists in `public/` and every media record has nonempty `credit`, `license`, and `source.url`. Assert that WOK contains the 8 m warning and Camping & Yachts contains the 7.5 m warning.

- [ ] **Step 5: Run data checks and verify GREEN**

Run: `npm run check:travel-content && npm run check`

Expected: the content validator reports six destinations and Astro type checks exit 0.

- [ ] **Step 6: Commit the researched content unit**

```bash
git add public/assets/travel-content.json public/assets/gallery/manifest.json tools/check-travel-content.mjs package.json ios/Karavan/Resources/trip.json src/data/tripData.json
git commit -m "content: add nearby camps and destination guides"
```

### Task 3: Hesap Geneli Seyahat Profili API'si

**Files:**
- Modify: `src/accounts/accountRepository.ts`
- Modify: `src/accounts/api.ts`
- Modify: `src/pages/api/v2/me.ts`
- Modify: `tools/check-account-auth.mjs`
- Modify: `ios/Karavan/Accounts/AccountModels.swift`
- Modify: `ios/Karavan/Accounts/AccountAPI.swift`
- Modify: `ios/Karavan/Accounts/AccountSessionStore.swift`
- Modify: `ios/Tests/account-domain-check.swift`

**Interfaces:**
- Produces TypeScript: `TravelProfileRecord`, `normalizeTravelProfile(input, fallback?)`, `updateTravelProfile(userId, profile)`.
- Produces API: `PATCH /api/v2/me` body `{ travelProfile: TravelProfileRecord }` and response `{ user }`.
- Produces Swift: `AccountTravelProfile`, `AccountAPI.updateTravelProfile(_:accessToken:)`, `AccountSessionStore.saveTravelProfile(_:)`.

- [ ] **Step 1: Add failing repository validation checks**

```js
const profile = normalizeTravelProfile({
  contactName: ' Bilal Şentürk ', contactEmail: ' BILAL@EXAMPLE.COM ',
  adults: 2, children: 0, vehicleDescription: 'VW Passat + Adria',
  totalLengthMeters: 10.8, needsElectricity: true, hasPet: false,
  additionalNeeds: '', preferredLanguage: 'english', updatedAt: now,
});
assert.equal(profile.contactName, 'Bilal Şentürk');
assert.equal(profile.contactEmail, 'bilal@example.com');
assert.throws(() => normalizeTravelProfile({ ...profile, adults: 99 }), /invalid_travel_profile/);
```

- [ ] **Step 2: Run account checks and verify RED**

Run: `npm run check:account-auth && ./ios/Tests/run-account-check.sh`

Expected: JavaScript import or Swift decoding fails because travel profile interfaces are absent.

- [ ] **Step 3: Extend the private account record**

```ts
export type TravelProfileRecord = {
  contactName: string;
  contactEmail: string | null;
  adults: number;
  children: number;
  vehicleDescription: string;
  totalLengthMeters: number | null;
  needsElectricity: boolean;
  hasPet: boolean;
  additionalNeeds: string;
  preferredLanguage: 'english' | 'turkish';
  updatedAt: string;
};

export type AccountRecord = {
  id: string;
  email: string | null;
  displayName: string | null;
  globalRole: GlobalRole;
  createdAt: string;
  updatedAt: string;
  travelProfile: TravelProfileRecord;
};
```

Default `contactName` and `contactEmail` from the Apple account during `upsertAppleAccount`. Preserve an existing profile. Validate string lengths, email syntax, adults `1...12`, children `0...12`, and total length `1...30`. Write the whole account record through `writePrivateJSON`.

- [ ] **Step 4: Add authenticated GET/PATCH behavior**

`GET /api/v2/me` continues to return `user` and `trips`; `user.travelProfile` contains the private profile. `PATCH /api/v2/me` authenticates, reads `{ travelProfile }`, validates it, forces `updatedAt` to server time, writes the account, and returns `{ user }`. No public endpoint imports or serializes `TravelProfileRecord`.

- [ ] **Step 5: Add Swift account profile models and requests**

```swift
struct AccountTravelProfile: Codable, Equatable {
    var contactName: String
    var contactEmail: String?
    var adults: Int
    var children: Int
    var vehicleDescription: String
    var totalLengthMeters: Double?
    var needsElectricity: Bool
    var hasPet: Bool
    var additionalNeeds: String
    var preferredLanguage: StayMessageLanguage
    var updatedAt: String
}
```

Decode the profile with backward-compatible defaults when old preview fixtures omit it. Update `AccountSessionStore.user` after a successful PATCH.

- [ ] **Step 6: Run private-profile checks and verify GREEN**

Run: `npm run check:account-auth && npm run check:accounts && ./ios/Tests/run-account-check.sh`

Expected: validation, private serialization, Swift decoding and update request checks pass.

- [ ] **Step 7: Commit the profile contract**

```bash
git add src/accounts/accountRepository.ts src/accounts/api.ts src/pages/api/v2/me.ts tools/check-account-auth.mjs ios/Karavan/Accounts/AccountModels.swift ios/Karavan/Accounts/AccountAPI.swift ios/Karavan/Accounts/AccountSessionStore.swift ios/Tests/account-domain-check.swift
git commit -m "feat: sync account travel profile"
```

### Task 4: Profil Ekranı ve Yerel Geçiş

**Files:**
- Modify: `ios/Karavan/StayContactProfileStore.swift`
- Create: `ios/Karavan/Views/Accounts/TravelProfileView.swift`
- Modify: `ios/Karavan/Views/Trips/AccountMenuView.swift`
- Modify: `ios/Karavan/Views/Trips/JourneyMenuView.swift`
- Modify: `ios/Karavan/Accounts/AccountPreviewFixtures.swift`
- Modify: `ios/project.yml`

**Interfaces:**
- Consumes: `AccountTravelProfile` and `AccountSessionStore.saveTravelProfile(_:)` from Task 3.
- Produces: `StayContactProfileStore.bind(account:vehicleSeed:)`, `TravelProfileView`.

- [ ] **Step 1: Add a failing migration check to `arrival-target-check.swift`**

```swift
let seeded = TravelProfileSeed.make(
    accountName: "Bilal Şentürk",
    accountEmail: "bilal@example.com",
    vehicleDescription: "VW Passat 2016 + Adria"
)
check("Apple hesap adı profile gelir", seeded.contactName == "Bilal Şentürk")
check("mevcut rota aracı boş profili doldurur", seeded.vehicleDescription.contains("Adria"))
var oldLocal = seeded
oldLocal.updatedAt = "2026-07-26T08:00:00Z"
var newRemote = seeded
newRemote.updatedAt = "2026-07-27T08:00:00Z"
check("sunucu profili daha yeniyse kazanır",
      TravelProfileMerge.resolve(local: oldLocal, remote: newRemote) == newRemote)
```

- [ ] **Step 2: Run and verify RED**

Run: `./ios/Tests/run-arrival-target-check.sh`

Expected: compilation fails because `TravelProfileSeed` and `TravelProfileMerge` do not exist.

- [ ] **Step 3: Implement deterministic seed and merge behavior**

Keep the existing UserDefaults key as a migration source. On first signed-in load, compare local and server `updatedAt`; persist the newer value. Seed empty contact fields from `AccountUser`, and seed an empty vehicle description from the Kuzey trip vehicle string only. Never overwrite a nonempty user value.

- [ ] **Step 4: Build the account profile form**

Use a `Form` with sections `İletişim`, `Yolculuk`, and `Tercihler`. Include contact name/email, adult/child steppers, vehicle description, total length, electricity, pet, additional needs and language. Save locally first, then call `saveTravelProfile`. Keep the form open and show a retryable inline error when sync fails.

- [ ] **Step 5: Link the form from account and journey menus**

Add a `NavigationLink` labeled `Seyahat profili` with `person.text.rectangle`. Show a one-line summary such as `2 yetişkin · VW Passat + Adria` without exposing the e-mail address on the menu.

- [ ] **Step 6: Run checks and regenerate the project**

Run: `./ios/Tests/run-arrival-target-check.sh && cd ios && xcodegen generate`

Expected: seed and merge checks pass; `TravelProfileView.swift` appears in the Kuzey target sources.

- [ ] **Step 7: Commit the profile UI**

```bash
git add ios/Karavan/StayContactProfileStore.swift ios/Karavan/Views/Accounts/TravelProfileView.swift ios/Karavan/Views/Trips/AccountMenuView.swift ios/Karavan/Views/Trips/JourneyMenuView.swift ios/Karavan/Accounts/AccountPreviewFixtures.swift ios/project.yml ios/Kuzey.xcodeproj/project.pbxproj ios/Tests/arrival-target-check.swift
git commit -m "feat: add shared travel profile screen"
```

### Task 5: ETA, Konaklama Varsayılanları ve Ulaşım-Duyarlı Mesaj

**Files:**
- Modify: `ios/Karavan/ArrivalTarget.swift`
- Modify: `ios/Karavan/Models.swift`
- Modify: `ios/Karavan/TripPlanner.swift`
- Modify: `ios/Karavan/Views/DayDetailView.swift`
- Modify: `ios/Karavan/Views/ArrivalTargetEditorView.swift`
- Modify: `ios/Tests/arrival-target-check.swift`
- Modify: `ios/Karavan/Resources/trip.json`
- Modify: `src/data/tripData.json`

**Interfaces:**
- Produces: `StayETAInput`, `StayETAWindow`, `StayETACalculator.calculate(_:)`.
- Changes: `StayMessageComposer.compose(target:stay:profile:transportMode:camp:)`.
- Changes: `StayDetails` gains `estimatedArrivalMode` and `estimatedArrivalWindow` with backward-compatible decoding.

- [ ] **Step 1: Add failing ETA and transport checks**

```swift
let departure = calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 8))!
let eta = StayETACalculator.calculate(.init(
    departure: departure, drivingSeconds: 8 * 3600,
    waypointMinutes: 45, borderBufferMinutes: 90
))
check("ETA yarım saatlik pencere üretir", eta.text == "17:00–18:00")
let flight = StayMessageComposer.compose(
    target: target, stay: stay, profile: profile, transportMode: .flight, camp: nil
)
check("uçak mesajında araç yok", !flight.body.contains("Passat") && !flight.body.contains("electricity"))
let car = StayMessageComposer.compose(
    target: target, stay: stay, profile: profile, transportMode: .automobile,
    camp: .init(maximumLengthMeters: 8)
)
check("uzunluk sınırı teyit edilir", car.body.contains("10.8 m") && car.body.contains("8.0 m"))
```

- [ ] **Step 2: Run and verify RED**

Run: `./ios/Tests/run-arrival-target-check.sh`

Expected: compilation fails on the new ETA and compose signatures.

- [ ] **Step 3: Implement ETA and backward-compatible stay decoding**

Calculate the center as departure plus driving, waypoint and border seconds. Round the center down and up to the neighboring half-hour bounds; widen to a one-hour window. Format in the destination day's calendar and time zone. Preserve a manual window until the user selects `Otomatik kullan`.

- [ ] **Step 4: Make message generation transport-aware**

Move vehicle, total length and electricity lines behind `transportMode == .automobile`. Keep guest, pet and additional-needs lines for every transport mode. Add a specific length-confirmation line when `profile.totalLengthMeters > camp.maximumLengthMeters`.

- [ ] **Step 5: Bind defaults in day detail and editor**

`DayDetailView.defaultStay` supplies check-in/out and automatic ETA. Add `estimatedMinutes` to `DayWaypoint` and `borderBufferMinutes` to `DayPlan`, both with backward-compatible optional decoding. Use `realLeg.time`, `day.waypoints.compactMap(\.estimatedMinutes).reduce(0, +)`, and the explicit border buffer. Pass `workspace.selectedTrip?.transportMode ?? .automobile` and the account profile to the editor. Remove the duplicate embedded profile fields from `ArrivalTargetEditorView`; replace them with a navigation link to `TravelProfileView`.

- [ ] **Step 6: Run ETA, planner and account checks**

Run: `./ios/Tests/run-arrival-target-check.sh && ./ios/Tests/run-planner-check.sh && ./ios/Tests/run-account-check.sh`

Expected: ETA, transport, old JSON decoding and account decoding checks pass.

- [ ] **Step 7: Commit ETA and message behavior**

```bash
git add ios/Karavan/ArrivalTarget.swift ios/Karavan/Models.swift ios/Karavan/TripPlanner.swift ios/Karavan/Views/DayDetailView.swift ios/Karavan/Views/ArrivalTargetEditorView.swift ios/Tests/arrival-target-check.swift ios/Karavan/Resources/trip.json src/data/tripData.json
git commit -m "feat: automate stay details and arrival windows"
```

### Task 6: Sistem Mesaj Oluşturucuları ve Otomatik Kopyalama

**Files:**
- Create: `ios/Karavan/Views/StayContactComposer.swift`
- Modify: `ios/Karavan/Views/ArrivalTargetEditorView.swift`
- Modify: `ios/Karavan/ArrivalTarget.swift`
- Modify: `ios/Tests/arrival-target-check.swift`
- Modify: `ios/project.yml`

**Interfaces:**
- Produces: `MailComposerSheet`, `MessageComposerSheet`, `StayContactAction`, `StayContactAvailability`.
- Produces: `StayContactAction.prepare(message:target:) -> PreparedContactAction` for pure tests.

- [ ] **Step 1: Add failing preparation checks**

```swift
let mail = StayContactAction.email.prepare(message: message, target: target)
check("mail alıcı konu ve gövde taşır",
      mail.recipient == "hello@example.com" && mail.subject == message.subject && mail.body == message.body)
let sms = StayContactAction.messages.prepare(message: message, target: target)
check("mesaj telefon ve gövde taşır", sms.recipient == target.phone && sms.body == message.body)
check("her kanal panoya aynı gövdeyi verir", mail.clipboardText == message.body && sms.clipboardText == message.body)
```

- [ ] **Step 2: Run and verify RED**

Run: `./ios/Tests/run-arrival-target-check.sh`

Expected: compilation fails because `StayContactAction` does not exist.

- [ ] **Step 3: Implement pure action preparation and MessageUI wrappers**

`MessageComposerSheet` wraps `MFMessageComposeViewController`, sets `recipients` and `body`, and returns `.sent`, `.cancelled`, or `.failed`. `MailComposerSheet` wraps `MFMailComposeViewController`, sets recipient, subject and body, and leaves the system `From` selector available. Use `canSendText()` and `canSendMail()` before presentation.

- [ ] **Step 4: Wire WhatsApp, Messages and E-mail buttons**

Before opening any channel, set `UIPasteboard.general.string = message.body` and show a two-second `Mesaj kopyalandı` confirmation. WhatsApp uses the existing `wa.me` builder. If a system composer is unavailable, keep the copy confirmation and show `Mesaj hazır; uygulama kullanılamadığı için panoya kopyalandı.`

- [ ] **Step 5: Keep communication state honest**

After a MessageUI `.sent` result, ask `Durumu “Yanıt bekleniyor” yap?`. After opening WhatsApp, present the same confirmation when the user returns. Never render a conversation list, delivery tick or incoming message.

- [ ] **Step 6: Run checks and regenerate Xcode project**

Run: `./ios/Tests/run-arrival-target-check.sh && cd ios && xcodegen generate`

Expected: pure preparation checks pass and `StayContactComposer.swift` is compiled in the app target.

- [ ] **Step 7: Commit contact composers**

```bash
git add ios/Karavan/Views/StayContactComposer.swift ios/Karavan/Views/ArrivalTargetEditorView.swift ios/Karavan/ArrivalTarget.swift ios/Tests/arrival-target-check.swift ios/project.yml ios/Kuzey.xcodeproj/project.pbxproj
git commit -m "feat: open prepared stay messages in system apps"
```

### Task 7: Gün Ayrıntısında Kamp ve Gezi Deneyimi

**Files:**
- Create: `ios/Karavan/TravelContentStore.swift`
- Create: `ios/Karavan/Views/NearbyTravelSections.swift`
- Create: `ios/Tests/travel-content-store-check.swift`
- Create: `ios/Tests/run-travel-content-store-check.sh`
- Modify: `ios/Karavan/Views/DayDetailView.swift`
- Modify: `ios/Karavan/KaravanApp.swift`
- Modify: `ios/Karavan/Views/CampImage.swift`
- Modify: `ios/project.yml`

**Interfaces:**
- Consumes: content types from Task 1 and `/assets/travel-content.json` from Task 2.
- Produces: `TravelContentStore.load()`, `TravelContentStore.content(for:)`, `NearbyCampSection`, `NearbyAttractionSection`.

- [ ] **Step 1: Add a failing store fallback check**

Create `ios/Tests/travel-content-store-check.swift` with a URL protocol fixture. Assert that a successful remote bundle replaces the embedded bundle; a network failure preserves the last valid bundle; invalid JSON never clears valid content.

- [ ] **Step 2: Run and verify RED**

Run: `./ios/Tests/run-travel-content-store-check.sh`

Expected: compilation fails because `TravelContentStore` does not exist.

- [ ] **Step 3: Implement remote, cached and embedded loading**

Load `Config.imageBaseURL + /assets/travel-content.json` with a 12-second timeout and URL cache policy. Persist the last valid JSON under Application Support. Fall back in this order: remote, disk cache, embedded `travel-content.json`. Publish only fully decoded bundles.

- [ ] **Step 4: Build reusable camp and attraction sections**

Camp cards show image, name, driving distance, electricity, caravan support, recommendation and warning. Buttons: `Haritada Aç`, `İletişim`, `Bu kampı seç`. Attraction cards show image, category, camp distance, visit duration and `Yol Tarifi`. Add visible source/credit disclosure on the detail sheet.

- [ ] **Step 5: Insert the sections into the approved day order**

In `DayDetailView`, render: day facts, main arrival target, communication state, nearby camps, nearby attractions, waypoints, subplans. Activate the currently unused `waypointsSection` and remove dead duplicate helper code. Keep `Buraya git` as the only primary action.

- [ ] **Step 6: Verify interactions and accessibility in Simulator**

Start the local server in background mode:

Run: `npx astro dev --background`

Build and run the iOS app, then inspect all six days. Verify small iPhone and iPad widths, Dynamic Type, VoiceOver labels, offline image placeholders, alternative selection, Maps opening, profile navigation and contact composer presentation. Stop the server with `npx astro dev stop`.

- [ ] **Step 7: Run the full verification suite**

Run:

```bash
npm run check:travel-content
npm run check:accounts
npm run check:account-auth
npm run check:trip-api
npm run check:web-sync
npm run check
npm run lint
./ios/Tests/run-arrival-target-check.sh
./ios/Tests/run-travel-content-check.sh
./ios/Tests/run-travel-content-store-check.sh
./ios/Tests/run-planner-check.sh
./ios/Tests/run-account-check.sh
xcodebuild -project ios/Kuzey.xcodeproj -scheme Kuzey -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Expected: every command exits 0; Xcode reports `BUILD SUCCEEDED`.

- [ ] **Step 8: Commit the finished experience**

```bash
git add ios/Karavan/TravelContentStore.swift ios/Karavan/Views/NearbyTravelSections.swift ios/Karavan/Views/DayDetailView.swift ios/Karavan/KaravanApp.swift ios/Karavan/Views/CampImage.swift ios/Tests/travel-content-store-check.swift ios/Tests/run-travel-content-store-check.sh ios/project.yml ios/Kuzey.xcodeproj/project.pbxproj
git commit -m "feat: show nearby stays and destination guides"
```
