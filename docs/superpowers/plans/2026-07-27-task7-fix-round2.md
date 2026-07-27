# Task 7 Fix Round 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the account ETA wire format, make curated-content loading/admission race-safe and canonical, and keep offline camp selections durable across view recreation.

**Architecture:** Account JSON uses an explicit wire DTO for ETA windows while local `StayETAWindow` remains unchanged. Travel content is preflighted from raw JSON before Codable normalization and all suspending I/O is generation-gated through an injected Sendable actor boundary. Day detail resolves a scoped persisted edit before account/base data only when the plan store records a real override.

**Tech Stack:** Swift 5/SwiftUI/Foundation, actor isolation, URLSession, Node.js TypeScript domain checks, shell Swift harnesses, Xcode simulator build.

## Global Constraints

- Preserve numeric Foundation `Date` payload compatibility while emitting canonical ISO-8601 UTC strings.
- Accept only version 1 and the approved six destinations/item ID sets.
- Content older than 90 days remains admissible and surfaces the existing warning.
- Never stage or overwrite unrelated shared-checkout changes.

---

### Task 1: Account ETA wire format

**Files:**
- Modify: `ios/Tests/arrival-target-check.swift`
- Modify: `ios/Karavan/Accounts/AccountModels.swift`
- Modify: `tools/check-account-domain.mjs`
- Modify: `src/accounts/domain.ts`

**Interfaces:**
- Produces: `AccountStayDetails.Codable` with ISO UTC `estimatedArrivalWindow.start/end` and numeric legacy decode.
- Produces: canonical UTC/IANA validation in the web stop parser.

- [x] Add Swift assertions that encoded ETA dates are strings, server ISO strings decode, and numeric legacy values decode.
- [x] Run `ios/Tests/run-arrival-target-check.sh` and record RED.
- [x] Implement the custom Swift wire Codable adapter without changing `StayETAWindow`.
- [x] Add web assertions rejecting `"1"`, impossible/noncanonical timestamps, and invalid IANA zones while accepting omission.
- [x] Run `npm run check:accounts` and record RED.
- [x] Implement canonical UTC and IANA validation.
- [x] Run both focused harnesses and commit `fix: align account ETA wire format`.

### Task 2: Canonical and race-safe travel content

**Files:**
- Modify: `ios/Tests/travel-content-store-check.swift`
- Modify: `ios/Karavan/TravelContentStore.swift`
- Modify: `ios/Karavan/TravelContent.swift`

**Interfaces:**
- Consumes: committed version-1 bundle and the approved item IDs in `tools/check-travel-content.mjs`.
- Produces: raw preflight admission plus generation-gated async `TravelContentIO` operations.

- [x] Add raw-key, exact-ID, critical-camp, representative-media, and traversal mutation tests.
- [x] Add deterministic gated decode/fallback tests where an older generation resumes after a newer generation.
- [x] Run the store harness and record RED.
- [x] Implement raw JSON preflight, version-1 exact sets, safe media grammar, and complete critical restrictions.
- [x] Change embedded loading to an async `@Sendable` actor operation and recheck generation after every suspension before publication/cache state.
- [x] Add Sendable conformances to immutable content values crossing actor boundaries.
- [x] Add Content-Length preflight; attempt streaming only if deployment/API compatibility is clean, otherwise document the bounded-buffer limitation.
- [x] Run store/content harnesses and commit `fix: make travel content updates race safe`.

### Task 3: Durable scoped offline selection

**Files:**
- Modify: `ios/Tests/planner-check.swift` or focused arrival harness input
- Modify: `ios/Karavan/TripPlanStore.swift`
- Modify: `ios/Karavan/Views/DayDetailView.swift`
- Modify: `ios/Karavan/ArrivalTarget.swift` only if the existing pure resolver needs extension.

**Interfaces:**
- Produces: a plan-store query that distinguishes an actual persisted arrival override from base data.
- Produces: trip/day/user-scoped ephemeral override context.

- [x] Add a failing resolver/recreation test proving a persisted local edit wins over stale account data only for the matching trip/day/user context.
- [x] Run the focused harness and record RED.
- [x] Implement the plan-store override query and scoped resolution/clearing in day detail while preserving request guards.
- [x] Run arrival/planner/account harnesses and commit `fix: persist offline camp selection`.

### Task 4: Verification and report

**Files:**
- Modify: `.superpowers/sdd/2026-07-27-kamp-gezi-profil-ve-hazir-iletisim/task-7-report.md`

- [x] Run store/content/arrival/account/planner Swift harnesses.
- [x] Run `npm run check:accounts`, `npm run check:account-auth`, and `npm run check:trip-api`.
- [x] Run the full iOS simulator Debug build with code signing disabled.
- [x] Append Fix Round 2 RED/GREEN evidence, commits, behavior, and remaining limitations.
- [x] Commit the report separately.
