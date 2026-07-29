import { randomUUID } from 'node:crypto';
import {
  can,
  featuresFor,
  foldTripEvents,
  normalizeEmail,
  TripDomainError,
  type GlobalRole,
  type TripAction,
  type TripEvent,
  type TripEventType,
  type TripRecord,
  type TripRole,
  type TransportMode,
  type RouteStopRecord,
} from './domain.ts';

export interface TripEventStorage {
  listTripIds(): Promise<string[]>;
  list(tripId: string): Promise<TripEvent[]>;
  append(event: TripEvent, expectedRevision: number): Promise<void>;
}

export type TripActor = {
  userId: string;
  globalRole: GlobalRole;
};

export type TripAccessView = {
  tripRole: TripRole | null;
  canEditTrip: boolean;
  canEditStops: boolean;
  canEditJournal: boolean;
  canManageMembers: boolean;
  canStartRoute: boolean;
  canDeleteTrip: boolean;
};

export type TripView = TripRecord & {
  features: ReturnType<typeof featuresFor>;
  access: TripAccessView;
};

export class TripRepositoryError extends Error {
  readonly code: string;
  readonly current?: TripRecord;

  constructor(
    code: string,
    message = code,
    current?: TripRecord,
  ) {
    super(message);
    this.code = code;
    this.current = current;
  }
}

export class TripStorageConflictError extends TripRepositoryError {
  constructor() {
    super('revision_conflict');
  }
}

export const createTrip = async (
  storage: TripEventStorage,
  actor: TripActor,
  input: { name: string; kind?: string; transportMode?: TransportMode; stops: RouteStopRecord[] },
): Promise<TripRecord> => {
  if (input.kind && input.kind !== 'standard') throw new TripRepositoryError('reserved_trip_kind');
  if (input.transportMode && !['automobile', 'walking', 'flight'].includes(input.transportMode)) {
    throw new TripRepositoryError('invalid_transport_mode');
  }
  const name = input.name.trim();
  if (!name) throw new TripRepositoryError('trip_name_required');
  const tripId = randomUUID();
  const occurredAt = new Date().toISOString();
  const candidate = event(
    tripId,
    actor.userId,
    1,
    'tripCreated',
    {
      name,
      kind: 'standard',
      transportMode: input.transportMode ?? 'automobile',
      ownerUserId: actor.userId,
      stops: input.stops.map((stop, index) => ({ ...stop, order: index })),
    },
    occurredAt,
  );

  let trip: TripRecord;
  try {
    trip = foldTripEvents([candidate]);
  } catch (error) {
    if (error instanceof TripDomainError) {
      throw new TripRepositoryError(error.code, error.message);
    }
    throw error;
  }
  await storage.append(candidate, 0);
  return trip;
};

export const getTripForUser = async (
  storage: TripEventStorage,
  actor: TripActor,
  tripId: string,
): Promise<TripView> => {
  const trip = await getTripForAction(storage, actor, tripId, 'read');
  const tripRole = trip.members.find((member) => member.userId === actor.userId)?.role ?? null;
  const access = { globalRole: actor.globalRole, tripRole };
  return {
    ...trip,
    features: featuresFor(trip.kind),
    access: {
      tripRole,
      canEditTrip: can(access, 'editTrip'),
      canEditStops: can(access, 'editStops'),
      canEditJournal: can(access, 'editJournal'),
      canManageMembers: can(access, 'manageMembers'),
      canStartRoute: can(access, 'startRoute'),
      canDeleteTrip: can(access, 'deleteTrip'),
    },
  };
};

export const getTripForAction = async (
  storage: TripEventStorage,
  actor: TripActor,
  tripId: string,
  action: TripAction,
): Promise<TripRecord> => {
  const trip = await loadTrip(storage, tripId);
  requireAction(trip, actor, action);
  return trip;
};

export const getPublicTrip = async (
  storage: TripEventStorage,
  tripId: string,
): Promise<TripRecord> => {
  const trip = await loadTrip(storage, tripId);
  if (trip.kind !== 'kuzey2026' || !featuresFor(trip.kind).publicTracking) {
    throw new TripRepositoryError('trip_not_found');
  }
  return trip;
};

