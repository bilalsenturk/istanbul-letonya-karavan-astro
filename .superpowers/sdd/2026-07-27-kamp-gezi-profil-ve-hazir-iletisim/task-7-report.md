# Task 7 Report — Gün Ayrıntısında Kamp ve Gezi Deneyimi

## Status

Implementation complete with two pre-existing web-suite failures and limited simulator interaction evidence. Task 7 focused tests and the iOS simulator build pass.

## RED / GREEN

RED was captured before production code existed:

```text
./ios/Tests/run-travel-content-store-check.sh
error: cannot find 'TravelContentStore' in scope
exit 1
```

GREEN after implementation: 12/12 checks pass. Coverage includes remote replacement, atomic cache persistence, valid-content preservation after network and malformed-JSON failures, cold remote→cache→embedded fallback, invalid cache/embedded rejection, stale concurrent response ordering, cancellation, the committed embedded bundle, all six Turkish destination aliases, and media disclosure decoding.

## Architecture and behavior

- `TravelContentStore` is a root-owned, `@MainActor` `ObservableObject` with injected remote URL, `URLSession`, cache URL, and embedded-data loader.
- Remote requests use a 12-second timeout, `useProtocolCachePolicy`, and an `Accept: application/json` header.
- Only completely decoded and minimally valid bundles are published. Network/decoding failures preserve an existing valid bundle. A cold store tries remote, disk, then embedded JSON.
- The last remote-valid bytes are written atomically under Application Support. Cache write failure never clears valid memory state.
- Each load has a generation; a newer load cancels the old task, and a late cancellation-ignoring response cannot overwrite newer content.
- `KaravanApp` owns and injects the store and calls `loadIfNeeded()` from its root `.task`. The endpoint is `Config.imageBaseURL/assets/travel-content.json`.
- `TravelMedia` now decodes `role`, `depictsCampground`, `alt`, `disclosure`, and nested photo source. `DestinationKey` maps Sofya, Novi Sad, Budapeşte, Krakow, Varşova, and Riga to the six bundle keys.
- `ArrivalTarget.maximumLengthMeters` and `AccountArrivalTarget.maximumLengthMeters` preserve a selected curated camp's message-composer length input through local and account stop stores.

## UI

Day detail order is now: facts, primary arrival target, manual communication state, nearby camps, nearby attractions, waypoints, subplans. Unsupported/transit destinations omit curated sections and never borrow another city's content. `Buraya git` remains the only prominent primary action.

`NearbyCampSection` and `NearbyAttractionSection` use small cards and adaptive horizontal/vertical action layouts. Camp distance is explicitly labelled `Şehir merkezine kuş uçuşu`; attraction distance is explicitly labelled `Konaklamadan kuş uçuşu`. No Haversine result is called driving distance.

Camp actions open exact coordinates in Maps, open the existing stay/contact editor with the curated phone/email/length constraint, and preview then persist camp selection. Attraction directions open exact coordinates in Apple Maps. Source sheets show verification date, factual source, photo credit, license, and photo source.

All camp photos in the current package are city/destination representations. Every card visibly says `TEMSİLİ DESTİNASYON · KAMP FOTOĞRAFI DEĞİL`, repeats the manifest disclosure, and exposes an accessibility label. `CampImage` accepts only HTTP(S) absolute or safely resolved relative URLs and keeps a stable themed placeholder offline.

## Embedded parity

`ios/Karavan/Resources/travel-content.json` is byte-identical to `public/assets/travel-content.json`.

```text
SHA-256 bc046b99bbec943d6af857929dcdd5101b12e77dfc25f8f14a944e8e35472973
```

XcodeGen generated exactly the three new project references/build entries, and the build logged `CpResource ... Kuzey.app/travel-content.json`.

## Files

Task 7 paths:

- `ios/Karavan/TravelContentStore.swift`
- `ios/Karavan/Views/NearbyTravelSections.swift`
- `ios/Karavan/Resources/travel-content.json`
- `ios/Tests/travel-content-store-check.swift`
- `ios/Tests/run-travel-content-store-check.sh`
- `ios/Karavan/TravelContent.swift`
- `ios/Karavan/ArrivalTarget.swift`
- `ios/Karavan/Accounts/AccountModels.swift`
- `ios/Karavan/Views/DayDetailView.swift`
- `ios/Karavan/KaravanApp.swift`
- `ios/Karavan/Views/CampImage.swift`
- `ios/Kuzey.xcodeproj/project.pbxproj`

`ios/project.yml` needed no Task 7 hunk because its existing `Karavan` directory source automatically classifies Swift and JSON files into Sources/Resources. Regeneration produced only the exact new references above.

## Full verification suite

Passes (exit 0):

