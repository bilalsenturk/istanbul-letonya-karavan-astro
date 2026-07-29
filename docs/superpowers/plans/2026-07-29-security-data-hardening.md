# Security and Data Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make trip-event and published-trip writes valid, atomic, account-scoped, and free of the shared iOS/server write secret.

**Architecture:** Keep event history append-only, but validate a complete candidate trip before claiming a deterministic revision path with Blob create-only semantics. Add a separate private published-state repository whose Blob ETags remain internal; trip-scoped handlers authenticate the URL trip, while public handlers expose only the approved Kuzey representation. Keep legacy read/write routes during intermediate commits, then delete them only after the iOS Bearer callers and web public URLs have migrated.

**Tech Stack:** Astro 7, TypeScript on Node 22, `@vercel/blob`, JOSE Bearer sessions, Swift 5.9/iOS 17 callers, Node assertion checks.

## Global Constraints

- Backward compatibility with uninstalled TestFlight builds is unnecessary.
- Production data migration is unnecessary. Old shared-secret blobs and pending outbox records may be ignored.
- Preserve the current visual language, the committed Kuzey icon work, and the approved cinematic hero design artifacts.
- Do not deploy from a dirty or partially verified tree.
- Keep public tracking available only for the `kuzey2026` trip kind.
- Never publish Kuzey-shaped local data under a standard trip ID.
- Never render raw coordinates as fallback location copy.
- Do not perform broad SwiftUI environment-object refactors without trace evidence.
- This plan owns server security/state work. The Package 3 plan owns `BearerSession`, Swift publisher migration, and `ios/Karavan/Config.swift`; the Package 2 plan owns website URL migration.
- Blob ETags never enter HTTP request or response bodies.
- `plan-edits` is optimistic: authenticated GET returns `{revision,departureAt,days,updatedAt}` and PUT accepts `{baseRevision,departureAt,days}`.
- The other authenticated PUTs use three server-side CAS attempts and return `{ok:true,revision,updatedAt}`.

## File Structure

- `src/accounts/domain.ts`: typed trip-domain validation and initial-stop folding.
- `src/accounts/tripRepository.ts`: candidate validation, authorization, conflict translation, corrupt-record isolation.
- `src/accounts/privateBlob.ts`: create-only and ETag-conditional private JSON primitives.
- `src/accounts/blobTripStorage.ts`: deterministic atomic event revision adapter.
- `src/accounts/bootstrap.ts`: atomic Kuzey seed/invite mutations.
- `src/accounts/publishedState.ts`: resource names, payload types, bounded validators, public projections.
- `src/accounts/publishedStateRepository.ts`: trip authorization, CAS retry, contribution merge, public gate.
- `src/accounts/blobPublishedStateStorage.ts`: private Blob state adapter.
- `src/pages/api/v2/trips/[id]/*.ts`: five authenticated published-state routes.
- `src/pages/api/v2/public/trips/[id]/*.ts`: four public read routes; `plan-edits` is never public.
- `tools/check-trip-api.mjs`, `tools/check-account-auth.mjs`, `tools/check-published-state.mjs`: executable regression checks.

---
### Task 1: Typed Domain Failures and Single-Event Trip Creation

**Files:**
- Modify: `src/accounts/domain.ts:104-181`
- Modify: `src/accounts/tripRepository.ts:43-87`
- Modify: `tools/check-trip-api.mjs:11-53`
**Interfaces:**
- Produces: `TripDomainError.code: string`; `tripCreated.payload.stops`; a new trip always has revision `1`.
- Consumes: existing `RouteStopRecord`, `TripEvent`, and `foldTripEvents(events)`.
- [ ] **Step 1: Write the failing create-validation checks**

Add assertions that a valid two-stop create stores exactly one event at revision 1, and invalid stop coordinates/name reject without changing `storage.events`. Assert the creation payload contains normalized orders `[0, 1]`.
```js
assert.equal((await storage.list(created.id)).length, 1);
assert.equal(created.revision, 1);
const before = storage.totalEvents();
await assert.rejects(createTrip(storage, owner, {
  name: 'Bozuk', stops: [{ id: 'x', name: '', lat: 120, lng: 29, order: 0 }],
}), (error) => error?.code === 'stop_name_required');
assert.equal(storage.totalEvents(), before);
```
- [ ] **Step 2: Run the check and confirm RED**
Run: `npm run check:trip-api`
Expected: FAIL because create currently appends `tripCreated` and one `stopAdded` per stop before folding.
- [ ] **Step 3: Implement typed folding and one-event creation**

