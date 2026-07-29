# System Hardening and Experience Design

## Goal

Make the Astro site and Kuzey iOS app safe, reliable, fast, and easier to use. Remove the shared write secret, prevent corrupt trip history, repair stale live data, improve the public journey flow, and replace launch-time permission prompts with contextual actions.

The work ships in three testable packages:

1. Security and data integrity
2. Web correctness, performance, accessibility, and SEO
3. iOS session handling, permission UX, release safety, and targeted performance

Each package must pass its focused tests and the full regression suite before the next package begins. The final verified commit deploys to the linked Vercel project. The iOS release uploads to TestFlight only through a release script that reports archive, export, and upload failures accurately.

## Constraints

- Backward compatibility with uninstalled TestFlight builds is unnecessary.
- Production data migration is unnecessary. Old shared-secret blobs and pending outbox records may be ignored.
- Preserve the current visual language, the committed Kuzey icon work, and the approved cinematic hero design artifacts.
- Do not deploy from a dirty or partially verified tree.
- Keep public tracking available only for the `kuzey2026` trip kind.
- Never publish Kuzey-shaped local data under a standard trip ID.
- Never render raw coordinates as fallback location copy.
- Do not perform broad SwiftUI environment-object refactors without trace evidence.

## Package 1: Security and Data Integrity

### Trip history writes

The trip repository validates a complete candidate state before writing. Invalid trip names, stops, reorder operations, invitations, and role changes return `422` without persisting an event.

The storage interface gains an atomic revision operation. A mutation supplies the current revision and the candidate event. The Blob implementation creates a deterministic `events/{paddedRevision}.json` path without overwrite permission, so only one writer can claim the next revision. A concurrent writer receives `409 revision_conflict` with the current trip. The in-memory implementation follows the same contract for tests.

Trip creation validates the full trip before any write and stores its initial stops in the single `tripCreated` event. A failed create cannot leave a partial trip. Listing trips isolates malformed or unauthorized records; one bad trip cannot break the entire account response.

All domain failures pass through typed repository errors. The API maps authentication failures to `401`, permission failures to `403`, missing resources to `404`, revision conflicts to `409`, and validation failures to `422`.

### Shared-secret removal

Delete the shared `LIVE_POST_SECRET`, `x-live-secret` header, old iOS constant, and old write endpoints. Replace the fixed global resources with trip-scoped v2 resources:

- `PUT /api/v2/trips/:id/live-location`
- `PUT /api/v2/trips/:id/expense-summary`
- `GET/PUT /api/v2/trips/:id/plan-edits`
- `PUT /api/v2/trips/:id/published-plan`
- `PUT /api/v2/trips/:id/shared-journal`

Every write authenticates the Bearer session and authorizes the account against the trip from the URL. Request bodies cannot select or override a trip.

The public website reads separate endpoints:

- `GET /api/v2/public/trips/:id/live-location`
- `GET /api/v2/public/trips/:id/expense-summary`
- `GET /api/v2/public/trips/:id/published-plan`
- `GET /api/v2/public/trips/:id/shared-journal`

Public handlers return `404` unless the requested trip enables public tracking. Public reads expose only the fields already intended for the website.

### Published trip state

Store mutable published state under `accounts/trips/{tripId}/state/{resource}.json` in private Blob storage. Each record uses this envelope:

```json
{
  "schemaVersion": 1,
  "tripId": "kuzey-2026",
  "revision": 1,
  "updatedAt": "ISO-8601 timestamp",
  "updatedBy": "account id",
  "data": {}
}
```

Writes use ETag conditional updates. Stale writes return `409` and the current state. Journal and expense records keep per-user contributions, then public reads aggregate them. The server derives journal authorship from the session instead of trusting client input.

Existing local stores remain Kuzey-specific in this work. Their publishers run only when the selected trip is `kuzey2026` and has public tracking enabled. Standard trips cannot receive those payloads.

