# Task 5 Report — ETA, Konaklama Varsayılanları ve Ulaşım-Duyarlı Mesaj

## TDD evidence

1. Added ETA, transport exclusion, length-warning, manual legacy decode, rollover, exact-boundary and DST behavior checks to `arrival-target-check.swift` before the implementation.
2. RED observed: `StayETACalculator` and the extended message-composer signature were unresolved.
3. Implemented the smallest model/calculator/composer behavior and re-ran GREEN.
4. Added old `DayPlan` JSON decoding coverage to planner checks and the legacy account stay default check.

The brief's example is arithmetically inconsistent: `08:00 + 8 h + 45 min + 90 min = 18:15`, so the one-hour window is correctly asserted as `18:00–19:00`, not `17:00–18:00`.

## Delivered

- Destination-calendar ETA windows, with a stable one-hour interval beginning at the containing half-hour.
- Automatic/manual ETA state that preserves manual values until `Otomatik kullan` is explicitly selected.
- Automobile-only vehicle, length and electricity copy; every transport mode retains guests, pets and additional needs. Oversize camps receive a confirmation line.
- Backward-compatible ETA/day waypoint/border decoding and account stay persistence.
- Day detail defaults use real driving time, waypoint minutes, border buffer and destination time zone; editor gets selected transport/profile and links to Travel Profile instead of duplicating profile fields.

## Verification

- `./ios/Tests/run-arrival-target-check.sh` — pass
- `./ios/Tests/run-planner-check.sh` — pass
- `./ios/Tests/run-account-check.sh` — pass
- `xcodebuild -project ios/Kuzey.xcodeproj -scheme Kuzey -configuration Debug -sdk iphonesimulator -derivedDataPath /tmp/kuzey-task5-derived CODE_SIGNING_ALLOWED=NO build` — `BUILD SUCCEEDED`

## Scope note

`ios/Karavan/Resources/trip.json` and `src/data/tripData.json` already contain a large concurrent route rewrite, so no JSON hunks were staged by this task.

## Fix round 1

Added RED checks for nearest-half-hour ETA and Turkish flight wording; they failed under the previous floor-only calculator and ungated camp wording. GREEN now uses absolute-date nearest-half-hour rounding (ties upward), a ±30 minute window, overflow-clamped ETA additions, DST offset labels when a window crosses an offset change, and automobile-only camp-limit messaging. Planner, account and arrival checks pass in the shared worktree.

## Fixture closure

The committed planner fixture now orders `borderBufferMinutes` after `camp` and supplies the new optional camp-length argument. A detached committed-tree compile succeeds. Its runtime planner harness still traps on the pre-existing mismatch between the committed 8-day resource and the separately committed 6-day planner expectations; the shared worktree's synchronized route content passes all three harnesses.

## Fix round 2

RED coverage added for DST fall-back ambiguity, bounded extreme waypoint input, and manual-to-automatic resolution. GREEN uses the production `StayETAInput` bounded total and `StayArrivalModeResolver`; arrival, account, and planner harnesses pass in the synchronized worktree.

## Fix round 3

The editor now invokes `StayArrivalModeResolver.useAutomatic`, while day defaults use both `StayETAInput.boundedWaypointMinutes` and `StayArrivalModeResolver.applyingAutomaticDefault`; a manual ETA therefore remains untouched until the explicit automatic action. The arrival harness exercises the same helpers with `[Int.max, Int.max]`, performs a real `AccountStayDetails` JSON encode/decode/resolution round trip for a manual window, and verifies Riga's second repeated 03:45 (UTC+2) plus a fallback window that prints two distinct EEST/EET (or GMT-offset) labels. Arrival, account, and planner harnesses pass.
