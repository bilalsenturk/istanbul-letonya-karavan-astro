# Apple Hesapları ve Çoklu Rotalar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apple hesabıyla giriş yapan kullanıcıların yetkilerine göre rota oluşturmasını, haritada durak düzenlemesini ve rotaya üye eklemesini sağlamak.

**Architecture:** Astro `/api/v2` uçları Apple kimlik token'ını doğrular, Kuzey oturumu üretir ve kişisel veriyi Vercel Private Blob'da olay kayıtları olarak saklar. iOS kökünde `AccountSessionStore` ile `TripWorkspaceStore` bulunur; seçili rota yoksa rota listesi, varsa mevcut sekmeli uygulama açılır. MapKit tabanlı rota oluşturucu arama, haritadan seçim, sıralama ve durak ayrıntılarını tek taslakta tutar.

**Tech Stack:** Swift 5.9, SwiftUI iOS 17, AuthenticationServices, MapKit, Security/Keychain, Astro 7, TypeScript, `jose`, Vercel Private Blob.

## Global Constraints

- Yeni sabit ücretli servis eklenmeyecek; mevcut Vercel Hobby projesi kullanılacak.
- Apple ile girişte özel hesaplar ilk girişte `E-postamı paylaş` seçmelidir.
- `senturk.bilal@icloud.com` global admin olur.
- `senturk.leyla@icloud.com` ve `szngk.13@icloud.com` Kuzey rotasında üye olur.
- Yeni rota oluşturan kullanıcı kendi rotasının sahibi olur.
- `kuzey2026` özellikleri yalnızca mevcut Kuzey rotasında görünür.
- Bütün yazma yetkileri sunucuda denetlenir.

---

### Task 1: Yetki ve Rota Alan Modeli

**Files:**
- Create: `src/accounts/domain.ts`
- Create: `tools/check-account-domain.mjs`
- Modify: `package.json`

**Interfaces:**
- Produces: `resolveGlobalRole(email)`, `can(role, action)`, `foldTripEvents(events)`, `TripRecord`, `TripMemberRecord`, `RouteStopRecord`.

- [ ] **Step 1: Write the failing domain tests**

Test admin e-posta eşlemesini, rota rollerini, standard rota özelliklerini, olay katlamayı ve son sahibin silinememesini gerçek fonksiyonlarla doğrular.

```js
assert.equal(resolveGlobalRole('senturk.bilal@icloud.com'), 'globalAdmin');
assert.equal(can({ globalRole: 'user', tripRole: 'member' }, 'editStops'), true);
assert.equal(can({ globalRole: 'user', tripRole: 'viewer' }, 'editStops'), false);
assert.deepEqual(featuresFor('standard'), { latvian: false, kuzeyMusic: false });
```

- [ ] **Step 2: Run the test and verify RED**

Run: `node --experimental-strip-types tools/check-account-domain.mjs`

Expected: FAIL because `src/accounts/domain.ts` does not exist.

- [ ] **Step 3: Implement the minimal domain model**

Use string unions for `GlobalRole`, `TripRole`, `TripKind`, and `TripAction`. Keep authorization pure and independent from Astro or Blob.

```ts
export const can = (access: Access, action: TripAction): boolean => {
  if (access.globalRole === 'globalAdmin') return true;
  if (access.tripRole === 'owner') return true;
  if (access.tripRole === 'member') return action === 'read' || action === 'editStops' || action === 'editJournal';
  return access.tripRole === 'viewer' && action === 'read';
};
```

- [ ] **Step 4: Run domain tests and verify GREEN**

Run: `npm run check:accounts`

Expected: `Account domain checks passed.`

- [ ] **Step 5: Commit**

```bash
git add src/accounts/domain.ts tools/check-account-domain.mjs package.json
git commit -m "feat: hesap ve rota yetki modelini ekle"
```

### Task 2: Apple Kimlik Doğrulama ve Kuzey Oturumu

**Files:**
- Create: `src/accounts/appleAuth.ts`
- Create: `src/accounts/session.ts`
- Create: `src/pages/api/v2/auth/apple.ts`
- Create: `src/pages/api/v2/auth/refresh.ts`
- Create: `src/pages/api/v2/auth/logout.ts`
- Create: `src/pages/api/v2/me.ts`
- Create: `tools/check-account-auth.mjs`
- Modify: `package.json`