### Dependencies

Update Astro, the Vercel adapter, and compatible patch-level tooling. Refresh the lockfile and resolve production audit findings without downgrading the adapter or taking unrelated major upgrades.

## Package 2: Web Correctness and Performance

### Service worker policy

The service worker follows an allowlist:

- `/api/*`, `/sw.js`, `/kuzey-version.json`, `/manifest.webmanifest`, and `/trip-data.json`: network only
- same-origin hashed `/_astro/*`: cache first
- HTML navigations: network first with an eligible offline fallback
- cross-origin resources and other assets: normal browser caching

The worker never stores a response marked `no-store`. Register it from the shared layout so direct day-page visits receive the same behavior.

### Journey and day pages

Add each day slug to the home timeline and expose a clear `Gün planını aç` action without changing the card style.

`RouteMap` gains explicit `journey` and `day` modes plus a live-state flag. Day pages pass only the active origin, destination, and matching route geometry. Static day maps do not subscribe to live events or display `Konum bekleniyor`.

Camp actions distinguish a website from exact navigation. Exact campsite directions remain primary. Empty camera sections stay hidden.

### Runtime behavior

Move the large homepage inline script into a bundled module. Reuse the shared live-data normalization code.

Replace overlapping intervals with awaited self-scheduling loops. Pause polls while the page is hidden, abort them on `pagehide`, resume only stale work, and apply bounded error backoff.

Cache successful weather results for 15 minutes. Request new weather only after 10 km of movement or after the TTL. A failed request must not poison the cache key.

Load Leaflet and map tiles through a dynamic import when the map approaches the viewport. Keep the static fallback visible until tiles load; restore it after tile errors.

### Images, caching, and metadata

Move the homepage presentation images into `src/assets` and render responsive Astro `Picture` or `Image` output. Preserve the source images, crops, and visual hierarchy. Use AVIF and WebP variants, intrinsic dimensions, a high-priority hero, and lazy gallery images.

Add immutable browser caching for hashed Astro assets and hash-named Latvian audio. Keep service workers, manifests, and mutable live data uncached.

Extend the shared layout with canonical, Open Graph, and Twitter metadata. Use page-specific titles and descriptions. Align `robots.txt` and the sitemap with `https://istanbul-letonya-karavan-astro.vercel.app`.

### Accessibility and route data

- Give the visual countdown `role="timer"` and disable second-by-second announcements.
- Announce only meaningful status changes.
- Give the route progress a native or ARIA progress value.
- Add `aria-current="step"` to the active route step.
- Restore heading hierarchy on day pages.
- Underline inline content links and preserve visible focus styles.
- Add the missing Serbia country and flag data.
- Derive mobile route columns from the stop count instead of a hard-coded number.
- Keep all interactive targets at least 44 points on iOS and 44 CSS pixels on the web.

## Package 3: iOS Experience and Release Safety

### Shared authenticated transport

Add one injectable Bearer session coordinator. It owns the current token pair, Keychain persistence, Bearer header injection, refresh rotation, and one retry after `401`.

Concurrent unauthorized requests join one refresh task. A rejected refresh clears the session and notifies `AccountSessionStore`. Connectivity and server failures preserve the tokens and queued work. The outbox stores only trip ID, resource path, and body; it never persists credentials.

Account APIs stop accepting access-token parameters. Account operations, live location, plan publishing, expenses, and shared journal publishing all use the same authenticated transport.

Outbox keys include the trip ID. Signing out pauses publication. Signing in drains eligible pending work. A standard trip cannot publish Kuzey data.

### Contextual permissions

The app reaches the dashboard after a clean install without displaying a system prompt.

Remove notification authorization from app startup. Remove location authorization from dashboard bootstrap. Split location control into explicit When In Use, Always, start-if-authorized, and Settings actions.