- `npm run check:travel-content` — 6 destinations, 14 camps, 18 attractions, 8 negative checks.
- `npm run check:accounts`
- `npm run check:account-auth`
- `npm run check:trip-api`
- `npm run check:web-sync`
- `./ios/Tests/run-arrival-target-check.sh`
- `./ios/Tests/run-travel-content-check.sh`
- `./ios/Tests/run-travel-content-store-check.sh`
- `./ios/Tests/run-planner-check.sh`
- `./ios/Tests/run-account-check.sh`
- `xcodebuild -project ios/Kuzey.xcodeproj -scheme Kuzey -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build` — `BUILD SUCCEEDED`.
- `xcodegen generate`
- `cmp public/assets/travel-content.json ios/Karavan/Resources/travel-content.json`

Pre-existing unrelated failures:

- `npm run check` exits 1 with five TypeScript errors at `src/accounts/accountRepository.ts:195-196` (`resolved` is `{ } | null`, so comparisons/number return are invalid), plus two Latvian-pack unused-argument hints. Task 7 does not modify those files.
- `npm run lint` exits 1 with 28 existing findings (25 errors, 3 warnings), principally `structuredClone` reported undefined in account/auth/trip/travel validator scripts. Task 7 adds no JavaScript/TypeScript.

## Simulator evidence and limitations

XcodeBuildMCP was not callable, so the skill-approved `xcodebuild`/`simctl` fallback was used. No simulator was booted automatically. Already booted devices were iPhone 17 (`687D33A5-A851-40B8-9979-743BD38156E5`) and iPad (A16) (`92EE1FB2-27F2-4C31-BF66-D2AA100B8F09`), plus an unrelated Budget test device.

The built app was installed and launched with the Plan preview argument on both target devices. Ready native screenshots prove the six destination rows render on iPhone and iPad; the iPad uses its adaptive top tab layout. The local Astro server was started with `npx astro dev --background`, allocated port 4322 because 4321 was already occupied by an unrelated 404 server, and was stopped with `npx astro dev stop`.

`serve-sim` ran against the exact iPhone UDID with a simulator-scoped cleanup trap. Its terminal reported real framebuffer callbacks (`1206x2622`, direct IOSurface), and the browser showed the real Plan frame, but the helper stayed behind its `connecting` overlay. It was terminated and the trap ran. Therefore no claim is made that the browser mirror, one destination detail, source sheet, Maps/contact/profile interactions, all-six-day details, a small iPhone, VoiceOver, or Dynamic Type were interactively verified. The small booted handset requested by the brief was not available, and the skill rule forbids booting one automatically. Accessibility/Dynamic Type were instead checked statically: no fixed text container heights, adaptive action layout, multiline text, explicit action/image labels and hints, and honest placeholder semantics.

Evidence files:

- `evidence/task7-iphone-plan.png`
- `evidence/task7-ipad-plan-ready.png`
- `evidence/task7-iphone-plan-axxxl.png` (content-size command was rejected; this is not claimed as XXL evidence)

## Concurrency and commit safety

The shared checkout remained heavily dirty with unrelated account, navigation, Latvian learning, web, and generated changes. No reset, revert, checkout, or amend was used. XcodeGen's project diff contains exactly 12 added lines for `TravelContentStore.swift`, `NearbyTravelSections.swift`, and `travel-content.json`; it did not capture unrelated untracked resources. Only the explicit Task 7 paths are staged/committed.

---

## Fix Round 1 — 2026-07-27

### Status and commits

Fix Round 1 is implemented and verified. The work is split into four narrow commits:

- `26fed93 fix: preserve travel stay account fields`
- `1c28f3a fix: validate curated travel content`
- `e59e6f9 fix: preserve selected camp state`
- `7d9400e fix: refresh travel content on foreground`

The shared checkout still contains unrelated concurrent edits in `ArrivalTarget.swift`, `KaravanApp.swift`, and other paths. The two overlapping files were staged hunk-by-hunk, so the commits above contain only Fix Round 1 changes.

### RED / GREEN evidence

Account contract RED was captured after adding the round-trip assertion and before changing production parsing:

```text
npm run check:accounts
AssertionError [ERR_ASSERTION]: Expected values to be strictly equal:
undefined !== 7.5
at tools/check-account-domain.mjs:109:8
exit 1
```

The store admission/transport RED was captured before exposing and implementing the stricter decoder:

```text
ios/Tests/run-travel-content-store-check.sh
error: 'decodeValid' is inaccessible due to 'private' protection level
error: extra argument 'now' in call
exit 1
```

After the first validator implementation, the mutation suite exposed silent policy clamping:

```text
✗ 25 km üzerindeki şehir politikası sessizce kırpılmadan reddedilir
❌ 1 STORE KONTROLÜ BAŞARISIZ
```

The model was then changed to preserve the decoded policy value so admission can reject it. Final GREEN:

```text
npm run check:accounts                         PASS
npm run check:account-auth                     PASS
npm run check:trip-api                         PASS
ios/Tests/run-travel-content-store-check.sh    PASS
ios/Tests/run-arrival-target-check.sh          PASS
ios/Tests/run-travel-content-check.sh           PASS
xcodebuild ... CODE_SIGNING_ALLOWED=NO build   BUILD SUCCEEDED
```

### Account contract

The web stop contract now preserves and validates `maximumLengthMeters`, `estimatedArrivalMode`, and `estimatedArrivalWindow` (`start`, `end`, and `timeZoneIdentifier`). The domain test performs a JSON encode/decode round trip through a folded stop update and proves that a 7.5 m limit and manual ETA survive. Invalid/non-positive length, unknown ETA mode, and reversed ETA windows are rejected. Missing fields remain valid for legacy clients. The account auth and trip repository checks also pass.

### Curated-content admission, HTTP, cache, and retry

Admission now requires exactly the six normalized route keys, a positive version, sensible generated/verification dates, a city center, at least two camps and three attractions per destination, finite in-range coordinates, unique IDs, city policy at or below 25 km, and candidates inside the allowed distance. It verifies nonempty factual/media metadata, HTTPS official/photo-source URLs, safe bundled photo paths, representative-photo role/disclosure, and the WOK 8 m and Camping & Yachts 7.5 m restrictions. Content older than 90 days remains admissible and is handled as a UI warning.

Remote loading now requires an HTTP(S) URL, an `HTTPURLResponse`, a 2xx status, JSON or `+json` MIME (parameters allowed), and at most 2 MiB. Tests verify the `Accept` header, 12-second timeout, protocol cache policy, status/MIME/size/non-HTTP rejection, atomic cache success, and cache-write failure without loss of valid memory state. Decode and disk read/write execute through a dedicated actor rather than on the main actor.

Concurrent `loadIfNeeded()` calls coalesce to one request. A fallback result does not permanently suppress a later retry. Foreground refresh is throttled for five minutes and is wired from `KaravanApp`; a refresh after the interval performs a new request. Generation checks still prevent a late cancellation-ignoring response from replacing newer content.

### Selection, contact, permissions, and freshness UI

Candidate contact now opens `ArrivalTargetEditorView` in a dedicated contact-only purpose. That mode has `Bitti`, no `Kaydet`, no save callback, disabled stay/target edits, no profile mutation path, and no post-send reservation-status persistence. Only `Bu kampı seç` opens the curated-camp selection confirmation.

Viewer users cannot open target selection or edit-save controls; an existing target opens in contact-only mode. `saveTarget` checks edit permission before clearing route state, setting the local plan, or starting account synchronization. `supportsCaravan: false` camps disable selection and visibly show `Bu kamp çekme karavan kabul etmiyor; varış yeri olarak seçilemez.` They are never mapped to a selectable caravan-park target.

A local target/stay override is installed before sync and has precedence over stale account data, so an offline or failed update remains visibly selected. Sync failures explicitly say the target is stored on the device but not shared. Each save carries a monotonically increasing revision plus trip and user IDs; canceled, stale, wrong-trip, and wrong-account completions cannot replace workspace state. A successful current response replaces the workspace and clears the local override.

Camp cards, attraction cards, and source sheets use injected `now` values for freshness. The exact warning `Gitmeden önce teyit et` appears only after 90 days. Tests cover the 90-day boundary and the 91-day warning case.

### Remaining concerns

- The revision/trip/user guard and local-override precedence are covered by deterministic policy tests, while transport ordering is covered by the cancellation-ignoring URL protocol fixture. There is no end-to-end test with two real server updates completing out of order; a server-side revision conflict can leave the newest local choice visible with the honest unsynced warning until retry.
- Fix Round 1 rebuilt the complete iOS simulator target but did not repeat the earlier manual VoiceOver, Dynamic Type, Maps, or contact-composer interaction audit.
- The pre-existing full `npm run check` TypeScript failures and lint findings documented above were outside this round and were not changed.

---

## Fix Round 2 — 2026-07-27

### Status and commits

Fix Round 2 is implemented and verified in three narrow production commits:

- `e37f386 fix: align account ETA wire format`
- `1f9de43 fix: make travel content updates race safe`
- `8166d77 fix: persist offline camp selection`

Overlapping shared files were staged hunk-by-hunk. Unrelated preview fixtures, legacy decoder changes, route-data edits, and the rest of the dirty checkout were not included.

