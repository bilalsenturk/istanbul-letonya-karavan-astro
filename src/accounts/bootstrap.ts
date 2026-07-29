import { randomUUID } from 'node:crypto';
import { tripData } from '../data/tripData.ts';
import type { AccountRecord } from './accountRepository.ts';
import type { ArrivalTargetRecord, RouteStopRecord, TripEvent } from './domain.ts';
import { foldTripEvents } from './domain.ts';
import { TripRepositoryError, TripStorageConflictError, type TripEventStorage } from './tripRepository.ts';

const kuzeyTripId = 'kuzey-2026';
const seedAt = '2026-07-26T00:00:00.000Z';
const routeRevisionId = 'kuzey-route-2026-07-26-v2';

export const ensureKuzeyTrip = async (storage: TripEventStorage): Promise<void> => {
  const existing = await storage.list(kuzeyTripId);
  if (existing.length > 0) {
    if (existing.some((event) => event.id === routeRevisionId)) return;
    const trip = foldTripEvents(existing);
    const candidate = {
      id: routeRevisionId,
      tripId: kuzeyTripId,
      revision: trip.revision + 1,
      occurredAt: new Date().toISOString(),
      actorUserId: 'system',
      type: 'stopsReplaced',
      payload: { stops: kuzeyStops() },
    } satisfies TripEvent;
    await appendCandidate(storage, existing, trip.revision, candidate);
    return;
  }
  const created = seedEvent(1, 'tripCreated', {
    name: "Leyla'nın Kuzey Yolculuğu",
    kind: 'kuzey2026',
    ownerUserId: 'system-kuzey-owner',
    stops: kuzeyStops(),
  });
  await appendCandidate(storage, [], 0, created);
  const events = [created];
  for (const email of ['senturk.leyla@icloud.com', 'szngk.13@icloud.com']) {
    const candidate = seedEvent(events.length + 1, 'memberInvited', { email, role: 'member' });
    await appendCandidate(storage, events, events.length, candidate);
    events.push(candidate);
  }
};

const kuzeyStops = (): RouteStopRecord[] => tripData.stops.map((stop, order) => {
  const day = tripData.days.find((item) => item.destination === stop.name);
  const rawTarget = day?.arrivalTarget;
  const arrivalTarget: ArrivalTargetRecord | undefined = rawTarget ? {
    id: rawTarget.id,
    name: rawTarget.name,
    kind: rawTarget.kind,
    latitude: rawTarget.latitude,
    longitude: rawTarget.longitude,
    formattedAddress: rawTarget.formattedAddress,
    ...(rawTarget.phone ? { phone: rawTarget.phone } : {}),
    ...(rawTarget.whatsAppPhone ? { whatsAppPhone: rawTarget.whatsAppPhone } : {}),
    ...(rawTarget.email ? { email: rawTarget.email } : {}),
    ...(rawTarget.websiteURL ? { websiteURL: rawTarget.websiteURL } : {}),
    source: rawTarget.source as ArrivalTargetRecord['source'],
    updatedAt: seedAt,
  } : undefined;
  return {
    id: stop.id,
    name: stop.name,
    lat: stop.lat,
    lng: stop.lng,
    order,
    source: order === 0 ? 'currentLocation' : 'place',
    note: order === 0 ? 'Kalkışta cihazın güncel konumu kullanılır.' : undefined,
    accommodation: arrivalTarget?.name,
    arrivalTarget,
    stayDetails: arrivalTarget ? { reservationStatus: 'notContacted' } : undefined,
  };
});

export const claimPendingInvites = async (
  storage: TripEventStorage,
  account: AccountRecord,
): Promise<void> => {
  if (!account.email) return;
  for (const tripId of await storage.listTripIds()) {
    const events = await storage.list(tripId);
    if (events.length === 0) continue;
    let trip = foldTripEvents(events);
    const invite = trip.invites.find((item) => item.email === account.email);
    if (!invite) continue;
    if (!trip.members.some((member) => member.userId === account.id)) {
      const candidate = accountEvent(trip.id, account.id, trip.revision + 1, 'memberAdded', {
        userId: account.id,
        role: invite.role,
      });
      trip = await appendCandidate(storage, events, trip.revision, candidate);
      events.push(candidate);
    }
    const candidate = accountEvent(trip.id, account.id, trip.revision + 1, 'inviteRemoved', {
      email: account.email,
    });
    await appendCandidate(storage, events, trip.revision, candidate);
  }
};

const appendCandidate = async (
  storage: TripEventStorage,
  events: TripEvent[],
  expectedRevision: number,
  candidate: TripEvent,
): Promise<ReturnType<typeof foldTripEvents>> => {
  const trip = foldTripEvents([...events, candidate]);
  try {
    await storage.append(candidate, expectedRevision);
  } catch (error) {
    if (error instanceof TripStorageConflictError) {
      const currentEvents = await storage.list(candidate.tripId);
      throw new TripRepositoryError('revision_conflict', 'revision_conflict', foldTripEvents(currentEvents));
    }
    throw error;
  }
  return trip;
};

const seedEvent = (revision: number, type: TripEvent['type'], payload: Record<string, unknown>): TripEvent => ({
  id: `kuzey-seed-${String(revision).padStart(3, '0')}`,
  tripId: kuzeyTripId,
  revision,
  occurredAt: seedAt,
  actorUserId: 'system',
  type,
  payload,
});

const accountEvent = (
  tripId: string,
  actorUserId: string,
  revision: number,
  type: TripEvent['type'],
  payload: Record<string, unknown>,
): TripEvent => ({
  id: randomUUID(),
  tripId,
  revision,
  occurredAt: new Date().toISOString(),
  actorUserId,
  type,
  payload,
});