The live-location card explains the benefit and exposes `Konumu Aç`. If access is denied, `Ayarları Aç` opens Settings. When In Use authorization reveals an optional `Arka planda varışları aç` action. Never escalate to Always automatically.

The dashboard exposes a compact notification primer for departure, arrival, and weather alerts. It requests notification access only after the user taps the action. Refresh authorization state whenever the app becomes active. Keep the existing contextual Latvian reminder action.

### Focused UX and maintenance

The Journal empty state keeps its current icon and theme, adds one explanatory sentence, and presents a full-width `İlk kaydını ekle` action that opens the existing composer.

Update the stale navigation check to the current dashboard, plan, journal, and tools tabs. Verify the map remains reachable through the plan screen.

Compute ordered account stops once per update rather than sorting inside the rendered loop. Preserve stable stop IDs. Leave the existing journal image pipeline unchanged.

### Release versioning

Treat build 17 as the current baseline. The release script calculates the next build in temporary command-line settings and mutates project source only after a successful upload. Archive, export, and upload failures must stop the script.

After a successful release, synchronize `project.yml`, the generated Xcode project, and `public/kuzey-version.json`. Omit the placeholder TestFlight URL until a real URL exists. Add a check that rejects mismatched app, widget, and web-manifest build numbers.

## Data Flow

1. Apple Sign In creates an app session and stores the token pair in Keychain.
2. Every protected request enters the Bearer coordinator.
3. The API verifies the JWT, confirms the stored session, loads the trip from the URL, and checks the action against the account role.
4. The repository validates the candidate state and performs a conditional Blob write.
5. The public site reads only the approved public representation for `kuzey2026`.
6. A `401` triggers one token refresh and one retry. A `409` returns current state for conflict handling. Queued writes remain pending through offline failures.

## Error Handling

- `400`: malformed JSON or request syntax
- `401`: missing, expired, invalid, or revoked session
- `403`: authenticated account lacks permission
- `404`: missing trip or non-public tracking resource
- `409`: stale revision or failed Blob precondition
- `422`: valid JSON with invalid domain data
- `500/503`: unexpected storage or service failure without credential deletion

The website shows the last known live values with an explicit disconnected age instead of presenting stale data as current. The iOS app keeps drafts and outbox records after recoverable network failures.

## Testing

### Server and web

- Add failing tests for validate-before-write, atomic revision conflicts, corrupt-trip isolation, role checks, cross-trip rejection, public-tracking gates, ETag conflicts, and server-authored journal entries.
- Add service-worker policy, weather TTL, polling, route-link, day-map, canonical, robots, and accessibility contract tests.
- Run Astro check, ESLint, the production build, all custom checks, and the production dependency audit.

### iOS

- Test Bearer attachment, one refresh for concurrent `401` responses, token rotation, retry limits, revocation, offline preservation, trip-scoped outbox records, and absence of the shared secret.
- Test permission-policy decisions as pure Swift logic.
- Confirm source wiring contains no launch-time permission requests.
- Run every `ios/Tests/run-*.sh` script and a clean Xcode Simulator build.
- On a clean simulator install, confirm the dashboard opens without a prompt; trigger each prompt from its matching action.

### Browser acceptance

- Verify 390×844 and 1440×900 layouts.
- Confirm no horizontal overflow or console errors.
- Confirm day links, exact day maps, keyboard focus, route state, and Journal CTA.
- Confirm Leaflet and tiles stay unloaded above the fold and load near the map.
- Confirm repeated location polls do not multiply weather requests.

## Deployment

Commit each verified package separately. Run the full suite from the final commit. Deploy the clean commit to the linked Vercel production project, then verify the production URL, public APIs, sitemap, service-worker headers, and responsive pages.

Run the repaired TestFlight release only after local archive/export checks pass and Apple credentials are available. Verify the uploaded build and the synchronized web version manifest. If an external credential or store service blocks one target, complete the other target and report the exact external blocker without weakening verification.
