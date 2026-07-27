/* global structuredClone */

import assert from 'node:assert/strict';
import {
  createTrip,
  getTripForUser,
  inviteMember,
  mutateTrip,
} from '../src/accounts/tripRepository.ts';

class MemoryTripEventStorage {
  events = new Map();

  async listTripIds() {
    return [...this.events.keys()];
  }

  async list(tripId) {
    return [...(this.events.get(tripId) ?? [])];
  }

  async append(event) {
    const items = this.events.get(event.tripId) ?? [];
    items.push(structuredClone(event));
    this.events.set(event.tripId, items);
  }
}

const storage = new MemoryTripEventStorage();
const owner = { userId: 'owner-1', globalRole: 'user' };
const created = await createTrip(storage, owner, {
  name: 'Balkan Yazı',
  transportMode: 'walking',
  stops: [
    { id: 'start', name: 'Konumum', lat: 41.01, lng: 28.97, order: 0, source: 'currentLocation' },
    { id: 'finish', name: 'Sofya', lat: 42.69, lng: 23.32, order: 1 },
  ],
});

assert.equal(created.kind, 'standard', 'new users cannot create a Kuzey-special trip');
assert.equal(created.transportMode, 'walking', 'trip keeps its transport mode');
assert.equal(created.revision, 3);
assert.equal(created.members[0].role, 'owner');
assert.equal(created.stops[0].source, 'currentLocation', 'current location remains semantic');

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

const stranger = { userId: 'stranger', globalRole: 'user' };
await assert.rejects(getTripForUser(storage, stranger, created.id), /forbidden/);

const admin = { userId: 'admin', globalRole: 'globalAdmin' };
const adminView = await getTripForUser(storage, admin, created.id);
assert.equal(adminView.access.canManageMembers, true);

console.log('Trip repository checks passed.');
