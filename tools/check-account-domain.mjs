import assert from 'node:assert/strict';
import {
  can,
  featuresFor,
  foldTripEvents,
  normalizeEmail,
  resolveGlobalRole,
} from '../src/accounts/domain.ts';

assert.equal(normalizeEmail('  SENTURK.BILAL@ICLOUD.COM '), 'senturk.bilal@icloud.com');
assert.equal(resolveGlobalRole('senturk.bilal@icloud.com'), 'globalAdmin');
assert.equal(resolveGlobalRole('senturk.leyla@icloud.com'), 'user');

assert.equal(can({ globalRole: 'globalAdmin', tripRole: null }, 'manageMembers'), true);
assert.equal(can({ globalRole: 'user', tripRole: 'owner' }, 'manageMembers'), true);
assert.equal(can({ globalRole: 'user', tripRole: 'member' }, 'editStops'), true);
assert.equal(can({ globalRole: 'user', tripRole: 'member' }, 'editJournal'), true);
assert.equal(can({ globalRole: 'user', tripRole: 'member' }, 'startRoute'), false);
assert.equal(can({ globalRole: 'user', tripRole: 'viewer' }, 'read'), true);
assert.equal(can({ globalRole: 'user', tripRole: 'viewer' }, 'editStops'), false);
assert.equal(can({ globalRole: 'user', tripRole: null }, 'read'), false);

assert.deepEqual(featuresFor('standard'), {
  latvian: false,
  kuzeyMusic: false,
  publicTracking: false,
});
assert.deepEqual(featuresFor('kuzey2026'), {
  latvian: true,
  kuzeyMusic: true,
  publicTracking: true,
});

const trip = foldTripEvents([
  {
    id: 'e1',
    tripId: 'trip-1',
    revision: 1,
    occurredAt: '2026-07-26T07:00:00.000Z',
    actorUserId: 'user-1',
    type: 'tripCreated',
    payload: {
      name: 'Balkan Rotası',
      kind: 'standard',
      ownerUserId: 'user-1',
    },
  },
  {
    id: 'e2',
    tripId: 'trip-1',
    revision: 2,
    occurredAt: '2026-07-26T07:01:00.000Z',
    actorUserId: 'user-1',
    type: 'stopAdded',
    payload: {
      stop: { id: 'istanbul', name: 'İstanbul', lat: 41.01, lng: 28.97, order: 0 },
    },
  },
  {
    id: 'e3',
    tripId: 'trip-1',
    revision: 3,
    occurredAt: '2026-07-26T07:02:00.000Z',
    actorUserId: 'user-1',
    type: 'stopAdded',
    payload: {
      stop: { id: 'sofia', name: 'Sofya', lat: 42.69, lng: 23.32, order: 1, note: 'İlk gece' },
    },
  },
  {
    id: 'e4',
    tripId: 'trip-1',
    revision: 4,
    occurredAt: '2026-07-26T07:03:00.000Z',
    actorUserId: 'user-1',
    type: 'stopUpdated',
    payload: { stopId: 'sofia', changes: { note: 'Kamp alanı' } },
  },
]);

assert.equal(trip.id, 'trip-1');
assert.equal(trip.name, 'Balkan Rotası');
assert.equal(trip.kind, 'standard');
assert.equal(trip.revision, 4);
assert.deepEqual(trip.stops.map((stop) => stop.id), ['istanbul', 'sofia']);
assert.equal(trip.stops[1].note, 'Kamp alanı');
assert.deepEqual(trip.members, [{ userId: 'user-1', role: 'owner' }]);

assert.throws(
  () => foldTripEvents([{ ...tripEvent('tripCreated', 1), payload: { name: '', kind: 'standard', ownerUserId: 'u1' } }]),
  /trip_name_required/,
);

function tripEvent(type, revision) {
  return {
    id: `event-${revision}`,
    tripId: 'trip-x',
    revision,
    occurredAt: '2026-07-26T07:00:00.000Z',
    actorUserId: 'u1',
    type,
    payload: {},
  };
}

console.log('Account domain checks passed.');
