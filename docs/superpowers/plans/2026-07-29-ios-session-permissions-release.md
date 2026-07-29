# iOS Session, Permissions, and Release Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move every protected iOS call onto one refreshable Bearer session, publish Kuzey data only through trip-scoped v2 resources, remove launch-time permission prompts, polish the focused UX issues, and make build 17 the safe release baseline.

**Architecture:** `BearerSessionCoordinator` exclusively owns the token pair, Keychain rotation, Authorization header, refresh, and one retry. Account and published-state clients inject that transport; a credential-free outbox retains eligible Kuzey writes, while `TripPlanStore` handles the sole client-visible revision. Permission decisions remain pure and managers expose explicit platform actions.

**Tech Stack:** Swift 5.9, SwiftUI, Foundation `URLSession`, Security/Keychain, Core Location, UserNotifications, shell/Swift checks, XcodeGen, Xcode 26, TestFlight, Astro/Vercel.

## Global Constraints

- Backward compatibility and production-data migration are unnecessary; remove the shared-secret callers and ignore legacy outbox records.
- Treat build `17` as current; never revert it.
- Preserve the current visual language, Kuzey icon work, cinematic hero artifacts, and journal image pipeline.
- Publish only when the selected trip has `kind == .kuzey2026` and `features.publicTracking == true`; never publish Kuzey data under a standard trip ID.
- Persist only trip ID, resource path, and body in the outbox—never credentials, Authorization headers, or absolute URLs.
- Offline and `5xx` failures retain tokens and work; rejected refresh or retry `401` clears the session.
- Do not perform broad SwiftUI environment-object refactors without trace evidence.
- Do not deploy from a dirty or partially verified tree.
- Tests must compile or execute the production behavior they protect. Static source scans may supplement security/wiring checks, but they must not be the sole evidence for session refresh, publishing, permissions, navigation, or release mutation behavior.

---

### Task 1: Add the single-flight Bearer coordinator

**Files:**
- Create: `ios/Karavan/Accounts/BearerSessionCoordinator.swift`, `ios/Tests/bearer-session-check.swift`, `ios/Tests/run-bearer-session-check.sh`; modify: `ios/Karavan/Accounts/KeychainTokenStore.swift:4-14`.

**Interfaces:** Consumes `AccountTokens`, `AccountTokenStoring`, `Config.accountAPIBaseURL`; produces `AuthenticatedRequestSending`, `install(_:)`, `restore()`, `clear()`, `hasSession`, `onRevoked`.

- [ ] **Step 1: Write the failing transport check**

Use a custom `URLProtocol`: install `old-access/old-refresh`; return concurrent `401`s; return `new-access/new-refresh` once from `/auth/refresh`; accept only `Bearer new-access`. Assert one refresh, two successful retries, rotated Keychain tokens, one-retry limit, refresh-`401` revocation, and offline token preservation.

```swift
async let a = coordinator.data(path: "me", method: "GET", body: nil)
async let b = coordinator.data(path: "trips/kuzey-2026/live-location", method: "PUT", body: Data("{}".utf8))
_ = try await (a, b)
expect(MockURLProtocol.refreshCount == 1, "eşzamanlı 401 tek refresh kullanır")
expect(store.saved?.accessToken == "new-access", "dönen token çifti saklanır")
```

- [ ] **Step 2: Verify RED**

Run: `bash ios/Tests/run-bearer-session-check.sh`

Expected: FAIL because `BearerSessionCoordinator` is absent.

- [ ] **Step 3: Implement the exact transport surface**

```swift
@MainActor protocol AuthenticatedRequestSending: AnyObject {
    var hasSession: Bool { get }
    func data(path: String, method: String, body: Data?) async throws -> (Data, HTTPURLResponse)
}
@MainActor final class BearerSessionCoordinator: AuthenticatedRequestSending {
    static let shared = BearerSessionCoordinator()
    var onRevoked: (() -> Void)?
    func install(_ tokens: AccountTokens) throws
    @discardableResult func restore() -> Bool
    func clear()
    func data(path: String, method: String, body: Data?) async throws -> (Data, HTTPURLResponse)
}
```

Store one `Task<AccountTokens, Error>?`. Before refreshing, compare the rejected access token with the current token so late callers join/skip the completed rotation. Save rotation before retry. Clear and notify only on refresh `401` or retry `401`; preserve tokens on transport/`5xx` errors.

- [ ] **Step 4: Verify GREEN and commit**

Run: `bash ios/Tests/run-bearer-session-check.sh`