Add `TripDomainError`, replace domain `throw new Error(code)` sites with it, parse `created.payload.stops ?? []` through the existing stop validator, reject more than 50/duplicate IDs, and sort by order. Build one `tripCreated` candidate containing `stops`, call `foldTripEvents([candidate])`, translate `TripDomainError` to `TripRepositoryError`, then append only the validated candidate.
- [ ] **Step 4: Run focused checks and confirm GREEN**
Run: `npm run check:accounts && npm run check:trip-api`
Expected: both pass; existing event histories without `tripCreated.payload.stops` still fold.
- [ ] **Step 5: Commit**
```bash
git add src/accounts/domain.ts src/accounts/tripRepository.ts tools/check-trip-api.mjs
git commit -m "fix: validate trip creation before persistence"
```
### Task 2: Atomic Event Revision Storage

**Files:**
- Modify: `src/accounts/privateBlob.ts:1-39`
- Modify: `src/accounts/tripRepository.ts:17-21`
- Modify: `src/accounts/blobTripStorage.ts:1-22`
- Modify: `tools/check-trip-api.mjs:11-27`
**Interfaces:**
- Produces: `TripEventStorage.append(event: TripEvent, expectedRevision: number): Promise<void>`.
- Produces: `PrivateBlobConflictError`; `createPrivateJSON(pathname, value): Promise<{etag:string}>`.
- Storage path: `accounts/trips/{tripId}/events/{revision.padStart(10, '0')}.json` with `allowOverwrite:false`.
- [ ] **Step 1: Make the memory storage enforce the new contract**

Implement the test double so `event.revision !== expectedRevision + 1` or an occupied revision throws `TripStorageConflictError`. Add `Promise.allSettled` for two revision-2 appends and assert exactly one fulfills.
- [ ] **Step 2: Run RED**
Run: `npm run check:trip-api`
Expected: FAIL because `append` has no expected revision and Blob paths include random event IDs.
- [ ] **Step 3: Add the create-only Blob primitive and deterministic adapter**

In local memory, check and set the path synchronously. In Blob mode call `put(pathname, payload, {access:'private', token, contentType:'application/json', addRandomSuffix:false, allowOverwrite:false})`; translate `BlobPreconditionFailedError` to `PrivateBlobConflictError`. Make `BlobTripEventStorage.append` validate the expected revision and translate the private conflict to `TripStorageConflictError`.
- [ ] **Step 4: Update all call sites to pass expected revision and verify**
Run: `npm run check:trip-api && npm run check:account-auth && npm run check`
Expected: all pass with no TypeScript errors.
- [ ] **Step 5: Commit**
```bash
git add src/accounts/privateBlob.ts src/accounts/tripRepository.ts src/accounts/blobTripStorage.ts tools/check-trip-api.mjs
git commit -m "fix: claim trip revisions atomically"
```
### Task 3: Validate Every Candidate and Isolate Corrupt Histories

**Files:**
- Modify: `src/accounts/tripRepository.ts:113-215`
- Modify: `src/accounts/bootstrap.ts:12-127`
- Modify: `tools/check-trip-api.mjs`
**Interfaces:**
- Produces: `getTripForAction(storage, actor, tripId, action): Promise<TripRecord>`.
- Produces: `getPublicTrip(storage, tripId): Promise<TripRecord>`; only `kind === 'kuzey2026' && featuresFor(kind).publicTracking` succeeds.
- Conflict shape remains `TripRepositoryError('revision_conflict', ..., current)`.
- [ ] **Step 1: Add invalid-mutation, race, and isolation checks**

Assert invalid stop update/reorder/invite/last-owner changes do not increment stored event count. Race two valid mutations from the same base revision and assert one rejects with `revision_conflict` plus the winning current trip. Inject malformed history and an unauthorized trip; assert `listTripsForUser` still returns the valid authorized trip.
- [ ] **Step 2: Run RED**
Run: `npm run check:trip-api`
Expected: FAIL because mutation appends before candidate folding and malformed history aborts the whole list.
- [ ] **Step 3: Implement candidate-first mutations**

Load `{events, trip}`, authorize, compare `baseRevision`, construct the candidate, and call `foldTripEvents([...events, candidate])` before `append(candidate, trip.revision)`. On `TripStorageConflictError`, reload and throw `revision_conflict` with current. Apply the same path to invitations and bootstrap mutations; seed Kuzey with initial stops in one `tripCreated` event.
- [ ] **Step 4: Isolate malformed and forbidden list entries**

