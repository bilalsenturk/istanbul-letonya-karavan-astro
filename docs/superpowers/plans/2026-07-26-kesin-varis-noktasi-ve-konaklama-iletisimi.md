# Kesin Varış Noktası ve Konaklama İletişimi Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Plan günlerindeki şehir hedefini gerçek kamp/otel/adres hedefinden ayırmak; Apple Maps seçimi, güvenli iletişim bilgileri, hazır WhatsApp/e-posta mesajları ve kesin hedefe bağlı navigasyon yaşam döngüsü eklemek.

**Architecture:** Saf Swift modelleri hedef, konaklama ve mesaj üretimini taşır. MapKit katmanı `MKMapItem` verisini yapılandırılmış hedefe dönüştürür; özel iletişim alanları oturum gerektiren `/api/v2` rota durağında saklanır, herkese açık plan yalnız şehir ve güvenli hedef özetini alır. `RouteSession` etap kimliğiyle birlikte hedef kimliği/koordinatını doğrular ve bütün anons/varış davranışı bu oturuma bağlanır.

**Tech Stack:** Swift 6, SwiftUI, MapKit, CoreLocation, Astro 7 API routes, TypeScript, Vercel Private Blob, shell tabanlı Swift davranış kontrolleri, Xcode Simulator.

## Global Constraints

- Dinlenme günü dışındaki etap kesin hedef olmadan başlatılamaz.
- Şehir merkezi hiçbir zaman sessiz navigasyon varsayımı olmaz.
- Navigasyon güncel cihaz GPS konumundan kesin hedef koordinatına açılır.
- MapKit e-posta veya WhatsApp sağlamıyorsa değer tahmin edilmez.
- Telefon, e-posta, rezervasyon ve iletişim profili herkese açık API yanıtına yazılmaz.
- Mesaj kullanıcı onayı olmadan gönderilmez; varsayılan dil İngilizcedir ve metin düzenlenebilir.
- Mevcut kirli çalışma ağacındaki ilgisiz değişiklikler geri alınmaz.

---

### Task 1: Saf Hedef, Konaklama ve Mesaj Modelleri

**Files:**
- Create: `ios/Karavan/ArrivalTarget.swift`
- Create: `ios/Tests/arrival-target-check.swift`
- Create: `ios/Tests/run-arrival-target-check.sh`
- Modify: `ios/Karavan/TripPlanner.swift`
- Modify: `ios/project.yml`

**Interfaces:**
- Produces: `ArrivalTarget`, `ArrivalTargetKind`, `StayDetails`, `StayContactProfile`, `StayMessage`, `StayMessageComposer.compose(target:stay:profile:)`, `ContactLinkBuilder.whatsAppURL(phone:message:)`, `ContactLinkBuilder.emailURL(email:subject:body:)`, `ArrivalTargetRequirement.canStart(isRestDay:target:)`.
- Produces: `DayEdit.arrivalTarget`, `DayEdit.stayDetails`, `EffectiveDay.arrivalTarget`, `EffectiveDay.stayDetails`.

- [ ] **Step 1: Write the failing behavior check**

```swift
let target = ArrivalTarget(id: "campuccino", name: "Camping Campuccino", kind: .campground,
    latitude: 42.66, longitude: 23.28, formattedAddress: "Sofia, Bulgaria",
    phone: "+359 88 123 4567", whatsAppPhone: nil, email: "hello@example.com", websiteURL: nil)
check("hedef olmadan etap başlamaz", !ArrivalTargetRequirement.canStart(isRestDay: false, target: nil))
check("koordinatlı hedefle etap başlar", ArrivalTargetRequirement.canStart(isRestDay: false, target: target))
let message = StayMessageComposer.compose(target: target, stay: StayDetails(checkIn: checkIn, checkOut: checkOut), profile: profile)
check("mesaj hedef ve tarih içerir", message.body.contains("Camping Campuccino") && message.body.contains("3 August"))
check("WhatsApp E.164 bağlantısı üretir", ContactLinkBuilder.whatsAppURL(phone: target.phone, message: message.body)?.absoluteString.contains("wa.me/359881234567") == true)
```

- [ ] **Step 2: Run the check and verify RED**

Run: `./ios/Tests/run-arrival-target-check.sh`

Expected: compilation fails because `ArrivalTarget` and message interfaces do not exist.