**Interfaces:**
- Consumes: `resolveGlobalRole(email)`.
- Produces: `verifyAppleIdentityToken(token, rawNonce)`, `issueSession(user)`, `requireSession(request)`.

- [ ] **Step 1: Write failing JWT tests**

Generate an ephemeral ES256 test key. Verify correct issuer, audience, expiry and nonce; reject a different nonce and audience. Verify the Kuzey access token returns the original user id and global role.

- [ ] **Step 2: Run the auth test and verify RED**

Run: `node --experimental-strip-types tools/check-account-auth.mjs`

Expected: FAIL because auth modules do not exist.

- [ ] **Step 3: Install and implement `jose` verification**

Run: `npm install jose`

Production uses Apple's JWKS URI and `com.bilalsenturk.kuzey` audience. Tests inject a local `createLocalJWKSet`. Session signing uses `AUTH_SESSION_SECRET`; production refuses the request when the secret is missing.

```ts
const { payload } = await jwtVerify(token, appleKeys, {
  issuer: 'https://appleid.apple.com',
  audience: 'com.bilalsenturk.kuzey',
});
if (payload.nonce !== sha256(rawNonce)) throw new AuthError('invalid_nonce');
```

- [ ] **Step 4: Implement auth routes**

`POST /apple` accepts `{ identityToken, rawNonce, givenName, familyName }`. It persists the verified Apple subject and first-login email, applies the three seed roles, claims pending invitations and returns `{ accessToken, refreshToken, user, trips }`.

- [ ] **Step 5: Run auth and Astro checks**

Run: `npm run check:account-auth && npm run check`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add package.json package-lock.json src/accounts src/pages/api/v2 tools/check-account-auth.mjs
git commit -m "feat: Apple girişini ve Kuzey oturumunu ekle"
```

### Task 3: Private Blob Rota Deposu ve API

**Files:**
- Create: `src/accounts/privateBlob.ts`
- Create: `src/accounts/tripRepository.ts`
- Create: `src/pages/api/v2/trips/index.ts`
- Create: `src/pages/api/v2/trips/[id].ts`
- Create: `src/pages/api/v2/trips/[id]/stops.ts`
- Create: `src/pages/api/v2/trips/[id]/members.ts`
- Create: `tools/check-trip-api.mjs`

**Interfaces:**
- Consumes: `requireSession(request)`, `can(access, action)`.
- Produces: `listTripsForUser`, `createTrip`, `getTrip`, `appendTripEvent`, `inviteMember`.

- [ ] **Step 1: Write failing repository tests**

Use an in-memory `TripEventStorage` implementation. Cover creating a standard trip, ordered stop mutations, `409` stale revision, member invite, viewer rejection, member stop edit and standard feature flags.

- [ ] **Step 2: Run repository tests and verify RED**

Run: `node --experimental-strip-types tools/check-trip-api.mjs`

Expected: FAIL because repository modules do not exist.

- [ ] **Step 3: Implement the storage boundary and repository**

```ts
export interface TripEventStorage {
  list(tripId: string): Promise<TripEvent[]>;
  append(event: TripEvent): Promise<void>;
}
```

Private Blob paths use `accounts/trips/<tripId>/events/<timestamp>-<uuid>.json`. The adapter requires `PRIVATE_BLOB_READ_WRITE_TOKEN` and uses `access: 'private'`.

- [ ] **Step 4: Implement authenticated API routes**

Validate names, coordinates, URL lengths, roles and base revisions before appending events. Never accept `kuzey2026` from a create request. Return structured `{ error, message, current }` responses.

- [ ] **Step 5: Run repository, account and Astro checks**

Run: `npm run check:trip-api && npm run check:accounts && npm run check:account-auth && npm run check`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/accounts src/pages/api/v2 tools/check-trip-api.mjs package.json
git commit -m "feat: çoklu rota ve üyelik API'sini ekle"
```

### Task 4: iOS Oturum ve Çalışma Alanı Depoları

**Files:**
- Create: `ios/Karavan/Accounts/AccountModels.swift`
- Create: `ios/Karavan/Accounts/KeychainTokenStore.swift`
- Create: `ios/Karavan/Accounts/AccountAPI.swift`
- Create: `ios/Karavan/Accounts/AccountSessionStore.swift`
- Create: `ios/Karavan/Accounts/TripWorkspaceStore.swift`
- Create: `ios/Tests/account-domain-check.swift`
- Create: `ios/Tests/run-account-check.sh`
- Modify: `ios/Karavan/Config.swift`
- Modify: `ios/project.yml`