```bash
git add ios/Karavan/Accounts/BearerSessionCoordinator.swift ios/Karavan/Accounts/KeychainTokenStore.swift ios/Tests/bearer-session-check.swift ios/Tests/run-bearer-session-check.sh
git commit -m "feat(ios): add refreshable bearer transport"
```

### Task 2: Remove token parameters from account operations

**Files:**
- Modify: `ios/Karavan/Accounts/AccountAPI.swift:9-194`, `ios/Karavan/Accounts/AccountSessionStore.swift:7-205`, `ios/Karavan/StayContactProfileStore.swift:65-76`, `ios/Tests/arrival-target-check.swift:550-559`, `ios/Tests/bearer-session-check.swift`.

**Interfaces:** Consumes Task 1 transport; produces `me()`, `updateTravelProfile(_:)`, `logout()`, `createTrip(_:)`, `invite(tripId:revision:email:role:)`, `updateStop(tripId:revision:stop:)`, `addStop(tripId:revision:stop:)`, `updateTrip(tripId:revision:name:transportMode:)`, and `replaceStops(tripId:revision:stops:)`, all without token arguments.

- [ ] **Step 1: Add failing signature and session-generation tests**

```swift
let generation = UUID()
expect(TravelProfileSessionGuard.accepts(currentAccountID: "a", currentSessionID: generation,
    expectedAccountID: "a", expectedSessionID: generation), "refresh aynı oturumdur")
expect(!TravelProfileSessionGuard.accepts(currentAccountID: "b", currentSessionID: UUID(),
    expectedAccountID: "a", expectedSessionID: generation), "yeni oturum eski yanıtı reddeder")
```

Also reject any protected `AccountAPI` declaration containing `accessToken:`.

- [ ] **Step 2: Verify RED, implement, and verify GREEN**

Run before and after: `bash ios/Tests/run-bearer-session-check.sh && bash ios/Tests/run-arrival-target-check.sh && bash ios/Tests/run-account-check.sh`

Keep Apple sign-in public. Install sign-in tokens in the coordinator; restore tokens before `api.me()`; rely on automatic refresh. Replace token equality with `sessionID: UUID`, changed only at sign-in/restore/clear, so rotation cannot invalidate an in-flight profile response. `onRevoked` clears user/trips.

- [ ] **Step 3: Commit**

```bash
git add ios/Karavan/Accounts/AccountAPI.swift ios/Karavan/Accounts/AccountSessionStore.swift ios/Karavan/StayContactProfileStore.swift ios/Tests
git commit -m "refactor(ios): centralize authenticated account calls"
```

### Task 3: Add trip-scoped publishing and a credential-free outbox

**Files:**
- Create: `ios/Karavan/Accounts/PublishedTripClient.swift`, `ios/Tests/published-trip-check.swift`, `ios/Tests/run-published-trip-check.sh`.
- Modify: `ios/Karavan/PublishOutbox.swift:1-105`, `ios/Karavan/Config.swift:14-31,54-60`, `ios/Karavan/KaravanApp.swift:23-24,80-90,102-114,198-228`, `ios/Karavan/LocationManager.swift:346-423`, `ios/Karavan/PlanPublisher.swift:4-48`, `ios/Karavan/ExpenseStore.swift:195-223`, `ios/Karavan/Journal/JournalStore.swift:569-638`.

**Interfaces:** Consumes `PUT /api/v2/trips/:id/{live-location,expense-summary,published-plan,shared-journal}` with success `{ok:true,revision,updatedAt}`; produces `PublishedTripScope`, `PublishedTripResource`, `PublishedTripClient.put(scope:resource:body:)`, and outbox keys `tripId:resourcePath`.

- [ ] **Step 1: Write failing eligibility, persistence, and secret-removal tests**

```swift
expect(PublishedTripScope(trip: kuzey)?.tripID == "kuzey-2026", "public Kuzey yayınlanır")
expect(PublishedTripScope(trip: standard) == nil, "standart rota reddedilir")
outbox.enqueue(resource: .expenseSummary, body: Data("{\"totalEur\":12}".utf8))
expect(outbox.persistedKeys == ["kuzey-2026:expense-summary"], "anahtar trip kapsamlıdır")
expect(!outbox.persistedJSON.contains("Bearer"), "kimlik bilgisi diske yazılmaz")
```

The shell check rejects `livePostSecret`, `LIVE_POST_SECRET`, and `x-live-secret` anywhere under `ios/Karavan`.

- [ ] **Step 2: Verify RED and implement exact types**

Run: `bash ios/Tests/run-published-trip-check.sh`