export const listTripsForUser = async (
  storage: TripEventStorage,
  actor: TripActor,
): Promise<TripView[]> => {
  const tripIds = await storage.listTripIds();
  const results = await Promise.all(tripIds.map(async (tripId) => {
    try {
      return await getTripForUser(storage, actor, tripId);
    } catch (error) {
      if (error instanceof TripRepositoryError && (error.code === 'forbidden' || error.code === 'trip_corrupt')) return null;
      throw error;
    }
  }));
  return results.filter((trip): trip is TripView => trip !== null);
};

export const mutateTrip = async (
  storage: TripEventStorage,
  actor: TripActor,
  input: {
    tripId: string;
    baseRevision: number;
    type: Exclude<TripEventType, 'tripCreated' | 'memberInvited'>;
    payload: Record<string, unknown>;
  },
): Promise<TripRecord> => {
  const { events, trip: current } = await loadTripHistory(storage, input.tripId);
  requireAction(current, actor, actionFor(input.type));
  requireCurrentRevision(current, input.baseRevision);
  const candidate = event(
    current.id,
    actor.userId,
    current.revision + 1,
    input.type,
    input.payload,
  );
  return appendCandidate(storage, events, current, candidate);
};

export const inviteMember = async (
  storage: TripEventStorage,
  actor: TripActor,
  input: {
    tripId: string;
    baseRevision: number;
    email: string;
    role: Exclude<TripRole, 'owner'>;
  },
): Promise<TripRecord> => {
  const { events, trip: current } = await loadTripHistory(storage, input.tripId);
  requireAction(current, actor, 'manageMembers');
  requireCurrentRevision(current, input.baseRevision);
  const email = normalizeEmail(input.email);
  if (!/^\S+@\S+\.\S+$/.test(email)) throw new TripRepositoryError('invalid_email');
  if (input.role !== 'member' && input.role !== 'viewer') throw new TripRepositoryError('invalid_invite_role');
  const candidate = event(current.id, actor.userId, current.revision + 1, 'memberInvited', {
    email,
    role: input.role,
  });
  return appendCandidate(storage, events, current, candidate);
};

const loadTrip = async (storage: TripEventStorage, tripId: string): Promise<TripRecord> => {
  const { trip } = await loadTripHistory(storage, tripId);
  return trip;
};

const loadTripHistory = async (
  storage: TripEventStorage,
  tripId: string,
): Promise<{ events: TripEvent[]; trip: TripRecord }> => {
  const events = await storage.list(tripId);
  if (events.length === 0) throw new TripRepositoryError('trip_not_found');
  try {
    return { events, trip: foldTripEvents(events) };
  } catch {
    throw new TripRepositoryError('trip_corrupt');
  }
};

const appendCandidate = async (
  storage: TripEventStorage,
  events: TripEvent[],
  current: TripRecord,
  candidate: TripEvent,
): Promise<TripRecord> => {
  let next: TripRecord;
  try {
    next = foldTripEvents([...events, candidate]);
  } catch (error) {
    if (error instanceof TripDomainError) throw new TripRepositoryError(error.code, error.message);
    throw error;
  }
  try {
    await storage.append(candidate, current.revision);
  } catch (error) {
    if (error instanceof TripStorageConflictError) {
      throw new TripRepositoryError('revision_conflict', 'revision_conflict', await loadTrip(storage, current.id));
    }
    throw error;
  }
  return next;
};

const requireAction = (trip: TripRecord, actor: TripActor, action: TripAction): void => {
  const tripRole = trip.members.find((member) => member.userId === actor.userId)?.role ?? null;
  if (!can({ globalRole: actor.globalRole, tripRole }, action)) throw new TripRepositoryError('forbidden');
};

const requireCurrentRevision = (trip: TripRecord, baseRevision: number): void => {
  if (trip.revision !== baseRevision) {
    throw new TripRepositoryError('revision_conflict', 'revision_conflict', trip);
  }
};

const actionFor = (type: Exclude<TripEventType, 'tripCreated' | 'memberInvited'>): TripAction => {
  if (type === 'tripUpdated') return 'editTrip';
  if (type === 'stopAdded' || type === 'stopUpdated' || type === 'stopRemoved' || type === 'stopsReordered' || type === 'stopsReplaced') {
    return 'editStops';
  }
  return 'manageMembers';
};

const event = (
  tripId: string,
  actorUserId: string,
  revision: number,
  type: TripEventType,
  payload: Record<string, unknown>,
  occurredAt = new Date().toISOString(),
): TripEvent => ({
  id: randomUUID(),
  tripId,
  revision,
  occurredAt,
  actorUserId,
  type,
  payload,
});
