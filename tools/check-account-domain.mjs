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
      stop: {
        id: 'sofia', name: 'Sofya', lat: 42.69, lng: 23.32, order: 1, note: 'İlk gece',
        arrivalTarget: {
          id: 'campuccino', name: 'Camping Campuccino', kind: 'campground',
          latitude: 42.66, longitude: 23.28, formattedAddress: 'Sofia, Bulgaria',
          phone: '+359881234567', email: 'hello@example.com', source: 'appleMaps',
          maximumLengthMeters: 7.5,
          updatedAt: '2026-07-26T07:01:00.000Z',
        },
        stayDetails: {
          checkIn: '2026-08-03T12:00:00.000Z', checkOut: '2026-08-05T08:00:00.000Z',
          reservationStatus: 'awaitingReply',
          estimatedArrival: '19:00–20:00',
          estimatedArrivalMode: 'manual',
          estimatedArrivalWindow: {
            start: '2026-08-03T16:00:00.000Z',
            end: '2026-08-03T17:00:00.000Z',
            timeZoneIdentifier: 'Europe/Sofia',
          },
        },
      },
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
assert.equal(trip.stops[1].arrivalTarget?.name, 'Camping Campuccino');
assert.equal(trip.stops[1].arrivalTarget?.phone, '+359881234567');
assert.equal(trip.stops[1].arrivalTarget?.maximumLengthMeters, 7.5);
assert.equal(trip.stops[1].stayDetails?.reservationStatus, 'awaitingReply');
assert.equal(trip.stops[1].stayDetails?.estimatedArrivalMode, 'manual');
assert.deepEqual(trip.stops[1].stayDetails?.estimatedArrivalWindow, {
  start: '2026-08-03T16:00:00.000Z',
  end: '2026-08-03T17:00:00.000Z',
  timeZoneIdentifier: 'Europe/Sofia',
});

const roundTrippedTrip = foldTripEvents(JSON.parse(JSON.stringify([
  {
    id: 'roundtrip-1', tripId: 'trip-roundtrip', revision: 1,
    occurredAt: '2026-07-26T07:04:00.000Z', actorUserId: 'user-1', type: 'tripCreated',
    payload: {
      name: 'Round trip', kind: 'standard', ownerUserId: 'user-1',
    },
  },
  {
    id: 'roundtrip-2', tripId: 'trip-roundtrip', revision: 2,
    occurredAt: '2026-07-26T07:05:00.000Z', actorUserId: 'user-1', type: 'stopAdded',
    payload: { stop: trip.stops[1] },
  },
])));
assert.equal(roundTrippedTrip.stops[0].arrivalTarget?.maximumLengthMeters, 7.5);
assert.equal(roundTrippedTrip.stops[0].stayDetails?.estimatedArrivalMode, 'manual');
assert.equal(roundTrippedTrip.stops[0].stayDetails?.estimatedArrivalWindow?.timeZoneIdentifier, 'Europe/Sofia');

const foldSingleStop = (stop) => foldTripEvents([
  {
    id: 'validation-1', tripId: 'trip-validation', revision: 1,
    occurredAt: '2026-07-26T07:04:00.000Z', actorUserId: 'user-1', type: 'tripCreated',
    payload: { name: 'Validation', kind: 'standard', ownerUserId: 'user-1' },
  },
  {
    id: 'validation-2', tripId: 'trip-validation', revision: 2,
    occurredAt: '2026-07-26T07:05:00.000Z', actorUserId: 'user-1', type: 'stopAdded',
    payload: { stop },
  },
]);

assert.throws(
  () => foldSingleStop({
    ...trip.stops[1],
    arrivalTarget: { ...trip.stops[1].arrivalTarget, maximumLengthMeters: 0 },
  }),
  /invalid_arrival_target/,
);
assert.throws(
  () => foldSingleStop({
    ...trip.stops[1],
    stayDetails: { ...trip.stops[1].stayDetails, estimatedArrivalMode: 'approximate' },
  }),
  /invalid_stay_details/,
);
for (const invalidStart of [
  '1',
  '2026-02-30T18:00:00.000Z',
  '2026-08-03T18:00:00+03:00',
  'August 3, 2026 18:00 UTC',
]) {
  assert.throws(
    () => foldSingleStop({
      ...trip.stops[1],
      stayDetails: {
        ...trip.stops[1].stayDetails,
        estimatedArrivalWindow: {
          ...trip.stops[1].stayDetails.estimatedArrivalWindow,
          start: invalidStart,
        },
      },
    }),
    /invalid_stay_details/,
  );
}
assert.throws(
  () => foldSingleStop({
    ...trip.stops[1],
    stayDetails: {
      ...trip.stops[1].stayDetails,
      estimatedArrivalWindow: {
        ...trip.stops[1].stayDetails.estimatedArrivalWindow,
        timeZoneIdentifier: 'Mars/Olympus_Mons',
      },
    },
  }),
  /invalid_stay_details/,
);
assert.throws(
  () => foldSingleStop({
    ...trip.stops[1],
    stayDetails: {
      ...trip.stops[1].stayDetails,
      estimatedArrivalWindow: {
        start: '2026-08-03T18:00:00.000Z',
        end: '2026-08-03T17:00:00.000Z',
        timeZoneIdentifier: 'Europe/Sofia',
      },
    },
  }),
  /invalid_stay_details/,
);
assert.deepEqual(trip.members, [{ userId: 'user-1', role: 'owner' }]);

assert.throws(
  () => foldTripEvents([{ ...tripEvent('tripCreated', 1), payload: { name: '', kind: 'standard', ownerUserId: 'u1' } }]),
  /trip_name_required/,
);

assert.throws(
  () => foldTripEvents([
    { ...tripEvent('tripCreated', 1), payload: { name: 'Test', kind: 'standard', ownerUserId: 'u1' } },
    {
      ...tripEvent('stopAdded', 2),
      payload: {
        stop: {
          id: 'bad', name: 'Hatalı', lat: 42, lng: 23, order: 0,
          arrivalTarget: {
            id: 'bad-target', name: 'Hatalı', kind: 'address', latitude: 120,
            longitude: 23, formattedAddress: '—', source: 'user',
            updatedAt: '2026-07-26T07:01:00.000Z',
          },
        },
      },
    },
  ]),
  /invalid_arrival_target/,
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