```swift
enum PublishedTripResource: String, Codable {
    case liveLocation = "live-location", expenseSummary = "expense-summary"
    case publishedPlan = "published-plan", sharedJournal = "shared-journal"
}
struct PublishedTripScope: Equatable {
    let tripID: String
    init?(trip: AccountTrip?) {
        guard let trip, trip.kind == .kuzey2026, trip.features.publicTracking else { return nil }
        tripID = trip.id
    }
}
```

Persist `PendingPost { tripID, resourcePath, body }` only; discard undecodable legacy files. `setScope(nil)` pauses without deletion; nonnil scope drains matching trip records. Recompute scope on account/trip changes. Keep current bodies: Location payload; expense `{totalEur,count,byCategory,ts}`; Plan payload; Journal `{entries:[{id,text,createdAt,mood?,stopId?}]}`. Remove legacy URL helpers and secret.

- [ ] **Step 3: Verify GREEN and commit**

Run: `bash ios/Tests/run-published-trip-check.sh && ! rg -n 'livePostSecret|LIVE_POST_SECRET|x-live-secret' ios/Karavan`

```bash
git add ios/Karavan/Accounts/PublishedTripClient.swift ios/Karavan/PublishOutbox.swift ios/Karavan/Config.swift ios/Karavan/KaravanApp.swift ios/Karavan/LocationManager.swift ios/Karavan/PlanPublisher.swift ios/Karavan/ExpenseStore.swift ios/Karavan/Journal/JournalStore.swift ios/Tests/published-trip-check.swift ios/Tests/run-published-trip-check.sh
git commit -m "feat(ios): publish through trip scoped bearer routes"
```

### Task 4: Migrate plan edits to the visible revision contract

**Files:**
- Modify: `ios/Karavan/Accounts/PublishedTripClient.swift`, `ios/Karavan/TripPlanStore.swift:75-214`, `ios/Tests/trip-plan-store-check.swift`, `ios/Tests/run-trip-plan-store-check.sh`.

**Interfaces:** Consumes GET/successful PUT `{revision,departureAt,days,updatedAt}`, PUT `{baseRevision,departureAt,days}`, stale `409 {error:"revision_conflict",current:{revision,departureAt,days,updatedAt}}`; produces `RemotePlanEdits`, `getPlanEdits(scope:)`, `putPlanEdits(scope:baseRevision:edits:)`, and `PublishedTripClientError.revisionConflict(RemotePlanEdits)`.

- [ ] **Step 1: Write failing rebase tests and verify RED**

Test a follower preserving remote departure, a local day rebased over `409 current`, one retry using current revision, offline local retention, and zero requests for a standard trip.

```swift
let rebased = PlanEditMerge.rebase(local: local, base: base, remote: current, canMoveDeparture: false)
expect(rebased.departureAt == current.departureAt, "takipçi kalkışı korur")
expect(rebased.days["sofya"] == local.days["sofya"], "yerel gün yeniden bindirilir")
```

Run: `bash ios/Tests/run-trip-plan-store-check.sh`

Expected: FAIL because the store still uses `/api/edits` and no revision.

- [ ] **Step 2: Implement, verify GREEN, and commit**

Decode ISO-8601 with/without fractional seconds. Fetch, three-way merge, persist `syncBase`, PUT only on difference. On `409`, rebase once over `current`, retry with `current.revision`; on network failure keep local/base files for foreground retry. Remove plan edits from generic outbox and delete `Config.editsURL`.

Run: `bash ios/Tests/run-trip-plan-store-check.sh && bash ios/Tests/run-published-trip-check.sh`

```bash
git add ios/Karavan/Accounts/PublishedTripClient.swift ios/Karavan/TripPlanStore.swift ios/Tests/trip-plan-store-check.swift ios/Tests/run-trip-plan-store-check.sh
git commit -m "fix(ios): rebase plan edits on v2 revisions"
```

### Task 5: Replace launch prompts with contextual permission actions

**Files:**
- Create: `ios/Karavan/PermissionPolicy.swift`, `ios/Tests/permission-policy-check.swift`, `ios/Tests/run-permission-policy-check.sh`.
- Modify: `ios/Karavan/LocationManager.swift:8-130`, `ios/Karavan/Notifications.swift:8-42`, `ios/Karavan/KaravanApp.swift:102-164`, `ios/Karavan/Views/DashboardView.swift:13-18,28-64,95-115,167-183`, `ios/Karavan/Views/LiveLocationCard.swift:1-112`, `ios/Karavan/Views/MapScreen.swift:127-136`, `ios/Karavan/Views/Trips/PlacePickerView.swift:291-297`.