Translate failures while folding stored history to `TripRepositoryError('trip_corrupt')`; skip `trip_corrupt` and `forbidden` inside `listTripsForUser`, but preserve `trip_not_found` for direct reads.
- [ ] **Step 5: Verify and commit**
Run: `npm run check:accounts && npm run check:trip-api && npm run check:account-auth`
Expected: all pass.
```bash
git add src/accounts/tripRepository.ts src/accounts/bootstrap.ts tools/check-trip-api.mjs
git commit -m "fix: reject invalid trip events before append"
```
### Task 4: Complete the API Error Taxonomy

**Files:**
- Modify: `src/accounts/api.ts:33-68`
- Modify: `src/pages/api/v2/auth/refresh.ts:8-21`
- Modify: `tools/check-account-auth.mjs`
**Interfaces:**
- Produces: `401` authentication/session, `403` permission, `404` missing/non-public, `409` revision/precondition, `422` domain validation, `500` unexpected storage.
- [ ] **Step 1: Add response assertions**

Assert `UnauthorizedError` and `session_revoked` map to 401; `forbidden` to 403; `trip_not_found` to 404; `revision_conflict` to 409 with `current`; validation codes to 422; unknown errors to redacted 500.
- [ ] **Step 2: Run RED**
Run: `npm run check:account-auth`
Expected: FAIL because refresh currently throws plain `session_revoked`, which becomes 500.
- [ ] **Step 3: Normalize authentication failures and verify**

Throw `UnauthorizedError` for inactive refresh sessions, invalid refresh tokens, and missing refresh accounts. Keep malformed JSON at 400 and never return raw exception messages for 500.
Run: `npm run check:account-auth && npm run check:trip-api`
Expected: both pass.
- [ ] **Step 4: Commit**
```bash
git add src/accounts/api.ts src/pages/api/v2/auth/refresh.ts tools/check-account-auth.mjs
git commit -m "fix: map account API failures consistently"
```
### Task 5: Private Published-State Storage with Internal ETags

**Files:**
- Create: `src/accounts/publishedState.ts`
- Create: `src/accounts/blobPublishedStateStorage.ts`
- Modify: `src/accounts/privateBlob.ts`
- Create: `tools/check-published-state.mjs`
- Modify: `package.json:13-22`
**Interfaces:**
- Produces: `PublishedResource = 'live-location' | 'expense-summary' | 'plan-edits' | 'published-plan' | 'shared-journal'`.
- Produces: `PublishedStateEnvelope<T> = {schemaVersion:1;tripId:string;revision:number;updatedAt:string;updatedBy:string;data:T}`.
- Produces: `PublishedStateStorage.read<T>(tripId, resource): Promise<{state:PublishedStateEnvelope<T>;etag:string}|null>` and `write<T>(tripId, resource, state, expectedEtag:string|null): Promise<{state:PublishedStateEnvelope<T>;etag:string}>`.
- Blob path: `accounts/trips/{tripId}/state/{resource}.json`.
- [ ] **Step 1: Add storage contract checks**

Create an in-memory adapter in the check file. Assert create uses expected ETag `null`, replacement rejects a stale ETag, successful replacement increments revision, and neither serialized API projection contains `etag`.
- [ ] **Step 2: Add the check script and run RED**

Add `"check:published-state": "node --experimental-strip-types tools/check-published-state.mjs"`.
Run: `npm run check:published-state`
Expected: FAIL because the modules do not exist.
- [ ] **Step 3: Implement conditional private writes**

Add `readPrivateJSONWithETag` and `writePrivateJSONConditional`. Use `allowOverwrite:false` for `expectedEtag === null`; otherwise use `ifMatch:expectedEtag`. Translate `BlobPreconditionFailedError` to `PrivateBlobConflictError`; local memory generates a new opaque ETag after every successful write.
- [ ] **Step 4: Implement the Blob state adapter and verify**
Run: `npm run check:published-state && npm run check`
Expected: both pass.
- [ ] **Step 5: Commit**
```bash
git add src/accounts/publishedState.ts src/accounts/blobPublishedStateStorage.ts src/accounts/privateBlob.ts tools/check-published-state.mjs package.json
git commit -m "feat: add conditional published trip storage"
```
### Task 6: Authorized Published-State Repository

**Files:**
- Create: `src/accounts/publishedStateRepository.ts`
- Modify: `src/accounts/publishedState.ts`
- Modify: `tools/check-published-state.mjs`
**Interfaces:**
- Produces: `getPlanEdits(deps, actor, tripId)` and `putPlanEdits(deps, actor, tripId, input)`.
- Produces: `putPublishedResource(deps, auth, tripId, resource, input): Promise<{ok:true;revision:number;updatedAt:string}>`.
- Produces: `getPublicPublishedResource(deps, tripId, resource): Promise<unknown>`.
- Authorization: live=`startRoute`, expense=`editJournal`, plan-edits=`editStops`, published-plan=`editTrip`, journal=`editJournal`.
- [ ] **Step 1: Add failing authorization, cross-trip, validation, and CAS checks**