**Interfaces:**
- Produces: `AccountSessionStore.State`, `signIn(authorization:nonce:)`, `signOut()`, `TripWorkspaceStore.selectedTrip`, `features` and `permissions`.

- [ ] **Step 1: Write failing Swift domain tests**

Test decoding, role permissions, standard/Kuzey feature flags, selected-trip persistence scoped by user id and sign-out cache removal.

- [ ] **Step 2: Run the Swift test and verify RED**

Run: `./ios/Tests/run-account-check.sh`

Expected: compiler failure because account models do not exist.

- [ ] **Step 3: Implement models and stores**

Use `@MainActor ObservableObject` to match the existing iOS 17 project. Store secrets only through Security.framework. Keep account and route selection in separate stores.

- [ ] **Step 4: Add Sign in with Apple entitlement**

Add `com.apple.developer.applesignin: [Default]` to the app entitlements and regenerate the Xcode project with `xcodegen generate --spec ios/project.yml`.

- [ ] **Step 5: Run Swift account tests and build**

Run: `./ios/Tests/run-account-check.sh`

Run: `xcodebuild -project ios/Kuzey.xcodeproj -scheme Kuzey -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build`

Expected: PASS and `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add ios/Karavan/Accounts ios/Karavan/Config.swift ios/Karavan/Kuzey.entitlements ios/project.yml ios/Kuzey.xcodeproj ios/Tests
git commit -m "feat: iOS hesap oturumunu ve rota çalışma alanını ekle"
```

### Task 5: Giriş ve Rotalarım Ekranları

**Files:**
- Create: `ios/Karavan/Views/Accounts/SignInView.swift`
- Create: `ios/Karavan/Views/Trips/TripsHomeView.swift`
- Create: `ios/Karavan/Views/Trips/AccountMenuView.swift`
- Modify: `ios/Karavan/KaravanApp.swift`
- Modify: `ios/Karavan/Views/ContentView.swift`

**Interfaces:**
- Consumes: `AccountSessionStore`, `TripWorkspaceStore`.
- Produces: signed-out gate, route picker, account menu and route workspace shell.

- [ ] **Step 1: Add source-level UI contract checks**

Extend `account-domain-check.swift` with copy constants and shell decisions so signed-out, empty, loading and selected-trip states stay explicit.

- [ ] **Step 2: Run and verify RED**

Run: `./ios/Tests/run-account-check.sh`

Expected: FAIL for missing shell policy.

- [ ] **Step 3: Implement the app gate and screens**

`SignInView` uses `SignInWithAppleButton`. `TripsHomeView` shows route rows, member role, last update and a single `Yeni rota` command. `ContentView` renames `Rotalar` to `Duraklar` and presents `TripsHomeView` when no route is selected.

- [ ] **Step 4: Run tests and build**

Run account tests and the iPhone 17 simulator build. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Karavan/Views/Accounts ios/Karavan/Views/Trips ios/Karavan/KaravanApp.swift ios/Karavan/Views/ContentView.swift ios/Tests
git commit -m "feat: Apple giriş ve Rotalarım ekranlarını ekle"
```

### Task 6: MapKit Rota Oluşturucu ve Durak Ayrıntısı

**Files:**
- Create: `ios/Karavan/Routes/RouteDraft.swift`
- Create: `ios/Karavan/Routes/PlaceSearchService.swift`
- Create: `ios/Karavan/Routes/RoutePreviewService.swift`
- Create: `ios/Karavan/Views/Trips/RouteBuilderView.swift`
- Create: `ios/Karavan/Views/Trips/StopEditorView.swift`
- Modify: `ios/Tests/account-domain-check.swift`

**Interfaces:**
- Produces: `RouteDraft.add`, `move`, `update`, `isSavable`; async place search and route preview.

- [ ] **Step 1: Write failing draft tests**

Test two-point minimum, stable stop identity, move order, detail preservation and invalid coordinate rejection.

- [ ] **Step 2: Run and verify RED**

Run: `./ios/Tests/run-account-check.sh`

Expected: FAIL because `RouteDraft` does not exist.

- [ ] **Step 3: Implement draft and MapKit services**

Use `MKLocalSearchCompleter` for suggestions, `MKLocalSearch` for coordinates and `MKDirections` for the preview. Cancel the previous search and directions task when input changes.

- [ ] **Step 4: Implement the route builder UI**

Use a stable map height, map controls, searchable bottom list and numbered stop rows. Support current location, map long press, search result selection, drag reorder and a sheet-based `StopEditorView`. Preserve the draft on MapKit or network failure.

- [ ] **Step 5: Run tests and build**

Run account tests and the simulator build. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ios/Karavan/Routes ios/Karavan/Views/Trips ios/Tests
git commit -m "feat: harita tabanlı rota oluşturucuyu ekle"
```

