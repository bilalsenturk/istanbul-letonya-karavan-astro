/* global structuredClone */

import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { resolve } from 'node:path';
import { createServer } from 'vite';
import {
  getPlanEdits,
  getPublicPublishedResource,
  putPlanEdits,
  putPublishedResource,
} from '../src/accounts/publishedStateRepository.ts';
import { errorResponse, json, requestJSON } from '../src/accounts/api.ts';
import { UnauthorizedError } from '../src/accounts/session.ts';
import { TripStorageConflictError } from '../src/accounts/tripRepository.ts';

const migrationScanRoots = ['src', 'ios/Karavan', 'README.md', 'ios/README.md', 'docs/APP-OVERVIEW.md'];
const retiredPublishingReferences = [
  'LIVE_POST_SECRET',
  'x-live-secret',
  'livePostSecret',
  '/api/location',
  '/api/expenses',
  '/api/plan',
  '/api/edits',
  '/api/journal',
];

const sourceFiles = (pathname) => {
  const absolutePath = resolve(process.cwd(), pathname);
  if (!existsSync(absolutePath)) return [];
  if (statSync(absolutePath).isFile()) return [pathname];
  const entries = readdirSync(absolutePath, { withFileTypes: true });
  return entries.flatMap((entry) => {
    const child = `${pathname}/${entry.name}`;
    return entry.isDirectory() ? sourceFiles(child) : entry.isFile() ? [child] : [];
  });
};

const migrationFiles = migrationScanRoots.flatMap(sourceFiles);
for (const forbidden of retiredPublishingReferences) {
  const offenders = migrationFiles.filter(
    (pathname) =>
      pathname.includes(forbidden) || readFileSync(resolve(process.cwd(), pathname), 'utf8').includes(forbidden),
  );
  assert.deepEqual(offenders, [], `${forbidden} must not remain in current source or documentation`);
}

const v2PublishedStateRoutes = [
  { resource: 'live-location', methods: ['PUT'] },
  { resource: 'expense-summary', methods: ['PUT'] },
  { resource: 'plan-edits', methods: ['GET', 'PUT'] },
  { resource: 'published-plan', methods: ['PUT'] },
  { resource: 'shared-journal', methods: ['PUT'] },
];

const publicPublishedStateRoutes = ['live-location', 'expense-summary', 'published-plan', 'shared-journal'];

