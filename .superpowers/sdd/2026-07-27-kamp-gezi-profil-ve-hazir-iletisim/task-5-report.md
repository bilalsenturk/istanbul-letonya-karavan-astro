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
