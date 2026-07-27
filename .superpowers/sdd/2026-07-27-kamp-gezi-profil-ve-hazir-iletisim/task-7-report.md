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