Test that a request actor cannot select a trip from the body, viewers cannot write, standard trips cannot expose public state, and `plan-edits` stale revision returns current state. Test two contribution writers and force one precondition failure; the three-attempt merge must preserve both accounts.
- [ ] **Step 2: Add bounded payload checks**

Cover coordinate ranges; nonnegative finite expenses; at most 32 category keys; plan day limits of 60; journal limit of 250 entries, 200-character IDs, 5,000-character text, valid ISO dates, and ignored client `author` fields.
- [ ] **Step 3: Run RED**
Run: `npm run check:published-state`
Expected: FAIL because the repository is missing.
- [ ] **Step 4: Implement repository and public projections**

Store expense and journal data as contributions keyed by authenticated account ID. Derive journal author from `auth.account.displayName`; aggregate expense totals/categories and flatten journal entries for public reads. For non-plan PUTs, read/merge/conditional-write at most three times. For `plan-edits`, reject a stale `baseRevision` immediately and include its current projected state.
- [ ] **Step 5: Verify and commit**
Run: `npm run check:published-state && npm run check:trip-api`
Expected: both pass.
```bash
git add src/accounts/publishedState.ts src/accounts/publishedStateRepository.ts tools/check-published-state.mjs
git commit -m "feat: authorize trip scoped published state"
```
### Task 7: Add Five Authenticated v2 Resource Routes

**Files:**
- Create: `src/pages/api/v2/trips/[id]/live-location.ts`
- Create: `src/pages/api/v2/trips/[id]/expense-summary.ts`
- Create: `src/pages/api/v2/trips/[id]/plan-edits.ts`
- Create: `src/pages/api/v2/trips/[id]/published-plan.ts`
- Create: `src/pages/api/v2/trips/[id]/shared-journal.ts`
- Modify: `tools/check-published-state.mjs`
**Interfaces:**
- All PUT handlers call `authenticateRequest(request)` and take the trip only from `params.id`.
- `plan-edits` GET/PUT uses the optimistic contract in Global Constraints.
- Other PUT request shapes remain: current live body; `{totalEur,count,byCategory,ts}`; current published-plan body; `{entries:[{id,text,createdAt,mood?,stopId?}]}`.
- [ ] **Step 1: Add route contract assertions and run RED**

Assert all five files exist, export `prerender = false`, use PUT rather than POST, authenticate before repository calls, never inspect `body.tripId`, and return `Cache-Control: no-store`.
Run: `npm run check:published-state`
Expected: FAIL because the routes are absent.
- [ ] **Step 2: Implement thin handlers**

Each handler parses JSON with `requestJSON`, calls the production Blob repositories, and passes failures through `errorResponse`. `plan-edits` also exposes authenticated GET; the other protected endpoints expose only PUT.
- [ ] **Step 3: Verify and commit**
Run: `npm run check:published-state && npm run check && npm run build`
Expected: all pass and Astro emits all five server routes.
```bash
git add src/pages/api/v2/trips src/accounts tools/check-published-state.mjs
git commit -m "feat: add authenticated published state routes"
```
### Task 8: Add Public Kuzey Read Routes

**Files:**
- Create: `src/pages/api/v2/public/trips/[id]/live-location.ts`
- Create: `src/pages/api/v2/public/trips/[id]/expense-summary.ts`
- Create: `src/pages/api/v2/public/trips/[id]/published-plan.ts`
- Create: `src/pages/api/v2/public/trips/[id]/shared-journal.ts`
- Modify: `tools/check-published-state.mjs`
**Interfaces:**
- Public GETs preserve legacy website shapes; they never return an envelope, contributor account IDs, ETags, or private plan edits.
- Missing state, standard trips, and trips without public tracking return 404.
- [ ] **Step 1: Add failing public-gate and privacy assertions**

Assert four routes exist and no public `plan-edits.ts` exists. Exercise projections and assert expense contributors and journal account IDs are absent while journal display authors remain server-authored.
- [ ] **Step 2: Run RED, implement handlers, and run GREEN**
Run: `npm run check:published-state`
Expected before implementation: FAIL. Expected after implementation: PASS.
Run: `npm run check:published-state && npm run check:trip-api && npm run build`
Expected: all pass.
- [ ] **Step 3: Commit**
```bash
git add src/pages/api/v2/public src/accounts/publishedStateRepository.ts tools/check-published-state.mjs
git commit -m "feat: expose gated public Kuzey state"
```
### Task 9: Patch Production Dependencies Without Major Upgrades

