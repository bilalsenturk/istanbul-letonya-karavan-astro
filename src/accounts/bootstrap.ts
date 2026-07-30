import { randomUUID } from 'node:crypto';
import { tripData } from '../data/tripData.ts';
import type { AccountRecord } from './accountRepository.ts';
import type { ArrivalTargetRecord, RouteStopRecord, TripEvent } from './domain.ts';
import { foldTripEvents, normalizeEmail, TripDomainError } from './domain.ts';
import { TripRepositoryError, TripStorageConflictError, type TripEventStorage } from './tripRepository.ts';

const kuzeyTripId = 'kuzey-2026';
const seedAt = '2026-07-26T00:00:00.000Z';
const routeRevisionId = 'kuzey-route-2026-07-26-v2';
const kuzeyOwnerEmails = new Set(['senturk.leyla@icloud.com', 'szngk.13@icloud.com']);

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
  for (const tripId of await storage.listTripIds()) {
    await reconcileTripMembership(storage, account, tripId);
  }
};

// Session restoration only needs to reconcile the seeded Kuzey trip. Keeping
// this targeted avoids a second full scan before listTripsForUser() and means a
// corrupt, unrelated trip cannot prevent the account from opening.
export const reconcileKuzeyMembership = async (
  storage: TripEventStorage,
  account: AccountRecord,
): Promise<void> => reconcileTripMembership(storage, account, kuzeyTripId);

const reconcileTripMembership = async (
  storage: TripEventStorage,
  account: AccountRecord,
  tripId: string,
): Promise<void> => {
  if (!account.email) return;
  const email = normalizeEmail(account.email);

  // A claim can require two events (membership + invite cleanup). Re-read for
  // every event so concurrent sign-in/session-restore calls stay idempotent.
  for (let attempt = 0; attempt < 6; attempt += 1) {
    const events = await storage.list(tripId);
    if (events.length === 0) return;
    let trip: ReturnType<typeof foldTripEvents>;
    try {
      trip = foldTripEvents(events);
    } catch (error) {
      if (error instanceof TripDomainError) return;
      throw error;
    }
    const invite = trip.invites.find((item) => item.email === email);
    const member = trip.members.find((item) => item.userId === account.id);
    const isTrustedKuzeyOwner = trip.id === kuzeyTripId && kuzeyOwnerEmails.has(email);
    const hasExplicitRoleHistory = events.some((event) =>
      event.type === 'memberRoleChanged' && event.payload.userId === account.id,
    );

    let candidate: TripEvent | null = null;
    if (!member && invite) {
      candidate = accountEvent(trip.id, account.id, trip.revision + 1, 'memberAdded', {
        userId: account.id,
        role: isTrustedKuzeyOwner ? 'owner' : invite.role,
      });
    } else if (member && isTrustedKuzeyOwner && member.role !== 'owner' && !hasExplicitRoleHistory) {
      candidate = accountEvent(trip.id, account.id, trip.revision + 1, 'memberRoleChanged', {
        userId: account.id,
        role: 'owner',
      });
    } else if (invite) {
      candidate = accountEvent(trip.id, account.id, trip.revision + 1, 'inviteRemoved', { email });
    }

    if (!candidate) return;
    try {
      await appendCandidate(storage, events, trip.revision, candidate);
    } catch (error) {
      if (error instanceof TripRepositoryError && error.code === 'revision_conflict' && attempt < 5) continue;
      throw error;
    }
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
