/* global structuredClone */

import assert from 'node:assert/strict';
import { createServer } from 'vite';
import {
  createTrip,
  getTripForUser,
  inviteMember,
  mutateTrip,
  TripStorageConflictError,
} from '../src/accounts/tripRepository.ts';
import * as tripRepository from '../src/accounts/tripRepository.ts';

class MemoryTripEventStorage {
  events = new Map();

  async listTripIds() {
    return [...this.events.keys()];
  }

  async list(tripId) {
    return [...(this.events.get(tripId) ?? [])];
  }

  async append(event, expectedRevision) {
    const items = this.events.get(event.tripId) ?? [];
    if (event.revision !== expectedRevision + 1 || items.some((item) => item.revision === event.revision)) {
      throw new TripStorageConflictError('revision_conflict');
    }
    items.push(structuredClone(event));
    this.events.set(event.tripId, items);
  }

  totalEvents() {
    return [...this.events.values()].reduce((total, events) => total + events.length, 0);
  }
}

const storage = new MemoryTripEventStorage();
const owner = { userId: 'owner-1', globalRole: 'user' };
const created = await createTrip(storage, owner, {
  name: 'Balkan Yazı',
  transportMode: 'walking',
  stops: [
    { id: 'start', name: 'Konumum', lat: 41.01, lng: 28.97, order: 7, source: 'currentLocation' },
    { id: 'finish', name: 'Sofya', lat: 42.69, lng: 23.32, order: 3 },
  ],
});

assert.equal(created.kind, 'standard', 'new users cannot create a Kuzey-special trip');
assert.equal(created.transportMode, 'walking', 'trip keeps its transport mode');
const createdEvents = await storage.list(created.id);
assert.equal(createdEvents.length, 1);
const [createdEvent] = createdEvents;
assert.equal(createdEvent.type, 'tripCreated');
assert.equal(createdEvent.revision, 1);
assert.deepEqual(createdEvent.payload.stops.map((stop) => stop.order), [0, 1]);
assert.equal(created.revision, 1);
assert.equal(created.members[0].role, 'owner');
assert.equal(created.stops[0].source, 'currentLocation', 'current location remains semantic');
assert.deepEqual(created.stops.map((stop) => stop.order), [0, 1]);

const vite = await createServer({
  root: process.cwd(),
  configFile: false,
  appType: 'custom',
  logLevel: 'silent',
  server: { middlewareMode: true },
});
try {
  const { BlobTripEventStorage } = await vite.ssrLoadModule('/src/accounts/blobTripStorage.ts');
  const { listPrivatePaths, readPrivateJSON } = await vite.ssrLoadModule('/src/accounts/privateBlob.ts');
  const { TripRepositoryError, TripStorageConflictError: AdapterConflictError } = await vite.ssrLoadModule(
    '/src/accounts/tripRepository.ts',
  );
  const revisionRaceStorage = new BlobTripEventStorage();
  const raceTripId = `atomic-race-${created.id}`;
  const revisionOne = {
    id: 'adapter-revision-one',
    tripId: raceTripId,
    revision: 1,
    occurredAt: '2026-07-29T12:00:00.000Z',
    actorUserId: owner.userId,
    type: 'tripCreated',
    payload: {
      name: 'Atomic storage test',
      kind: 'standard',
      transportMode: 'automobile',
      ownerUserId: owner.userId,
      stops: [],
    },
  };
  await revisionRaceStorage.append(revisionOne, 0);
  const revisionCandidates = [
    {
      ...revisionOne,
      id: 'adapter-revision-two-a',
      revision: 2,
      type: 'tripUpdated',
      payload: { name: 'Writer A' },
    },
    {
      ...revisionOne,
      id: 'adapter-revision-two-b',
      revision: 2,
      type: 'tripUpdated',
      payload: { name: 'Writer B' },
    },
  ];
  await assert.rejects(
    revisionRaceStorage.append(revisionCandidates[0], 0),
    (error) => error instanceof AdapterConflictError && error.code === 'revision_conflict',
  );
  const revisionRace = await Promise.allSettled([
    revisionRaceStorage.append(revisionCandidates[0], 1),
    revisionRaceStorage.append(revisionCandidates[1], 1),
  ]);
  assert.equal(revisionRace.filter((result) => result.status === 'fulfilled').length, 1);
  assert.equal(revisionRace.filter((result) => result.status === 'rejected').length, 1);
  const rejected = revisionRace.find((result) => result.status === 'rejected');
  assert.ok(rejected?.reason instanceof AdapterConflictError);
  assert.ok(rejected.reason instanceof TripRepositoryError);
  assert.equal(rejected.reason.code, 'revision_conflict');
  const winnerIndex = revisionRace.findIndex((result) => result.status === 'fulfilled');
  const winner = revisionCandidates[winnerIndex];
  const eventPrefix = `accounts/trips/${raceTripId}/events/`;
  const revisionOnePath = `${eventPrefix}0000000001.json`;
  const revisionTwoPath = `${eventPrefix}0000000002.json`;
  assert.deepEqual(await listPrivatePaths(eventPrefix), [revisionOnePath, revisionTwoPath]);
  assert.deepEqual(await readPrivateJSON(revisionTwoPath), winner);
  assert.deepEqual(await revisionRaceStorage.list(raceTripId), [revisionOne, winner]);
} finally {
  await vite.close();
}