**Files:**
- Modify: `package.json:24-41`
- Modify: `package-lock.json`
**Interfaces:**
- Astro `^7.1.6`; `@astrojs/vercel` `^11.0.4`; `@astrojs/check` `^0.9.10`; Prettier `^3.9.6`; `typescript-eslint` `^8.65.0`.
- Do not accept the audit suggestion that downgrades the Vercel adapter to 8.x; do not upgrade ESLint or TypeScript across a major version.
- [ ] **Step 1: Capture the current production audit**
Run: `npm audit --omit=dev`
Expected: nonzero with the previously observed Astro adapter/path-to-regexp and tar findings.
- [ ] **Step 2: Apply compatible patch updates**
Run: `npm install astro@^7.1.6 @astrojs/vercel@^11.0.4 && npm install --save-dev @astrojs/check@^0.9.10 prettier@^3.9.6 typescript-eslint@^8.65.0`
- [ ] **Step 3: Verify dependency and application health**
Run: `npm audit --omit=dev && npm run check && npm run lint && npm run build`
Expected: audit exits 0; check/build pass; lint has no errors.
- [ ] **Step 4: Commit**
```bash
git add package.json package-lock.json
git commit -m "chore: patch production web dependencies"
```
### Task 10: Cross-Package Migration Gate, Legacy Deletion, and Full Verification

**Files:**
- Delete: `src/pages/api/location.ts`
- Delete: `src/pages/api/expenses.ts`
- Delete: `src/pages/api/plan.ts`
- Delete: `src/pages/api/edits.ts`
- Delete: `src/pages/api/journal.ts`
- Modify: `README.md`
- Modify: `ios/README.md`
- Modify: `docs/APP-OVERVIEW.md`
- Modify: `tools/check-published-state.mjs`
**Interfaces:**
- Consumes from Package 3: `BearerSessionCoordinator.data(path:method:body:)`, trip-scoped `PublishOutbox` records, all Swift callers on `/api/v2/trips/{selectedTripId}/...`, and no `Config.livePostSecret`.
- Consumes from Package 2: website reads `/api/v2/public/trips/kuzey-2026/{live-location,expense-summary,published-plan,shared-journal}`.
- Produces: no runtime reference to `LIVE_POST_SECRET`, `x-live-secret`, or the five legacy API paths.
- [ ] **Step 1: Verify both external migration prerequisites**
Run:
```bash
rg -n 'livePostSecret|x-live-secret|api/(location|expenses|plan|edits|journal)' ios/Karavan src/pages/index.astro src/scripts
```
Expected: no matches. If matches remain, execute the owning Package 2 or Package 3 plan before continuing; do not delete a route still used by a caller.
- [ ] **Step 2: Delete legacy handlers and update current documentation**

Remove the five files. Document Bearer authentication, private state paths, v2 protected/public URL tables, 409/422 behavior, and the absence of a shared app secret. Historical specs/plans remain unchanged.
- [ ] **Step 3: Make the security check reject regressions**

Add source scans limited to `src`, `ios/Karavan`, `README.md`, `ios/README.md`, and `docs/APP-OVERVIEW.md`; fail on `LIVE_POST_SECRET`, `x-live-secret`, `livePostSecret`, or the five legacy API URLs.
- [ ] **Step 4: Run the complete server/web/iOS verification**
Run:
```bash
npm run check:accounts
npm run check:account-auth
npm run check:trip-api
npm run check:published-state
npm run check:web-sync
npm run check:latvian-pack
npm run check:travel-content
npm run check
npm run lint
npm run build
npm audit --omit=dev
for script in ios/Tests/run-*.sh; do bash "$script"; done
xcodebuild -project ios/Kuzey.xcodeproj -scheme Kuzey -sdk iphonesimulator -configuration Debug -derivedDataPath /tmp/kuzey-security-derived-data CODE_SIGNING_ALLOWED=NO build
git status --short
```
Expected: every command exits 0 and `git status --short` contains only this package's intended files before commit.
- [ ] **Step 5: Commit the verified cleanup**
```bash
git add src/pages/api README.md ios/README.md docs/APP-OVERVIEW.md tools/check-published-state.mjs
git commit -m "refactor: remove shared secret publishing routes"
```

Do not deploy from this task. The master plan deploys only after Package 2 and Package 3 acceptance checks pass from the final clean commit.