**Interfaces:**
- Produces: `LocationPermissionPolicy.primaryAction(for:)`, `showsBackgroundAction(for:)`, and explicit `requestWhenInUse()`, `requestAlways()`, `startIfAuthorized()`, `openSettings()`.

- [ ] **Step 1: Write failing pure-policy and wiring checks**

```swift
expect(LocationPermissionPolicy.primaryAction(for: .notDetermined) == .requestWhenInUse, "önce When In Use")
expect(LocationPermissionPolicy.showsBackgroundAction(for: .whenInUse), "Always ayrı eylemdir")
expect(LocationPermissionPolicy.primaryAction(for: .denied) == .openSettings, "ret Ayarlar'a gider")
```

Reject notification request in `startAppServices`, `loc.request()` in Dashboard/Map bootstrap, and Always request in the location delegate.

Run: `bash ios/Tests/run-permission-policy-check.sh`

Expected: FAIL on all three automatic prompts.

- [ ] **Step 2: Implement contextual actions**

Initialize status from `manager.authorizationStatus`; monitor stops only under `.authorizedAlways`; start foreground updates when authorized; never auto-escalate. Live card copy is “Kalan mesafe, hız ve sıradaki durağı konumuna göre hesapla.” with 44-point `Konumu Aç`; denied shows `Ayarları Aç`; When In Use shows `Arka planda varışları aç`. PlacePicker requests When In Use only from `Konumum`; Map only starts if authorized.

Expose notification status, refresh it on active scene, and add Dashboard primer “Kalkış, varış ve hava uyarılarını zamanında al.” Its tap requests access; denied opens Settings. Preserve the Latvian reminder action.

- [ ] **Step 3: Verify GREEN and commit**

Run: `bash ios/Tests/run-permission-policy-check.sh`

```bash
git add ios/Karavan/PermissionPolicy.swift ios/Karavan/LocationManager.swift ios/Karavan/Notifications.swift ios/Karavan/KaravanApp.swift ios/Karavan/Views/DashboardView.swift ios/Karavan/Views/LiveLocationCard.swift ios/Karavan/Views/MapScreen.swift ios/Karavan/Views/Trips/PlacePickerView.swift ios/Tests/permission-policy-check.swift ios/Tests/run-permission-policy-check.sh
git commit -m "feat(ios): request permissions in context"
```

### Task 6: Polish Journal, stop rendering, and navigation checks

**Files:**
- Modify: `ios/Karavan/Views/Journal/JournalView.swift:25-29,108-118`, `ios/Karavan/Views/Trips/AccountStopsView.swift:18-24,74-88,115-191`, `ios/Tests/run-trip-navigation-wiring-check.sh`.

**Interfaces:**
- Produces: full-width `İlk kaydını ekle`, cached ordered stops, and four-tab-plus-Plan-map wiring.

- [ ] **Step 1: Make the navigation check fail, then fix focused UX**

Require only `dashboard plan journal tools`; reject `.tag(AppTab.map)`; assert `PlanScreen` contains `Button { showMap = true }`, `.fullScreenCover(isPresented: $showMap)`, and `PlanMapView()`.

Run: `bash ios/Tests/run-trip-navigation-wiring-check.sh`

Expected: FAIL because the script requires the removed map tab.

Add Journal sentence “Yoldaki anları, notları ve fotoğrafları burada biriktir.” and a 44-point full-width button opening existing `showCompose`. Add `@State private var orderedStops`; sort once in `refreshTripDerivedState()` called from `onAppear` and `onChange(of: trip?.stops)`, then render `ForEach(orderedStops)` with stable stop IDs.

- [ ] **Step 2: Verify and commit**

Run: `bash ios/Tests/run-trip-navigation-wiring-check.sh && bash ios/Tests/run-account-check.sh`

```bash
git add ios/Karavan/Views/Journal/JournalView.swift ios/Karavan/Views/Trips/AccountStopsView.swift ios/Tests/run-trip-navigation-wiring-check.sh
git commit -m "fix(ios): polish empty and route states"
```

### Task 7: Make build 17 and TestFlight mutation failure-safe

**Files:**
- Create: `tools/check-ios-release-version.mjs`, `ios/Tests/run-release-safety-check.sh`; modify: `tools/testflight.sh:1-55`, `public/kuzey-version.json:1-5`; modify only after successful upload: `ios/project.yml`, `ios/Kuzey.xcodeproj/project.pbxproj`, `public/kuzey-version.json`.