for (const { resource, methods } of v2PublishedStateRoutes) {
  const relativePath = `src/pages/api/v2/trips/[id]/${resource}.ts`;
  const routePath = resolve(process.cwd(), relativePath);
  assert.ok(existsSync(routePath), `${relativePath} must exist`);
  const source = readFileSync(routePath, 'utf8');
  assert.match(source, /export const prerender = false/, `${resource} must be server-rendered`);
  assert.doesNotMatch(source, /body\.tripId/, `${resource} must never select a trip from the request body`);
  assert.match(source, /authenticateRequest\(request\)/, `${resource} must authenticate requests`);
  assert.match(source, /return dependencies\.json\(/, `${resource} responses must use the no-store JSON helper`);
  assert.match(source, /return dependencies\.errorResponse\(error\)/, `${resource} failures must use errorResponse`);
  const authenticateIndex = source.indexOf('authenticateRequest(request)');
  const repositoryIndex =
    resource === 'plan-edits'
      ? Math.min(source.indexOf('await getPlanEdits'), source.indexOf('await putPlanEdits'))
      : source.indexOf('await putPublishedResource');
  assert.ok(authenticateIndex < repositoryIndex, `${resource} must authenticate before repository calls`);
  for (const method of methods) {
    assert.match(source, new RegExp(`export const ${method}\\b`), `${resource} must export ${method}`);
  }
  for (const method of ['GET', 'POST', 'PATCH', 'DELETE']) {
    if (!methods.includes(method)) {
      assert.doesNotMatch(source, new RegExp(`export const ${method}\\b`), `${resource} must not expose ${method}`);
    }
  }
}

for (const resource of publicPublishedStateRoutes) {
  const relativePath = `src/pages/api/v2/public/trips/[id]/${resource}.ts`;
  const routePath = resolve(process.cwd(), relativePath);
  assert.ok(existsSync(routePath), `${relativePath} must exist`);
  const source = readFileSync(routePath, 'utf8');
  assert.match(source, /export const prerender = false/, `${resource} must be server-rendered`);
  assert.match(source, /await getPublicPublishedResource/, `${resource} must use the public repository projection`);
  assert.match(source, /return dependencies\.json\(/, `${resource} must return the raw no-store JSON projection`);
  assert.match(source, /return dependencies\.errorResponse\(error\)/, `${resource} failures must use no-store errors`);
  assert.match(source, /export const GET\b/, `${resource} must export GET`);
  for (const method of ['POST', 'PUT', 'PATCH', 'DELETE']) {
    assert.doesNotMatch(source, new RegExp(`export const ${method}\\b`), `${resource} must not expose ${method}`);
  }
  assert.doesNotMatch(source, /authenticateRequest/, `${resource} must be readable without authentication`);
}

assert.equal(
  existsSync(resolve(process.cwd(), 'src/pages/api/v2/public/trips/[id]/plan-edits.ts')),
  false,
  'private plan edits must never have a public route',
);

class MemoryPublishedStateStorage {
  entries = new Map();
  readCalls = [];
  writeCalls = [];
  conflictCount = 0;
  readBarriers = new Map();

  synchronizeReads(resource, count) {
    this.readBarriers.set(resource, { count, waiting: 0, releases: [] });
  }

  async read(tripId, resource) {
    this.readCalls.push(`${tripId}:${resource}`);
    const snapshot = structuredClone(this.entries.get(`${tripId}:${resource}`) ?? null);
    const barrier = this.readBarriers.get(resource);
    if (barrier && barrier.waiting < barrier.count) {
      barrier.waiting += 1;
      if (barrier.waiting === barrier.count) {
        for (const release of barrier.releases) release();
        this.readBarriers.delete(resource);
      } else {
        await new Promise((resolve) => barrier.releases.push(resolve));
      }
    }
    return snapshot;
  }

  async write(tripId, resource, state, expectedEtag) {
    this.writeCalls.push(expectedEtag);
    const key = `${tripId}:${resource}`;
    const current = this.entries.get(key);
    if ((current && current.etag !== expectedEtag) || (!current && expectedEtag !== null)) {
      this.conflictCount += 1;
      throw new Error('private_blob_conflict');
    }
    const next = { state: structuredClone(state), etag: `memory-${this.entries.size + this.writeCalls.length}` };
    this.entries.set(key, next);
    return next;
  }
}

class MemoryTripEventStorage {
  events = new Map();

  async listTripIds() {
    return [...this.events.keys()];
  }

  async list(tripId) {
    return structuredClone(this.events.get(tripId) ?? []);
  }

  async append(event, expectedRevision) {
    const events = this.events.get(event.tripId) ?? [];
    if (events.length !== expectedRevision) throw new TripStorageConflictError();
    events.push(structuredClone(event));
    this.events.set(event.tripId, events);
  }

  addTrip(id, kind, members) {
    this.events.set(id, [
      {
        id: `${id}-created`,
        tripId: id,
        revision: 1,
        occurredAt: '2026-07-29T12:00:00.000Z',
        actorUserId: members[0].userId,
        type: 'tripCreated',
        payload: {
          name: id,
          kind,
          transportMode: 'automobile',
          ownerUserId: members[0].userId,
          stops: [],
        },
      },
      ...members.slice(1).map((member, index) => ({
        id: `${id}-member-${index}`,
        tripId: id,
        revision: index + 2,
        occurredAt: `2026-07-29T12:00:0${index + 1}.000Z`,
        actorUserId: members[0].userId,
        type: 'memberAdded',
        payload: member,
      })),
    ]);
  }
}

class AlwaysConflictingPublishedStateStorage extends MemoryPublishedStateStorage {
  async write() {
    this.writeCalls.push('forced-conflict');
    throw new Error('private_blob_conflict');
  }
}

const tripId = 'published-state-check';
const resource = 'shared-journal';
const initialState = {
  schemaVersion: 1,
  tripId,
  revision: 1,
  updatedAt: '2026-07-29T12:00:00.000Z',
  updatedBy: 'owner-1',
  data: { entries: ['İstanbul’dan yola çıktık'] },
};

const memoryStorage = new MemoryPublishedStateStorage();
const created = await memoryStorage.write(tripId, resource, initialState, null);
assert.deepEqual(memoryStorage.writeCalls, [null], 'creates must use a null expected ETag');
await assert.rejects(
  memoryStorage.write(tripId, resource, { ...initialState, revision: 2 }, 'stale-etag'),
  /private_blob_conflict/,
  'stale ETags must reject replacement',
);
const replacement = await memoryStorage.write(
  tripId,
  resource,
  { ...initialState, revision: 2, updatedAt: '2026-07-29T12:05:00.000Z' },
  created.etag,
);
assert.equal(replacement.state.revision, 2, 'successful replacements must persist the next revision');
assert.equal(JSON.stringify(replacement.state).includes('etag'), false, 'API state projections must not expose ETags');

const tripStorage = new MemoryTripEventStorage();
tripStorage.addTrip('kuzey-public', 'kuzey2026', [
  { userId: 'owner-1', role: 'owner' },
  { userId: 'member-1', role: 'member' },
  { userId: 'viewer-1', role: 'viewer' },
]);
tripStorage.addTrip('standard-private', 'standard', [{ userId: 'owner-1', role: 'owner' }]);
tripStorage.addTrip('other-public', 'kuzey2026', [{ userId: 'other-owner', role: 'owner' }]);

const ownerAuth = {
  actor: { userId: 'owner-1', globalRole: 'user' },
  account: { id: 'owner-1', displayName: 'Owner Name' },
  sessionId: 'owner-session',
};
const memberAuth = {
  actor: { userId: 'member-1', globalRole: 'user' },
  account: { id: 'member-1', displayName: 'Member Name' },
  sessionId: 'member-session',
};
const viewerAuth = {
  actor: { userId: 'viewer-1', globalRole: 'user' },
  account: { id: 'viewer-1', displayName: 'Viewer Name' },
  sessionId: 'viewer-session',
};
let clockTick = 0;
const repositoryStorage = new MemoryPublishedStateStorage();
const deps = {
  tripStorage,
  publishedStateStorage: repositoryStorage,
  now: () => `2026-07-29T13:00:${String(clockTick++).padStart(2, '0')}.000Z`,
};

const validInputs = {
  'live-location': { lat: 41.01, lng: 28.97, speedKmh: 80, city: 'İstanbul', ts: '2026-07-29T12:30:00Z' },
  'expense-summary': { totalEur: 12.5, count: 1, byCategory: { fuel: 12.5 }, ts: '2026-07-29T12:30:00Z' },
  'published-plan': {
    departureAt: '2026-07-30T05:00:00Z',
    arrivalAt: '2026-08-01T18:00:00Z',
    totalDays: 2,
    days: [{ slug: 'day-1', date: '2026-07-30T05:00:00Z', origin: 'İstanbul', destination: 'Sofia' }],
  },
  'shared-journal': {
    entries: [{ id: 'entry-1', text: 'Yola çıktık', createdAt: '2026-07-29T12:30:00Z', author: 'Client Forgery' }],
  },
};

for (const [name, input] of Object.entries(validInputs)) {
  await assert.rejects(
    putPublishedResource(deps, viewerAuth, 'kuzey-public', name, input),
    (error) => error?.code === 'forbidden',
    `viewers must not write ${name}`,
  );
}

await assert.rejects(
  putPublishedResource(deps, memberAuth, 'kuzey-public', 'live-location', validInputs['live-location']),
  (error) => error?.code === 'forbidden',
  'live location requires startRoute permission',
);
await assert.rejects(
  putPublishedResource(deps, memberAuth, 'kuzey-public', 'published-plan', validInputs['published-plan']),
  (error) => error?.code === 'forbidden',
  'published plan requires editTrip permission',
);

const unsupportedResourceStorage = new MemoryPublishedStateStorage();
const unsupportedResourceDeps = { ...deps, publishedStateStorage: unsupportedResourceStorage };
for (const inheritedResource of ['toString', '__proto__', 'constructor']) {
  await assert.rejects(
    putPublishedResource(
      unsupportedResourceDeps,
      ownerAuth,
      'kuzey-public',
      inheritedResource,
      validInputs['shared-journal'],
    ),
    (error) => error?.code === 'trip_not_found',
    `inherited resource ${inheritedResource} must be rejected by the explicit allowlist`,
  );
}
assert.deepEqual(unsupportedResourceStorage.readCalls, [], 'unsupported resources are rejected before state reads');
assert.deepEqual(unsupportedResourceStorage.writeCalls, [], 'unsupported resources are rejected before state writes');

await putPublishedResource(deps, ownerAuth, 'kuzey-public', 'live-location', {
  ...validInputs['live-location'],
  tripId: 'other-public',
});
assert.ok(repositoryStorage.entries.has('kuzey-public:live-location'), 'the repository trip argument selects storage');
assert.equal(
  repositoryStorage.entries.has('other-public:live-location'),
  false,
  'a body tripId cannot select another trip',
);
assert.equal(repositoryStorage.entries.get('kuzey-public:live-location').state.tripId, 'kuzey-public');

await repositoryStorage.write(
  'standard-private',
  'live-location',
  {
    schemaVersion: 1,
    tripId: 'standard-private',
    revision: 1,
    updatedAt: '2026-07-29T12:30:00.000Z',
    updatedBy: 'owner-1',
    data: validInputs['live-location'],
  },
  null,
);
await assert.rejects(
  getPublicPublishedResource(deps, 'standard-private', 'live-location'),
  (error) => error?.code === 'trip_not_found',
  'standard trip state must never be public',
);
await assert.rejects(
  putPublishedResource(deps, ownerAuth, 'standard-private', 'expense-summary', validInputs['expense-summary']),
  (error) => error?.code === 'trip_not_found',
  'standard trips must not receive published resource payloads',
);
assert.equal(
  repositoryStorage.entries.has('standard-private:expense-summary'),
  false,
  'a rejected standard-trip publish must not persist state',
);
await assert.rejects(
  getPublicPublishedResource(deps, 'kuzey-public', 'plan-edits'),
  (error) => error?.code === 'trip_not_found',
  'plan edits must never be public',
);

assert.deepEqual(
  await getPlanEdits(deps, memberAuth.actor, 'kuzey-public'),
  { revision: 0, departureAt: null, days: {}, updatedAt: null },
  'missing plan edits have an explicit revision-zero projection',
);
const planOne = await putPlanEdits(deps, memberAuth.actor, 'kuzey-public', {
  baseRevision: 0,
  departureAt: '2026-07-30T05:00:00Z',
  days: { 'day-1': { destination: 'Sofia' } },
  tripId: 'other-public',
});
assert.equal(planOne.revision, 1);
assert.equal(
  repositoryStorage.entries.has('other-public:plan-edits'),
  false,
  'plan bodies cannot override the URL trip',
);
await assert.rejects(
  putPlanEdits(deps, memberAuth.actor, 'kuzey-public', {
    baseRevision: 0,
    departureAt: null,
    days: {},
  }),
  (error) =>
    error?.code === 'revision_conflict' &&
    error?.current?.revision === 1 &&
    error?.current?.departureAt === '2026-07-30T05:00:00.000Z',
  'stale plan writes must immediately include current projected state',
);

const currentDayEdit = {
  origin: 'İstanbul',
  destination: 'Sofia',
  distanceKm: '550 km',
  duration: '7 sa',
  fuel: '55 L',
  note: 'Sınırda mola',
  campName: 'Sofia Camp',
  campPlace: 'Sofia',
  arrivalTarget: {
    id: 'target-1',
    mapItemIdentifier: 'map-1',
    name: 'Sofia Camp',
    kind: 'campground',
    latitude: 42.66,
    longitude: 23.28,
    formattedAddress: 'Sofia, Bulgaria',
    maximumLengthMeters: 8.5,
    source: 'appleMaps',
    updatedAt: '2026-07-29T12:00:00Z',
  },
  stayDetails: {
    checkIn: '2026-07-30T12:00:00Z',
    checkOut: '2026-07-31T08:00:00Z',
    reservationStatus: 'confirmed',
    estimatedArrival: '18:30',
    estimatedArrivalMode: 'manual',
    estimatedArrivalWindow: {
      start: '2026-07-30T15:00:00Z',
      end: '2026-07-30T16:00:00Z',
      timeZoneIdentifier: 'Europe/Sofia',
    },
  },
  isRestDay: false,
  extraDays: 1,
  startHour: 7,
  subplans: [
    {
      id: 'subplan-1',
      title: 'Akşam yürüyüşü',
      placeName: 'Sofia',
      latitude: 42.69,
      longitude: 23.32,
      startMinute: 1_080,
      durationMinutes: 60,
      note: 'Merkez',
    },
  ],
};
const planTwo = await putPlanEdits(deps, memberAuth.actor, 'kuzey-public', {
  baseRevision: 1,
  departureAt: '2026-07-30T05:00:00Z',
  days: { 'day-1': currentDayEdit },
});
assert.equal(planTwo.revision, 2, 'the current Swift DayEdit payload remains valid');
assert.equal(planTwo.days['day-1'].arrivalTarget.kind, 'campground');
assert.equal(planTwo.days['day-1'].subplans[0].startMinute, 1_080);

const assertInvalidPlanEdits = async (days, message) => {
  await assert.rejects(
    putPlanEdits(deps, memberAuth.actor, 'kuzey-public', {
      baseRevision: 2,
      departureAt: null,
      days,
    }),
    (error) => error?.code === 'invalid_published_state',
    message,
  );
};

await assertInvalidPlanEdits(
  { 'day-deep': { note: { nested: { deeper: { payload: 'x' } } } } },
  'plan edits reject nested values outside the concrete DayEdit shape',
);
await assertInvalidPlanEdits({ 'day-string': { note: 'x'.repeat(5_001) } }, 'plan edits reject huge strings');
await assertInvalidPlanEdits(
  {
    'day-array': {
      subplans: Array.from({ length: 65 }, (_, index) => ({ ...currentDayEdit.subplans[0], id: `sub-${index}` })),
    },
  },
  'plan edits reject huge arrays',
);
await assertInvalidPlanEdits(
  { 'day-keys': Object.fromEntries(Array.from({ length: 65 }, (_, index) => [`field-${index}`, index])) },
  'plan edits reject huge key sets',
);
await assertInvalidPlanEdits(
  {
    'day-bytes': {
      subplans: Array.from({ length: 64 }, (_, index) => ({
        ...currentDayEdit.subplans[0],
        id: `sub-${index}`,
        note: 'x'.repeat(1_000),
      })),
    },
  },
  'plan edits reject a single oversized serialized day',
);
await assertInvalidPlanEdits(
  Object.fromEntries(Array.from({ length: 60 }, (_, index) => [`day-${index}`, { note: 'x'.repeat(5_000) }])),
  'plan edits reject an oversized serialized days collection even when each day is valid',
);

const assertInvalid = async (resourceName, input, message) => {
  await assert.rejects(
    putPublishedResource(deps, ownerAuth, 'kuzey-public', resourceName, input),
    (error) => error?.code === 'invalid_published_state',
    message,
  );
};

await assertInvalid('live-location', { ...validInputs['live-location'], lat: 90.01 }, 'latitude must be in range');
await assertInvalid('live-location', { ...validInputs['live-location'], lng: -180.01 }, 'longitude must be in range');
await assertInvalid(
  'expense-summary',
  { ...validInputs['expense-summary'], totalEur: -0.01 },
  'expense totals are nonnegative',
);
await assertInvalid(
  'expense-summary',
  { ...validInputs['expense-summary'], totalEur: Infinity },
  'expense totals are finite',
);
await assertInvalid(
  'expense-summary',
  { ...validInputs['expense-summary'], totalEur: Number.MAX_VALUE },
  'huge finite expense totals are rejected before currency rounding can overflow',
);
await assertInvalid(
  'expense-summary',
  { ...validInputs['expense-summary'], byCategory: { fuel: Number.MAX_VALUE } },
  'huge finite category totals are rejected before currency rounding can overflow',
);
await assertInvalid(
  'expense-summary',
  {
    ...validInputs['expense-summary'],
    byCategory: Object.fromEntries(Array.from({ length: 33 }, (_, index) => [`category-${index}`, 1])),
  },
  'expense summaries accept no more than 32 category keys',
);
await assertInvalid(
  'expense-summary',
  {
    ...validInputs['expense-summary'],
    byCategory: { fuel: -1 },
  },
  'expense category values are nonnegative',
);
await assertInvalid(
  'published-plan',
  {
    ...validInputs['published-plan'],
    days: Array.from({ length: 61 }, (_, index) => ({ slug: `day-${index}`, date: '2026-07-30T05:00:00Z' })),
  },
  'published plans accept no more than 60 days',
);
await assert.rejects(
  putPlanEdits(deps, ownerAuth.actor, 'kuzey-public', {
    baseRevision: 1,
    departureAt: null,
    days: Object.fromEntries(Array.from({ length: 61 }, (_, index) => [`day-${index}`, {}])),
  }),
  (error) => error?.code === 'invalid_published_state',
  'plan edits accept no more than 60 day keys',
);
await assertInvalid(
  'shared-journal',
  {
    entries: Array.from({ length: 251 }, (_, index) => ({
      id: `entry-${index}`,
      text: 'x',
      createdAt: '2026-07-29T12:30:00Z',
    })),
  },
  'journals accept no more than 250 entries',
);
await assertInvalid(
  'shared-journal',
  {
    entries: [{ id: 'x'.repeat(201), text: 'x', createdAt: '2026-07-29T12:30:00Z' }],
  },
  'journal IDs are bounded',
);
await assertInvalid(
  'shared-journal',
  {
    entries: [{ id: 'x', text: 'x'.repeat(5001), createdAt: '2026-07-29T12:30:00Z' }],
  },
  'journal text is bounded',
);
await assertInvalid(
  'shared-journal',
  {
    entries: [{ id: 'x', text: 'x', createdAt: 'not-a-date' }],
  },
  'journal dates must be valid ISO timestamps',
);
await assertInvalid(
  'shared-journal',
  {
    entries: [{ id: 'x', text: 'x', createdAt: '2026-02-31T12:30:00Z' }],
  },
  'ISO-shaped but impossible calendar dates must be rejected',
);

const raceStorage = new MemoryPublishedStateStorage();
raceStorage.synchronizeReads('expense-summary', 2);
const raceDeps = { ...deps, publishedStateStorage: raceStorage };
const expenseRace = await Promise.all([
  putPublishedResource(raceDeps, ownerAuth, 'kuzey-public', 'expense-summary', {
    totalEur: 10,
    count: 1,
    byCategory: { fuel: 10 },
    ts: '2026-07-29T12:31:00Z',
  }),
  putPublishedResource(raceDeps, memberAuth, 'kuzey-public', 'expense-summary', {
    totalEur: 5,
    count: 2,
    byCategory: { food: 5 },
    ts: '2026-07-29T12:32:00Z',
  }),
]);
assert.deepEqual(
  expenseRace.map((result) => result.ok),
  [true, true],
);
assert.equal(raceStorage.conflictCount, 1, 'the contribution race must force one precondition failure');
assert.deepEqual(
  await getPublicPublishedResource(raceDeps, 'kuzey-public', 'expense-summary'),
  {
    totalEur: 15,
    count: 3,
    byCategory: { food: 5, fuel: 10 },
    ts: '2026-07-29T12:32:00.000Z',
    receivedAt: expenseRace[1].updatedAt,
  },
  'CAS retry must preserve and aggregate both account contributions',
);
assert.equal(
  JSON.stringify(await getPublicPublishedResource(raceDeps, 'kuzey-public', 'expense-summary')).includes('owner-1'),
  false,
  'public expenses must not reveal contribution account IDs',
);

const prototypeCategoryStorage = new MemoryPublishedStateStorage();
const prototypeCategoryDeps = { ...deps, publishedStateStorage: prototypeCategoryStorage };
await putPublishedResource(prototypeCategoryDeps, ownerAuth, 'kuzey-public', 'expense-summary', {
  totalEur: 5,
  count: 1,
  byCategory: JSON.parse('{"toString":2,"__proto__":3}'),
  ts: '2026-07-29T12:31:00Z',
});
const inheritedCategories = Object.create({ inherited: 999 });
inheritedCategories.toString = 4;
Object.defineProperty(inheritedCategories, '__proto__', { value: 5, enumerable: true });
await putPublishedResource(prototypeCategoryDeps, memberAuth, 'kuzey-public', 'expense-summary', {
  totalEur: 9,
  count: 2,
  byCategory: inheritedCategories,
  ts: '2026-07-29T12:32:00Z',
});
const prototypeCategoryProjection = await getPublicPublishedResource(
  prototypeCategoryDeps,
  'kuzey-public',
  'expense-summary',
);
assert.equal(prototypeCategoryProjection.totalEur, 14);
assert.equal(prototypeCategoryProjection.byCategory.toString, 6, 'toString is aggregated as an own category');
assert.equal(prototypeCategoryProjection.byCategory.__proto__, 8, '__proto__ is aggregated as an own category');
assert.equal(Object.hasOwn(prototypeCategoryProjection.byCategory, '__proto__'), true);
assert.equal(
  Object.hasOwn(prototypeCategoryProjection.byCategory, 'inherited'),
  false,
  'inherited categories are ignored',
);
assert.equal(
  Object.values(prototypeCategoryProjection.byCategory).every(Number.isFinite),
  true,
  'prototype-like category totals remain finite',
);

const cumulativeExpenseStorage = new MemoryPublishedStateStorage();
const cumulativeExpenseDeps = { ...deps, publishedStateStorage: cumulativeExpenseStorage };
const largeSafeExpense = {
  totalEur: 60_000_000_000_000,
  count: 1,
  byCategory: { fuel: 60_000_000_000_000 },
  ts: '2026-07-29T12:31:00Z',
};
await putPublishedResource(cumulativeExpenseDeps, ownerAuth, 'kuzey-public', 'expense-summary', largeSafeExpense);
await assert.rejects(
  putPublishedResource(cumulativeExpenseDeps, memberAuth, 'kuzey-public', 'expense-summary', largeSafeExpense),
  (error) => error?.code === 'invalid_published_state',
  'a contribution that makes the aggregate exceed the safe amount ceiling is rejected',
);
assert.equal(
  (await getPublicPublishedResource(cumulativeExpenseDeps, 'kuzey-public', 'expense-summary')).totalEur,
  60_000_000_000_000,
  'a rejected cumulative overflow leaves the prior finite aggregate intact',
);

const alwaysConflictingStorage = new AlwaysConflictingPublishedStateStorage();
await assert.rejects(
  putPublishedResource(
    { ...deps, publishedStateStorage: alwaysConflictingStorage },
    ownerAuth,
    'kuzey-public',
    'expense-summary',
    validInputs['expense-summary'],
  ),
  (error) => error?.code === 'revision_conflict',
  'an exhausted non-plan merge reports a repository conflict',
);
assert.equal(alwaysConflictingStorage.writeCalls.length, 3, 'non-plan CAS writes stop after three attempts');

await putPublishedResource(deps, memberAuth, 'kuzey-public', 'shared-journal', validInputs['shared-journal']);
await putPublishedResource(deps, ownerAuth, 'kuzey-public', 'shared-journal', {
  entries: [{ id: 'entry-2', text: 'İkinci kayıt', createdAt: '2026-07-29T12:31:00Z', author: 'Another Forgery' }],
});
const journal = await getPublicPublishedResource(deps, 'kuzey-public', 'shared-journal');
assert.deepEqual(
  journal.entries.map((entry) => [entry.id, entry.author]),
  [
    ['entry-2', 'Owner Name'],
    ['entry-1', 'Member Name'],
  ],
  'journal contributions from both accounts survive and use server-authored display names',
);
assert.equal(JSON.stringify(journal).includes('Client Forgery'), false, 'client journal authors are ignored');
assert.equal(JSON.stringify(journal).includes('Another Forgery'), false, 'all client journal authors are ignored');
assert.equal(JSON.stringify(journal).includes('member-1'), false, 'public journals do not reveal account IDs');

const vite = await createServer({
  root: process.cwd(),
  configFile: false,
  appType: 'custom',
  logLevel: 'silent',
  server: { middlewareMode: true },
});
try {
  const routeStorage = new MemoryPublishedStateStorage();
  const routeDependencies = {
    tripStorage,
    publishedStateStorage: routeStorage,
    now: () => '2026-07-29T14:00:00.000Z',
  };
  const routeInputs = {
    'live-location': validInputs['live-location'],
    'expense-summary': validInputs['expense-summary'],
    'plan-edits': { baseRevision: 0, departureAt: null, days: {} },
    'published-plan': validInputs['published-plan'],
    'shared-journal': validInputs['shared-journal'],
  };

  for (const { resource, methods } of v2PublishedStateRoutes) {
    const route = await vite.ssrLoadModule(`/src/pages/api/v2/trips/[id]/${resource}.ts`);
    const handlers = route.createHandlers({
      authenticateRequest: async () => ownerAuth,
      errorResponse,
      json,
      requestJSON,
      repositoryDependencies: routeDependencies,
    });
    const targetTripId = 'kuzey-public';
    const forgedTripId = 'other-public';
    const put = await handlers.PUT({
      request: new Request(`https://test.invalid/api/v2/trips/${targetTripId}/${resource}`, {
        method: 'PUT',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ ...routeInputs[resource], tripId: forgedTripId }),
      }),
      params: { id: targetTripId },
    });
    assert.equal(put.status, 200, `${resource} accepts authenticated PUT requests`);
    assert.equal(put.headers.get('cache-control'), 'no-store', `${resource} PUT responses must not be cached`);
    assert.ok(
      routeStorage.entries.has(`${targetTripId}:${resource}`),
      `${resource} uses params.id for storage selection`,
    );
    assert.equal(
      routeStorage.entries.has(`${forgedTripId}:${resource}`),
      false,
      `${resource} ignores a forged body tripId`,
    );

    const malformed = await handlers.PUT({
      request: new Request(`https://test.invalid/api/v2/trips/${targetTripId}/${resource}`, {
        method: 'PUT',
        body: '{',
      }),
      params: { id: targetTripId },
    });
    assert.equal(malformed.status, 400, `${resource} rejects malformed JSON`);
    assert.equal(malformed.headers.get('cache-control'), 'no-store', `${resource} error responses must not be cached`);

    const unauthenticated = route.createHandlers({
      authenticateRequest: async () => {
        throw new UnauthorizedError();
      },
      errorResponse,
      json,
      requestJSON,
      repositoryDependencies: routeDependencies,
    });
    const denied = await unauthenticated.PUT({
      request: new Request(`https://test.invalid/api/v2/trips/${targetTripId}/${resource}`, {
        method: 'PUT',
        body: '{}',
      }),
      params: { id: targetTripId },
    });
    assert.equal(denied.status, 401, `${resource} authenticates before publishing state`);

    if (!methods.includes('GET')) continue;
    const get = await handlers.GET({
      request: new Request(`https://test.invalid/api/v2/trips/${targetTripId}/${resource}`),
      params: { id: targetTripId },
    });
    assert.equal(get.status, 200, 'plan-edits GET requires authentication and returns the projected state');
    assert.equal(get.headers.get('cache-control'), 'no-store', 'plan-edits GET responses must not be cached');
    assert.equal((await get.json()).revision, 1, 'plan-edits GET returns the latest revision after PUT');
    const deniedGet = await unauthenticated.GET({
      request: new Request(`https://test.invalid/api/v2/trips/${targetTripId}/${resource}`),
      params: { id: targetTripId },
    });
    assert.equal(deniedGet.status, 401, 'plan-edits GET authenticates before reading state');
  }

  const legacyPublicKeys = {
    'live-location': [
      'activeRouteCode',
      'activeRouteStartedAt',
      'activeRouteStop',
      'altitudeAvailable',
      'altitudeKind',
      'altitudeMeters',
      'altitudeSource',
      'city',
      'journeyStarted',
      'lat',
      'legProgress',
      'lng',
      'nextFlag',
      'nextStop',
      'pressureHpa',
      'receivedAt',
      'remainingKm',
      'remainingMin',
      'remainingToFinalKm',
      'speedKmh',
      'traveledKm',
      'ts',
    ],
    'expense-summary': ['byCategory', 'count', 'receivedAt', 'totalEur', 'ts'],
    'published-plan': ['arrivalAt', 'days', 'departureAt', 'receivedAt', 'totalDays'],
    'shared-journal': ['entries', 'updatedAt'],
  };
  const publicApi = await vite.ssrLoadModule('/src/accounts/api.ts');

  for (const resource of publicPublishedStateRoutes) {
    const route = await vite.ssrLoadModule(`/src/pages/api/v2/public/trips/[id]/${resource}.ts`);
    const handlers = route.createHandlers({
      errorResponse: publicApi.errorResponse,
      json: publicApi.json,
      repositoryDependencies: routeDependencies,
    });
    const response = await handlers.GET({
      request: new Request(`https://test.invalid/api/v2/public/trips/kuzey-public/${resource}`),
      params: { id: 'kuzey-public' },
    });
    assert.equal(response.status, 200, `${resource} is available without an authenticated request`);
    assert.equal(response.headers.get('cache-control'), 'no-store', `${resource} public responses must not be cached`);
    const body = await response.json();
    assert.deepEqual(
      Object.keys(body).sort(),
      legacyPublicKeys[resource],
      `${resource} keeps its legacy response shape`,
    );
    assert.deepEqual(
      body,
      await getPublicPublishedResource(routeDependencies, 'kuzey-public', resource),
      `${resource} handler returns the public repository projection without an envelope`,
    );
    assert.equal(
      /(?:contributions|owner-1|member-1|schemaVersion|tripId|revision|updatedBy|etag)/.test(JSON.stringify(body)),
      false,
      `${resource} public response must not expose private storage metadata or contribution account IDs`,
    );
  }

  const publicLiveLocation = await vite.ssrLoadModule('/src/pages/api/v2/public/trips/[id]/live-location.ts');
  const publicHandlers = publicLiveLocation.createHandlers({
    errorResponse: publicApi.errorResponse,
    json: publicApi.json,
    repositoryDependencies: routeDependencies,
  });
  for (const deniedTripId of ['other-public', 'standard-private', 'missing-trip']) {
    const response = await publicHandlers.GET({
      request: new Request(`https://test.invalid/api/v2/public/trips/${deniedTripId}/live-location`),
      params: { id: deniedTripId },
    });
    assert.equal(response.status, 404, `${deniedTripId} public state must be hidden as not found`);
    assert.equal(response.headers.get('cache-control'), 'no-store', `${deniedTripId} 404 responses must not be cached`);
  }

  const { BlobPublishedStateStorage } = await vite.ssrLoadModule('/src/accounts/blobPublishedStateStorage.ts');
  const { PrivateBlobConflictError, listPrivatePaths } = await vite.ssrLoadModule('/src/accounts/privateBlob.ts');
  const storage = new BlobPublishedStateStorage();
  const localTripId = `${tripId}-local`;
  const localInitialState = { ...initialState, tripId: localTripId };
  const localCreated = await storage.write(localTripId, resource, localInitialState, null);
  assert.deepEqual(
    await listPrivatePaths(`accounts/trips/${localTripId}/state/`),
    [`accounts/trips/${localTripId}/state/${resource}.json`],
    'production storage must use the private published-state path',
  );
  const localRead = await storage.read(localTripId, resource);
  assert.deepEqual(localRead?.state, localInitialState, 'production storage must read its locally persisted envelope');
  assert.equal(JSON.stringify(localRead?.state).includes('etag'), false, 'read API projections must not expose ETags');
  const contenders = await Promise.allSettled([
    storage.write(localTripId, resource, { ...localInitialState, revision: 2 }, localCreated.etag),
    storage.write(localTripId, resource, { ...localInitialState, revision: 2 }, localCreated.etag),
  ]);
  assert.equal(
    contenders.filter((result) => result.status === 'fulfilled').length,
    1,
    'one writer must win the stale-ETag race',
  );
  assert.equal(
    contenders.filter((result) => result.status === 'rejected').length,
    1,
    'one writer must conflict in the stale-ETag race',
  );
  const winner = contenders.find((result) => result.status === 'fulfilled');
  const loser = contenders.find((result) => result.status === 'rejected');
  assert.notEqual(winner.value.etag, localCreated.etag, 'each successful local write must produce a new opaque ETag');
  assert.ok(loser.reason instanceof PrivateBlobConflictError, 'stale writes must become private-blob conflicts');
} finally {
  await vite.close();
}