- [ ] **Step 3: Implement minimal pure models**

```swift
struct ArrivalTarget: Codable, Equatable, Identifiable {
    let id: String
    var mapItemIdentifier: String?
    var name: String
    var kind: ArrivalTargetKind
    var latitude: Double
    var longitude: Double
    var formattedAddress: String
    var phone: String?
    var whatsAppPhone: String?
    var email: String?
    var websiteURL: URL?
    var source: ArrivalTargetSource = .appleMaps
    var updatedAt: Date = Date()
    var hasValidCoordinate: Bool { latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180 }
}
```

Implement deterministic English date formatting with `en_GB` and `Europe/Istanbul`, E.164 normalization that strips punctuation and preserves/inserts `+`, URL encoding through `URLComponents`, and nil-returning invalid phone/email paths. Add optional target/stay properties to `DayEdit`; preserve backward Codable compatibility.

- [ ] **Step 4: Run RED-to-GREEN checks**

Run: `./ios/Tests/run-arrival-target-check.sh && ./ios/Tests/run-planner-check.sh`

Expected: both scripts exit 0 and legacy plan JSON still decodes.

- [ ] **Step 5: Commit the domain unit**

```bash
git add ios/Karavan/ArrivalTarget.swift ios/Karavan/TripPlanner.swift ios/Tests/arrival-target-check.swift ios/Tests/run-arrival-target-check.sh ios/project.yml
git commit -m "feat: model exact arrival targets"
```

### Task 2: Private API Contract for Arrival Targets

**Files:**
- Modify: `src/accounts/domain.ts`
- Modify: `src/accounts/tripRepository.ts`
- Modify: `ios/Karavan/Accounts/AccountModels.swift`
- Modify: `ios/Karavan/Accounts/AccountAPI.swift`
- Modify: `ios/Karavan/Accounts/AccountSessionStore.swift`
- Modify: `ios/Karavan/Routes/RouteDraft.swift`
- Modify: `tools/check-account-domain.mjs`
- Modify: `tools/check-trip-api.mjs`
- Modify: `ios/Tests/account-domain-check.swift`

**Interfaces:**
- Consumes: `ArrivalTarget`, `StayDetails` from Task 1.
- Produces: optional `arrivalTarget`, `stayDetails` and private `contact` fields on `RouteStopRecord`/`AccountRouteStop`; existing authenticated stop update endpoint persists them under revision control.

- [ ] **Step 1: Add failing server and Swift contract tests**

```ts
const target = {
  id: 'campuccino', name: 'Camping Campuccino', kind: 'campground',
  latitude: 42.66, longitude: 23.28, formattedAddress: 'Sofia, Bulgaria',
  phone: '+359881234567', email: 'hello@example.com'
};
const folded = foldTripEvents([createdEvent, stopAddedEvent({ ...stop, arrivalTarget: target })]);
assert.equal(folded.stops[0].arrivalTarget?.name, 'Camping Campuccino');
assert.throws(() => routeStopWithInvalidTarget(), /invalid_arrival_target/);
```

Add Swift JSON decoding assertions for a stop containing the same target and stay dates.

- [ ] **Step 2: Verify RED**

Run: `npm run check:accounts && npm run check:trip-api && ./ios/Tests/run-account-check.sh`

Expected: assertions or compilation fail because target fields are absent.

- [ ] **Step 3: Extend and validate the authenticated stop schema**

Add TypeScript `ArrivalTargetRecord` and `StayDetailsRecord`. Validate finite coordinates, enum kind, max string lengths, valid absolute `http/https` website URLs, optional phone/e-mail strings, and ISO date strings. Include fields in `optionalStopFields()` and `stopChanges()` so `stopAdded`, `stopUpdated`, and `stopsReplaced` behave consistently.

Extend Swift API models and request bodies with the same optional structures. Convert `RouteDraftStop` to and from these structures without dropping values during reordering or replacement.

- [ ] **Step 4: Verify GREEN and privacy boundary**

Run: `npm run check:accounts && npm run check:trip-api && ./ios/Tests/run-account-check.sh`

Expected: all commands pass; unauthenticated `/api/plan` shape contains no phone, e-mail, reservation reference, or contact profile field.

- [ ] **Step 5: Commit the API unit**