**Interfaces:** Produces one version check across app/widget/project/manifest and a release that archives build 18 while source remains 17 until upload succeeds.

- [ ] **Step 1: Write mismatch/order checks and verify RED**

Parse both YAML build values, every pbx target value, and manifest `latestBuild`; require one unique integer. The shell check requires `set -euo pipefail`, rejects `|| true`, requires `CURRENT_PROJECT_VERSION="$NEXT"`, and verifies mutation occurs after `xcrun altool --upload-app`.

Run: `node tools/check-ios-release-version.mjs`

Expected: FAIL with project 17 versus manifest 14.

- [ ] **Step 2: Fix baseline and release ordering**

Set the manifest to `{"latestBuild":17,"minBuild":1}` with no placeholder URL. Keep source untouched before upload. Use failure-propagating commands:

```bash
xcodebuild -project Kuzey.xcodeproj -scheme Kuzey -destination 'generic/platform=iOS' \
  -configuration Release CURRENT_PROJECT_VERSION="$NEXT" -allowProvisioningUpdates \
  archive -archivePath "$ARCHIVE" 2>&1 | tee /tmp/kuzey-archive.log
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST" -allowProvisioningUpdates 2>&1 | tee /tmp/kuzey-export.log
xcrun altool --upload-app -f "$EXPORT_DIR/Kuzey.ipa" -t ios --apiKey "$KEY_ID" --apiIssuer "$ISSUER"
```

After upload only: replace both YAML values with `$NEXT`, set manifest `latestBuild`, run `xcodegen generate`, then `node ../tools/check-ios-release-version.mjs`.

- [ ] **Step 3: Verify and commit**

Run: `bash ios/Tests/run-release-safety-check.sh && node tools/check-ios-release-version.mjs`

Expected: PASS with app/widget/project/manifest all 17.

```bash
git add tools/testflight.sh tools/check-ios-release-version.mjs public/kuzey-version.json ios/Tests/run-release-safety-check.sh
git commit -m "fix(release): make TestFlight versioning atomic"
```

### Task 8: Run regression, simulator acceptance, release, and deploy

**Files:**
- Verify: all Task 1-7 files and every `ios/Tests/run-*.sh`.

**Interfaces:** Consumes completed package-1 v2 API routes and package-2 web commit; produces a verified iOS app, optional TestFlight build 18, and matching deployed manifest.

- [ ] **Step 1: Run all checks and a clean Simulator build**

```bash
for check in ios/Tests/run-*.sh; do echo "==> $check"; bash "$check"; done
cd ios && xcodegen generate
xcodebuild -project Kuzey.xcodeproj -scheme Kuzey \
  -destination 'platform=iOS Simulator,name=Budget Verification' \
  -derivedDataPath /tmp/kuzey-derived-data CODE_SIGNING_ALLOWED=NO clean build
cd ..
```

Expected: every script exits `0` and Xcode prints `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Perform clean-install acceptance**

```bash
xcrun simctl uninstall booted com.bilalsenturk.kuzey || true
xcrun simctl install booted /tmp/kuzey-derived-data/Build/Products/Debug-iphonesimulator/Kuzey.app
xcrun simctl launch booted com.bilalsenturk.kuzey
```

Confirm dashboard opens without prompts; `Konumu Aç` asks only When In Use; the background-arrivals action asks Always; the notification primer asks notifications; denied states open Settings; Journal CTA opens composer; Plan opens `PlanMapView`.

- [ ] **Step 3: Run final clean-tree gate**

```bash
npm run check && npm run lint && npm run build
npm run check:accounts && npm run check:account-auth && npm run check:trip-api
npm run check:web-sync && npm run check:travel-content && npm audit --omit=dev
test -z "$(git status --porcelain)"
```

- [ ] **Step 4: Release only with Apple credentials, then deploy**

```bash
test -f "$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
ASC_KEY_ID="$ASC_KEY_ID" ASC_ISSUER_ID="$ASC_ISSUER_ID" bash tools/testflight.sh
node tools/check-ios-release-version.mjs
git add ios/project.yml ios/Kuzey.xcodeproj/project.pbxproj public/kuzey-version.json
git commit -m "chore(release): record TestFlight build 18"
npm run build && test -z "$(git status --porcelain)"
npm exec vercel -- deploy --prod --yes
```

Expected: TestFlight upload succeeds before source becomes 18; production `https://istanbul-letonya-karavan-astro.vercel.app/kuzey-version.json` reports 18 without a placeholder URL. If Apple credentials/service block upload, leave all sources at 17, deploy the verified build-17 manifest, and report the exact external error.