const assertCreateRejectedWithoutPersistence = async (input, code) => {
  const before = storage.totalEvents();
  await assert.rejects(createTrip(storage, owner, input), (error) => error?.code === code);
  assert.equal(storage.totalEvents(), before, `${code} must not persist an event`);
};

await assertCreateRejectedWithoutPersistence({
  name: 'Bozuk Koordinat', stops: [{ id: 'x', name: 'Hatalı', lat: 120, lng: 29, order: 0 }],
}, 'invalid_stop_coordinates');

await assertCreateRejectedWithoutPersistence({
  name: 'Bozuk', stops: [{ id: 'x', name: '', lat: 41, lng: 29, order: 0 }],
}, 'stop_name_required');

await assertCreateRejectedWithoutPersistence({
  name: 'Tekrarlı Durak',
  stops: [
    { id: 'aynı', name: 'Birinci', lat: 41, lng: 29, order: 0 },
    { id: 'aynı', name: 'İkinci', lat: 42, lng: 30, order: 1 },
  ],
}, 'duplicate_stop');

await assertCreateRejectedWithoutPersistence({
  name: 'Fazla Durak',
  stops: Array.from({ length: 51 }, (_, index) => ({
    id: `stop-${index}`, name: `Durak ${index}`, lat: 41, lng: 29, order: index,
  })),
}, 'too_many_stops');

await assert.rejects(
  createTrip(storage, owner, { name: 'Fake Kuzey', kind: 'kuzey2026', stops: [] }),
  /reserved_trip_kind/,
);
await assert.rejects(
  createTrip(storage, owner, { name: 'Bozuk', transportMode: 'teleport', stops: [] }),
  /invalid_transport_mode/,
);

const invited = await inviteMember(storage, owner, {
  tripId: created.id,
  baseRevision: created.revision,
  email: ' MEMBER@EXAMPLE.COM ',
  role: 'member',
});
assert.deepEqual(invited.invites, [{ email: 'member@example.com', role: 'member' }]);

const memberAdded = await mutateTrip(storage, owner, {
  tripId: created.id,
  baseRevision: invited.revision,
  type: 'memberAdded',
  payload: { userId: 'member-1', role: 'member' },
});

const member = { userId: 'member-1', globalRole: 'user' };
const memberView = await getTripForUser(storage, member, created.id);
assert.equal(memberView.access.tripRole, 'member');
assert.equal(memberView.access.canEditStops, true);
assert.equal(memberView.access.canManageMembers, false);

const stopEdited = await mutateTrip(storage, member, {
  tripId: created.id,
  baseRevision: memberAdded.revision,
  type: 'stopUpdated',
  payload: {
    stopId: 'finish',
    changes: {
      note: 'Merkezde kamp',
      arrivalTarget: {
        id: 'campuccino', name: 'Camping Campuccino', kind: 'campground',
        latitude: 42.66, longitude: 23.28, formattedAddress: 'Sofia, Bulgaria',
        phone: '+359881234567', email: 'hello@example.com', source: 'appleMaps',
        updatedAt: '2026-07-26T07:01:00.000Z',
      },
      stayDetails: { reservationStatus: 'notContacted' },
    },
  },
});
assert.equal(stopEdited.stops[1].note, 'Merkezde kamp');
assert.equal(stopEdited.stops[1].arrivalTarget?.id, 'campuccino');

const routeReplaced = await mutateTrip(storage, member, {
  tripId: created.id,
  baseRevision: stopEdited.revision,
  type: 'stopsReplaced',
  payload: {
    stops: [
      { ...stopEdited.stops[1], order: 0 },
      { ...stopEdited.stops[0], lat: 41.04, lng: 29.03, order: 1 },
      { id: 'third', name: 'Bükreş', lat: 44.43, lng: 26.1, order: 2 },
    ],
  },
});
assert.deepEqual(routeReplaced.stops.map((stop) => stop.id), ['finish', 'start', 'third']);
assert.equal(routeReplaced.stops[1].source, 'currentLocation');
assert.equal(routeReplaced.stops[0].arrivalTarget?.id, 'campuccino');

await assert.rejects(
  inviteMember(storage, member, {
    tripId: created.id,
    baseRevision: routeReplaced.revision,
    email: 'viewer@example.com',
    role: 'viewer',
  }),
  /forbidden/,
);

await assert.rejects(
  mutateTrip(storage, member, {
    tripId: created.id,
    baseRevision: created.revision,
    type: 'stopUpdated',
    payload: { stopId: 'finish', changes: { note: 'Bayat yazma' } },
  }),
  (error) => error?.code === 'revision_conflict' && error?.current?.revision === routeReplaced.revision,
);