```bash
git add src/accounts/domain.ts src/accounts/tripRepository.ts ios/Karavan/Accounts/AccountModels.swift ios/Karavan/Accounts/AccountAPI.swift ios/Karavan/Accounts/AccountSessionStore.swift ios/Karavan/Routes/RouteDraft.swift tools/check-account-domain.mjs tools/check-trip-api.mjs ios/Tests/account-domain-check.swift
git commit -m "feat: persist private arrival targets"
```

### Task 3: Apple Maps Target Search and Result Mapping

**Files:**
- Create: `ios/Karavan/Routes/ArrivalPlaceSearchService.swift`
- Create: `ios/Karavan/Views/Trips/ArrivalTargetPickerView.swift`
- Modify: `ios/project.yml`

**Interfaces:**
- Consumes: `ArrivalTarget` from Task 1.
- Produces: `ArrivalPlaceSuggestion`, `ArrivalSearchCategory`, `ArrivalPlaceSearchService.update(region:)`, `search(category:region:)`, `resolve(_:) async throws -> ArrivalTarget`; `ArrivalTargetPickerView(cityName:cityCoordinate:selection:onSelect:)`.

- [ ] **Step 1: Add a failing mapper check to the Xcode test build**

Define a deterministic `ArrivalMapItemSnapshot` initializer and assert that address, phone, URL, category and coordinate survive conversion to `ArrivalTarget`. Assert missing e-mail/WhatsApp remain nil.

- [ ] **Step 2: Build and verify RED**

Run: `xcodebuild -project ios/Kuzey.xcodeproj -scheme Kuzey -sdk iphonesimulator -destination 'platform=iOS Simulator,id=687D33A5-A851-40B8-9979-743BD38156E5' build`

Expected: build fails because arrival search types are absent.

- [ ] **Step 3: Implement Apple Maps search**

Use `MKLocalSearchCompleter` with `.address` and `.pointOfInterest`, seed its region with the destination city's coordinate, and provide campground, hotel, caravan park, parking and address categories. Resolve the selected completion to `MKMapItem`; format the postal address from placemark fields and map only values Apple supplies.

Build a full-screen picker with a 180-point map preview, search field, horizontal icon categories, result list, selected-place preview and one `Bu Yeri Seç` action. Keep the map/list selection synchronized and retain the current target until confirmation.

- [ ] **Step 4: Verify GREEN**

Run: `xcodebuild -project ios/Kuzey.xcodeproj -scheme Kuzey -sdk iphonesimulator -destination 'platform=iOS Simulator,id=687D33A5-A851-40B8-9979-743BD38156E5' build`

Expected: build succeeds without new warnings from the arrival search files.

- [ ] **Step 5: Commit the MapKit unit**

```bash
git add ios/Karavan/Routes/ArrivalPlaceSearchService.swift ios/Karavan/Views/Trips/ArrivalTargetPickerView.swift ios/project.yml ios/Kuzey.xcodeproj/project.pbxproj
git commit -m "feat: add Apple Maps arrival picker"
```

### Task 4: Plan Card, Contact Editor and Message Actions

**Files:**
- Create: `ios/Karavan/Views/ArrivalTargetCard.swift`
- Create: `ios/Karavan/Views/ArrivalTargetEditorView.swift`
- Create: `ios/Karavan/StayContactProfileStore.swift`
- Modify: `ios/Karavan/Views/DayDetailView.swift`
- Modify: `ios/Karavan/Views/DayEditView.swift`
- Modify: `ios/Karavan/TripPlanStore.swift`
- Modify: `ios/Karavan/PlanPublisher.swift`
- Modify: `ios/project.yml`

**Interfaces:**
- Consumes: target/search/message interfaces from Tasks 1 and 3.
- Produces: a single plan hierarchy: city leg title, exact target card, contact actions, and target-required route state. `TripPlanStore.setArrivalTarget(_:stay:slug:)` atomically changes a day.

- [ ] **Step 1: Add failing plan behavior assertions**

Add assertions to `arrival-target-check.swift` that target replacement clears old target contact data, extra-day date changes alter freshly composed check-out text, and `PlanPublisher.publicDayPayload` exposes target name/address only when public sharing is enabled and never exposes phone/e-mail.

- [ ] **Step 2: Verify RED**

Run: `./ios/Tests/run-arrival-target-check.sh`

Expected: missing store/publisher helper assertions fail.