### RED / GREEN evidence

ETA contract tests failed before the wire adapter and strict web validators existed. Swift's synthesized `Date` decoder could not consume the server ISO string (`Expected to decode Double but found a string instead`), and the web negative cases reported missing expected exceptions for noncanonical dates and an invalid IANA zone. The final account suites pass with ISO encode/server decode/legacy numeric coverage.

Travel-store tests were added first for exact raw keys and IDs, critical camp facts, unsafe local media paths, and deterministic suspensions at decode/cache/embedded stages. The pre-change implementation had no injected async I/O generation boundary, so the new gated tests could not compile or guarantee that an older operation would be rejected after resuming. After implementation, the full store harness passes, including older decode, cache fallback, cache write, and embedded fallback losing to the newest generation.

Durable-selection tests were added before the scoped types and resolver. The RED compile failed because `ArrivalTargetOverrideScope`, `ScopedArrivalTargetOverride`, `ArrivalTargetSelectionResolver`, and `DayEdit.arrivalTargetScope` did not exist. The GREEN planner harness proves JSON persistence through view recreation, local-over-stale-account precedence for a matching scope, and no leakage across trip, day, or user scopes.

### Account ETA wire contract

`AccountStayDetails` now uses a private wire DTO for the ETA window. Encoding always emits ISO-8601 UTC strings ending in `Z`; decoding accepts server ISO-8601 strings with or without fractional seconds and the legacy Foundation reference-date numbers. The local `StayETAWindow` representation remains unchanged.

The web boundary accepts only canonical UTC forms (`YYYY-MM-DDTHH:mm:ssZ` or exactly three fractional digits), rejects impossible round trips and offsets, verifies `end > start`, and validates the supplied IANA identifier with `Intl.DateTimeFormat`. Omitted legacy fields remain valid.

### Canonical admission and race-safe I/O

Admission now preflights the raw JSON object before Codable normalization. It requires exactly the version-1 root shape, the six canonical destination keys, city policy `25`, the approved camp and attraction ID sets, HTTPS factual/photo sources, and safe `/assets/...` media paths with no traversal, escaping, percent encoding, query, or fragment. Representative media semantics and the WOK, Camping & Yachts, Ave Natura, Clepardia, Riga City Camping, and Farma 47 critical facts are pinned. Content older than 90 days remains admissible and continues to use the existing freshness warning.

Immutable travel-content values crossing concurrency boundaries conform to `Sendable`. Decode, cache read/write, and main-bundle reads run through `TravelContentIO`; the store advances its generation before work and rechecks generation/cancellation immediately after every suspension. Deterministic continuation gates prove a resumed old decode cannot publish or overwrite cache, and resumed old cache/embedded fallbacks cannot replace a newer remote result.

HTTP response admission checks status, JSON MIME, declared `Content-Length`/`expectedContentLength`, and the actual two-MiB byte count. This rejects an oversized declared body before decoding and rejects any oversized received body before admission or cache persistence.

### Durable offline camp selection

Camp selection is persisted in `DayEdit` with a trip/day/user scope, then resolved ahead of stale account data only when that scope matches. Recreating `DayDetailView` therefore restores an unsynced local choice from `TripPlanStore`; changing trip or account cancels pending work and prevents the prior selection from leaking. A current successful account update replaces workspace state and clears only the matching local override. Failed or unavailable sync keeps the scoped device selection.

The scope is local metadata and is stripped from the public plan payload. Contact-only and viewer permission behavior from Round 1 remains unchanged.

### Final verification

Fresh passes (exit 0):

- `./ios/Tests/run-travel-content-store-check.sh`
- `./ios/Tests/run-travel-content-check.sh`
- `./ios/Tests/run-arrival-target-check.sh`
- `./ios/Tests/run-account-check.sh`
- `./ios/Tests/run-planner-check.sh`
- `npm run check:accounts`
- `npm run check:account-auth`
- `npm run check:trip-api`
- `xcodebuild -project ios/Kuzey.xcodeproj -scheme Kuzey -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` — `BUILD SUCCEEDED`
- `git diff --cached --check`

### Remaining concerns

- `URLSession.data(for:)` still materializes a response when `Content-Length` is absent or dishonest. The actual-byte cap prevents decode, publication, and cache persistence after receipt, but it is not a streaming memory bound. A delegate/streamed download with enforced cancellation remains a future hardening step.
- The scoped resolver/store behavior has deterministic model tests and the app target compiles, but this round did not add a UI automation test that kills/relaunches the app during a real failed account request.
- Exact version-1 IDs and critical content are deliberately app-pinned. Any legitimate version, destination, or curated-item-set change requires an app admission-policy update rather than being silently accepted.