const assertMutationRejectedWithoutPersistence = async (operation, code) => {
  const before = storage.totalEvents();
  await assert.rejects(operation(), (error) => error?.code === code);
  assert.equal(storage.totalEvents(), before, `${code} must not persist an event`);
};

await assertMutationRejectedWithoutPersistence(
  () => mutateTrip(storage, owner, {
    tripId: created.id,
    baseRevision: routeReplaced.revision,
    type: 'stopUpdated',
    payload: { stopId: 'finish', changes: { lat: 120 } },
  }),
  'invalid_stop_coordinates',
);

await assertMutationRejectedWithoutPersistence(
  () => mutateTrip(storage, owner, {
    tripId: created.id,
    baseRevision: routeReplaced.revision,
    type: 'stopsReordered',
    payload: { stopIds: ['finish', 'finish', 'third'] },
  }),
  'invalid_stop_order',
);

await assertMutationRejectedWithoutPersistence(
  () => inviteMember(storage, owner, {
    tripId: created.id,
    baseRevision: routeReplaced.revision,
    email: 'member@example.com',
    role: 'member',
  }),
  'duplicate_invite',
);

await assertMutationRejectedWithoutPersistence(
  () => mutateTrip(storage, owner, {
    tripId: created.id,
    baseRevision: routeReplaced.revision,
    type: 'memberRoleChanged',
    payload: { userId: owner.userId, role: 'member' },
  }),
  'last_owner_required',
);

const mutationRace = await Promise.allSettled([
  mutateTrip(storage, owner, {
    tripId: created.id,
    baseRevision: routeReplaced.revision,
    type: 'tripUpdated',
    payload: { name: 'Kazanan A' },
  }),
  mutateTrip(storage, owner, {
    tripId: created.id,
    baseRevision: routeReplaced.revision,
    type: 'tripUpdated',
    payload: { name: 'Kazanan B' },
  }),
]);
assert.equal(mutationRace.filter((result) => result.status === 'fulfilled').length, 1);
assert.equal(mutationRace.filter((result) => result.status === 'rejected').length, 1);
const winningMutation = mutationRace.find((result) => result.status === 'fulfilled').value;
const rejectedMutation = mutationRace.find((result) => result.status === 'rejected').reason;
assert.equal(rejectedMutation?.code, 'revision_conflict');
assert.equal(rejectedMutation?.current?.revision, winningMutation.revision);
assert.equal(rejectedMutation?.current?.name, winningMutation.name);

const inaccessible = await createTrip(storage, { userId: 'other-owner', globalRole: 'user' }, {
  name: 'Özel Seyahat', stops: [],
});
storage.events.set('corrupt-trip', [{
  id: 'corrupt-event',
  tripId: 'corrupt-trip',
  revision: 1,
  occurredAt: '2026-07-29T12:00:00.000Z',
  actorUserId: owner.userId,
  type: 'tripUpdated',
  payload: { name: 'Geçersiz geçmiş' },
}]);
const listedTrips = await tripRepository.listTripsForUser(storage, owner);
assert.deepEqual(listedTrips.map((trip) => trip.id), [created.id]);
await assert.rejects(
  tripRepository.getTripForUser(storage, owner, 'corrupt-trip'),
  (error) => error?.code === 'trip_corrupt',
);
assert.ok(inaccessible.id, 'the unauthorized trip remains present but hidden from this actor');

assert.equal(
  (await tripRepository.getTripForAction(storage, owner, created.id, 'editTrip')).id,
  created.id,
);
await assert.rejects(
  tripRepository.getTripForAction(storage, member, created.id, 'manageMembers'),
  (error) => error?.code === 'forbidden',
);

const bootstrapStorage = new MemoryTripEventStorage();
const bootstrapVite = await createServer({
  root: process.cwd(),
  configFile: false,
  appType: 'custom',
  logLevel: 'silent',
  server: { middlewareMode: true },
});
try {
  const { ensureKuzeyTrip } = await bootstrapVite.ssrLoadModule('/src/accounts/bootstrap.ts');
  await ensureKuzeyTrip(bootstrapStorage);
} finally {
  await bootstrapVite.close();
}
const kuzeyEvents = await bootstrapStorage.list('kuzey-2026');
assert.equal(kuzeyEvents[0].type, 'tripCreated');
assert.ok(Array.isArray(kuzeyEvents[0].payload.stops));
assert.ok(kuzeyEvents[0].payload.stops.length > 0);
assert.equal((await tripRepository.getPublicTrip(bootstrapStorage, 'kuzey-2026')).id, 'kuzey-2026');
await assert.rejects(
  tripRepository.getPublicTrip(storage, created.id),
  (error) => error?.code === 'trip_not_found',
);

const stranger = { userId: 'stranger', globalRole: 'user' };
await assert.rejects(getTripForUser(storage, stranger, created.id), /forbidden/);

const admin = { userId: 'admin', globalRole: 'globalAdmin' };
const adminView = await getTripForUser(storage, admin, created.id);
assert.equal(adminView.access.canManageMembers, true);

console.log('Trip repository checks passed.');
