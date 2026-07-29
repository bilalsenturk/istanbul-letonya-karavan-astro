import { randomUUID } from 'node:crypto';
import { tripData } from '../data/tripData.ts';
import type { AccountRecord } from './accountRepository.ts';
import type { ArrivalTargetRecord, RouteStopRecord, TripEvent } from './domain.ts';
import { foldTripEvents } from './domain.ts';
import type { TripEventStorage } from './tripRepository.ts';

const kuzeyTripId = 'kuzey-2026';
const seedAt = '2026-07-26T00:00:00.000Z';
const routeRevisionId = 'kuzey-route-2026-07-26-v2';

export const ensureKuzeyTrip = async (storage: TripEventStorage): Promise<void> => {
  const existing = await storage.list(kuzeyTripId);
  if (existing.length > 0) {
    if (existing.some((event) => event.id === routeRevisionId)) return;
    const trip = foldTripEvents(existing);
    await storage.append({
      id: routeRevisionId,
      tripId: kuzeyTripId,
      revision: trip.revision + 1,
      occurredAt: new Date().toISOString(),
      actorUserId: 'system',
      type: 'stopsReplaced',
      payload: { stops: kuzeyStops() },
    }, trip.revision);
    return;
  }
  let revision = 1;
  await storage.append(seedEvent(revision, 'tripCreated', {
    name: "Leyla'nın Kuzey Yolculuğu",
    kind: 'kuzey2026',
    ownerUserId: 'system-kuzey-owner',
  }), 0);
  for (const stop of kuzeyStops()) {
    revision += 1;
    await storage.append(seedEvent(revision, 'stopAdded', {
      stop,
    }), revision - 1);
  }
  for (const email of ['senturk.leyla@icloud.com', 'szngk.13@icloud.com']) {
    revision += 1;
    await storage.append(seedEvent(revision, 'memberInvited', { email, role: 'member' }), revision - 1);
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
    const trip = foldTripEvents(events);
    const invite = trip.invites.find((item) => item.email === account.email);
    if (!invite) continue;
    let revision = trip.revision;
    if (!trip.members.some((member) => member.userId === account.id)) {
      revision += 1;
      await storage.append(accountEvent(trip.id, account.id, revision, 'memberAdded', {
        userId: account.id,
        role: invite.role,
      }), revision - 1);
    }
    revision += 1;
    await storage.append(accountEvent(trip.id, account.id, revision, 'inviteRemoved', {
      email: account.email,
    }), revision - 1);
  }
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