### Task 7: Duraklar ve Üye Yönetimi

**Files:**
- Create: `ios/Karavan/Views/Trips/MembersView.swift`
- Create: `ios/Karavan/Views/Trips/MemberInviteView.swift`
- Modify: `ios/Karavan/Views/MapScreen.swift`
- Modify: `ios/Karavan/Views/Tools/ToolsView.swift`
- Modify: `ios/Karavan/Views/ContentView.swift`
- Modify: `ios/Karavan/Accounts/TripWorkspaceStore.swift`

**Interfaces:**
- Consumes: selected trip permissions and features.
- Produces: role-aware stop editing, member invites and Kuzey-only tool visibility.

- [ ] **Step 1: Write failing permission/feature tests**

Assert member stop editing, viewer read-only UI, owner member management and hidden special tools for `standard` trips.

- [ ] **Step 2: Run and verify RED**

Run: `./ios/Tests/run-account-check.sh`

Expected: FAIL for missing presentation policy.

- [ ] **Step 3: Implement member management**

Show owner, members and pending invitations in one list. Invite sheet validates normalized email and offers `Üye` or `Görüntüleyen`. Only owner/global admin sees role menus and removal controls.

- [ ] **Step 4: Adapt Duraklar and Araçlar**

Rename visible route copy to `Duraklar`. Feed selected route stops to the map workspace. Hide Letonca and Kuzey music sections unless `features.latvian` or `features.kuzeyMusic` is true.

- [ ] **Step 5: Run all checks and build**

Run: `npm run check:accounts && npm run check:account-auth && npm run check:trip-api && ./ios/Tests/run-account-check.sh && ./ios/Tests/run-planner-check.sh && npm run check`

Run the iPhone 17 simulator build. Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add ios/Karavan/Views ios/Karavan/Accounts ios/Tests
git commit -m "feat: Duraklar ve rota üyelerini role bağla"
```

### Task 8: Ortam, Simülatör ve Görsel Doğrulama

**Files:**
- Modify: `.env.example`
- Modify: `ios/README.md`

**Interfaces:**
- Consumes: completed API and iOS app.
- Produces: repeatable local setup and verified screens.

- [ ] **Step 1: Document required secrets**

Document `AUTH_SESSION_SECRET`, `PRIVATE_BLOB_READ_WRITE_TOKEN` and `APPLE_BUNDLE_ID=com.bilalsenturk.kuzey`. Never commit real values.

- [ ] **Step 2: Create/connect a private Blob store**

Use the linked Vercel project to create a private store and connect its token as `PRIVATE_BLOB_READ_WRITE_TOKEN`. Stop and report if Vercel authentication is unavailable; do not expose data through the public store.

- [ ] **Step 3: Start local Astro in background mode**

Run: `astro dev --background`

Expected: local server at `http://localhost:4321`.

- [ ] **Step 4: Install and launch the simulator app**

Build, install the Debug app on the booted iPhone 17 simulator and launch `com.bilalsenturk.kuzey`.

- [ ] **Step 5: Inspect required screens**

Capture and inspect iPhone screenshots for Apple login, Rotalarım, new route map, stop editor and members. Verify no overflow, overlap, blank map or inaccessible primary action.

- [ ] **Step 6: Run final verification**

Run all Node, Swift and Xcode checks again. Record any external Apple/Vercel configuration that still blocks real sign-in.

- [ ] **Step 7: Commit documentation**

```bash
git add .env.example ios/README.md
git commit -m "docs: hesap ve rota ortam kurulumunu açıkla"
```