- [ ] **Step 3: Implement the plan UI and contact actions**

Replace the separate legacy `Kamp` card and free-text `Nereye`, `Kamp adı`, `Yer` controls. Show `İstanbul → Sofya` as context and `Varış yeri gerekli` or the selected target as the primary card. Open the MapKit picker centered on the matched city stop. After selection, show editable phone, WhatsApp and e-mail fields, reservation state, arrival time and message preview.

Use `openURL` for `tel:`, validated `wa.me`, `mailto:` and website actions. Add a copy button using `UIPasteboard`; never auto-send. Persist reusable traveler fields in a route-scoped Codable profile keyed by account trip id.

- [ ] **Step 4: Verify GREEN and regression checks**

Run: `./ios/Tests/run-arrival-target-check.sh && ./ios/Tests/run-planner-check.sh && xcodebuild -project ios/Kuzey.xcodeproj -scheme Kuzey -sdk iphonesimulator -destination 'platform=iOS Simulator,id=687D33A5-A851-40B8-9979-743BD38156E5' build`

Expected: scripts and build pass; no free-text destination/camp controls remain in `DayEditView`.

- [ ] **Step 5: Commit the plan UI unit**

```bash
git add ios/Karavan/Views/ArrivalTargetCard.swift ios/Karavan/Views/ArrivalTargetEditorView.swift ios/Karavan/StayContactProfileStore.swift ios/Karavan/Views/DayDetailView.swift ios/Karavan/Views/DayEditView.swift ios/Karavan/TripPlanStore.swift ios/Karavan/PlanPublisher.swift ios/project.yml ios/Kuzey.xcodeproj/project.pbxproj ios/Tests/arrival-target-check.swift
git commit -m "feat: add exact target planning flow"
```

### Task 5: Account Route Stop Integration

**Files:**
- Modify: `ios/Karavan/Views/Trips/StopEditorView.swift`
- Modify: `ios/Karavan/Views/Trips/AccountStopsView.swift`
- Modify: `ios/Karavan/Views/Trips/RouteBuilderView.swift`

**Interfaces:**
- Consumes: private `AccountRouteStop.arrivalTarget/stayDetails` from Task 2 and picker/editor from Tasks 3-4.
- Produces: standard routes and the selected Kuzey account route can choose/edit an exact target without changing the city waypoint.

- [ ] **Step 1: Add failing model round-trip assertions**

Extend `account-domain-check.swift` so replacing, reordering and API conversion preserve `arrivalTarget.id`, address and stay dates while city stop name/coordinate remain unchanged.

- [ ] **Step 2: Verify RED**

Run: `./ios/Tests/run-account-check.sh`

Expected: preservation assertions fail until editor conversion is wired.

- [ ] **Step 3: Integrate the exact-target editor**

In stop details, label the existing route point as `Etap şehri`; add a separate `Kesin varış noktası` row opening the arrival picker. Keep route-builder waypoints unchanged. Save through the authenticated stop update and refresh `TripWorkspaceStore` with the returned revision.

- [ ] **Step 4: Verify GREEN**

Run: `./ios/Tests/run-account-check.sh && npm run check:trip-api && xcodebuild -project ios/Kuzey.xcodeproj -scheme Kuzey -sdk iphonesimulator -destination 'platform=iOS Simulator,id=687D33A5-A851-40B8-9979-743BD38156E5' build`

Expected: all pass and account route target survives server round trip.

- [ ] **Step 5: Commit the account UI unit**

```bash
git add ios/Karavan/Views/Trips/StopEditorView.swift ios/Karavan/Views/Trips/AccountStopsView.swift ios/Karavan/Views/Trips/RouteBuilderView.swift ios/Tests/account-domain-check.swift
git commit -m "feat: edit exact targets on route stops"
```

### Task 6: Exact-Target Navigation Session and Arrival

**Files:**
- Modify: `ios/Karavan/LegLauncher.swift`
- Modify: `ios/Karavan/Navigation.swift`
- Modify: `ios/Karavan/LocationManager.swift`
- Modify: `ios/Karavan/RouteAnnouncementPolicy.swift`
- Modify: `ios/Tests/main.swift`

**Interfaces:**
- Consumes: `ArrivalTarget`, `ArrivalTargetRequirement` from Task 1.
- Produces: `RouteSession.start(stop:target:stops:)`, persisted `activeTargetId`, target coordinate/name, `finishIfArrived(location:)`, and `LegLauncher.start(stop:target:stops:nav:location:speedKmh:)`.

- [ ] **Step 1: Write failing route lifecycle assertions**

```swift
check("hedefsiz başlatma reddedilir", !RouteStartPolicy.canStart(isRestDay: false, target: nil, stepState: .available))
check("kilitli etap hedefli olsa da başlamaz", !RouteStartPolicy.canStart(isRestDay: false, target: target, stepState: .locked))
check("oturum hedef kimliği uyuşmadan anons yapmaz", !RouteAnnouncementPolicy.allowsRouteProgressAnnouncement(routeStarted: true, activeStopId: "sofia", activeTargetId: "old", nextStopId: "sofia", nextTargetId: "campuccino"))
```

- [ ] **Step 2: Verify RED**

Run: `./ios/Tests/run-planner-check.sh`

Expected: compile failure from the new target-aware interfaces.

- [ ] **Step 3: Implement target-bound session**

Persist target id/name/latitude/longitude alongside stop id and started time. On restore, clear sessions missing any required target value. Calculate `MKDirections` and open Apple Maps using the target coordinate/name. Require a fresh device location; if unavailable, keep the user on the plan screen and show `Konum alınıyor` rather than substituting a city origin.

Evaluate arrival using current GPS distance to the target with horizontal accuracy included; finish automatically only within 250 meters and accuracy at most 100 meters. Keep city geofences informational, but do not complete the active leg from a city-center region. Include target identity in progress/deviation policy checks.

- [ ] **Step 4: Verify GREEN**

Run: `./ios/Tests/run-planner-check.sh && xcodebuild -project ios/Kuzey.xcodeproj -scheme Kuzey -sdk iphonesimulator -destination 'platform=iOS Simulator,id=687D33A5-A851-40B8-9979-743BD38156E5' build`

Expected: tests and build pass; no route can start or announce with a missing/mismatched exact target.

- [ ] **Step 5: Commit the navigation unit**

```bash
git add ios/Karavan/LegLauncher.swift ios/Karavan/Navigation.swift ios/Karavan/LocationManager.swift ios/Karavan/RouteAnnouncementPolicy.swift ios/Tests/main.swift
git commit -m "fix: bind navigation to exact arrival target"
```

### Task 7: End-to-End Verification, Simulator Preview and API Deployment

**Files:**
- Modify only files required by failures discovered in this task.

**Interfaces:**
- Consumes: all prior tasks.
- Produces: built simulator app, visual evidence for target selection and plan card, deployed authenticated API schema.

- [ ] **Step 1: Run the complete automated suite**

Run: `./ios/Tests/run-arrival-target-check.sh && ./ios/Tests/run-planner-check.sh && ./ios/Tests/run-account-check.sh && npm run check:accounts && npm run check:account-auth && npm run check:trip-api && npm run check && npm run build`

Expected: every command exits 0.

- [ ] **Step 2: Build and install on the active simulator**

Run: `xcodegen generate --spec ios/project.yml && xcodebuild -project ios/Kuzey.xcodeproj -scheme Kuzey -sdk iphonesimulator -destination 'platform=iOS Simulator,id=687D33A5-A851-40B8-9979-743BD38156E5' -derivedDataPath /tmp/KuzeyDerived build && xcrun simctl install 687D33A5-A851-40B8-9979-743BD38156E5 /tmp/KuzeyDerived/Build/Products/Debug-iphonesimulator/Kuzey.app`

Expected: build and install succeed.

- [ ] **Step 3: Launch preview and inspect screenshots**

Launch with preview account/plan arguments, open the Sofya day, capture compact and regular screenshots, and verify: no text overlap; city and exact target are visually distinct; missing target disables navigation; picker results show address/contact availability; message preview fits; buttons have at least 44-point hit targets.

- [ ] **Step 4: Deploy API changes**

Run: `npx vercel deploy --prod`

Expected: production deployment succeeds and `/api/v2` authenticated trip checks pass against the deployed origin without exposing contact fields through `/api/plan`.

- [ ] **Step 5: Final regression and status review**

Run: `git status --short && git log --oneline -8`

Expected: only pre-existing unrelated work remains uncommitted; feature commits and verification results are visible.
