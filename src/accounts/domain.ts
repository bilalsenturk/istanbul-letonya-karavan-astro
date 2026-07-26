export type GlobalRole = 'globalAdmin' | 'user';
export type TripRole = 'owner' | 'member' | 'viewer';
export type TripKind = 'kuzey2026' | 'standard';
export type TripAction =
  | 'read'
  | 'editTrip'
  | 'editStops'
  | 'editJournal'
  | 'manageMembers'
  | 'startRoute'
  | 'deleteTrip';

export type Access = {
  globalRole: GlobalRole;
  tripRole: TripRole | null;
};

export type TripFeatures = {
  latvian: boolean;
  kuzeyMusic: boolean;
  publicTracking: boolean;
};

export type RouteStopRecord = {
  id: string;
  name: string;
  lat: number;
  lng: number;
  order: number;
  note?: string;
  arrivalAt?: string;
  accommodation?: string;
  link?: string;
};

export type TripMemberRecord = {
  userId: string;
  role: TripRole;
};

export type TripRecord = {
  id: string;
  name: string;
  kind: TripKind;
  revision: number;
  createdAt: string;
  updatedAt: string;
  stops: RouteStopRecord[];
  members: TripMemberRecord[];
};

export type TripEventType =
  | 'tripCreated'
  | 'tripUpdated'
  | 'stopAdded'
  | 'stopUpdated'
  | 'stopRemoved'
  | 'stopsReordered'
  | 'memberAdded'
  | 'memberRoleChanged'
  | 'memberRemoved';

export type TripEvent = {
  id: string;
  tripId: string;
  revision: number;
  occurredAt: string;
  actorUserId: string;
  type: TripEventType;
  payload: Record<string, unknown>;
};

const adminEmails = new Set(['senturk.bilal@icloud.com']);

export const normalizeEmail = (email: string): string => email.trim().toLocaleLowerCase('en-US');

export const resolveGlobalRole = (email: string | null | undefined): GlobalRole =>
  email && adminEmails.has(normalizeEmail(email)) ? 'globalAdmin' : 'user';

export const featuresFor = (kind: TripKind): TripFeatures => ({
  latvian: kind === 'kuzey2026',
  kuzeyMusic: kind === 'kuzey2026',
  publicTracking: kind === 'kuzey2026',
});

export const can = (access: Access, action: TripAction): boolean => {
  if (access.globalRole === 'globalAdmin') return true;
  if (access.tripRole === 'owner') return true;
  if (access.tripRole === 'member') {
    return action === 'read' || action === 'editStops' || action === 'editJournal';
  }
  return access.tripRole === 'viewer' && action === 'read';
};

export const foldTripEvents = (events: TripEvent[]): TripRecord => {
  const ordered = [...events].sort((left, right) => left.revision - right.revision);
  const created = ordered[0];
  if (!created || created.type !== 'tripCreated') throw new Error('trip_created_event_required');

  const name = requiredString(created.payload.name, 'trip_name_required');
  const kind = tripKind(created.payload.kind);
  const ownerUserId = requiredString(created.payload.ownerUserId, 'trip_owner_required');
  const trip: TripRecord = {
    id: created.tripId,
    name,
    kind,
    revision: created.revision,
    createdAt: created.occurredAt,
    updatedAt: created.occurredAt,
    stops: [],
    members: [{ userId: ownerUserId, role: 'owner' }],
  };

  for (const event of ordered.slice(1)) {
    if (event.tripId !== trip.id || event.revision <= trip.revision) {
      throw new Error('invalid_trip_event_sequence');
    }
    applyEvent(trip, event);
    trip.revision = event.revision;
    trip.updatedAt = event.occurredAt;
  }

  trip.stops.sort((left, right) => left.order - right.order);
  return trip;
};

const applyEvent = (trip: TripRecord, event: TripEvent): void => {
  switch (event.type) {
    case 'tripUpdated': {
      if (event.payload.name !== undefined) {
        trip.name = requiredString(event.payload.name, 'trip_name_required');
      }
      break;
    }
    case 'stopAdded': {
      const stop = routeStop(event.payload.stop);
      if (trip.stops.some((item) => item.id === stop.id)) throw new Error('duplicate_stop');
      trip.stops.push(stop);
      break;
    }
    case 'stopUpdated': {
      const stopId = requiredString(event.payload.stopId, 'stop_id_required');
      const stop = trip.stops.find((item) => item.id === stopId);
      if (!stop) throw new Error('stop_not_found');
      Object.assign(stop, stopChanges(event.payload.changes));
      break;
    }
    case 'stopRemoved': {
      const stopId = requiredString(event.payload.stopId, 'stop_id_required');
      trip.stops = trip.stops.filter((item) => item.id !== stopId);
      break;
    }
    case 'stopsReordered': {
      const stopIds = stringArray(event.payload.stopIds, 'stop_order_required');
      if (stopIds.length !== trip.stops.length || new Set(stopIds).size !== trip.stops.length) {
        throw new Error('invalid_stop_order');
      }
      const positions = new Map(stopIds.map((id, index) => [id, index]));
      if (trip.stops.some((stop) => !positions.has(stop.id))) throw new Error('invalid_stop_order');
      trip.stops.forEach((stop) => { stop.order = positions.get(stop.id)!; });
      break;
    }
    case 'memberAdded': {
      const userId = requiredString(event.payload.userId, 'member_user_required');
      const role = tripRole(event.payload.role);
      if (trip.members.some((member) => member.userId === userId)) throw new Error('duplicate_member');
      trip.members.push({ userId, role });
      break;
    }
    case 'memberRoleChanged': {
      const userId = requiredString(event.payload.userId, 'member_user_required');
      const member = trip.members.find((item) => item.userId === userId);
      if (!member) throw new Error('member_not_found');
      const role = tripRole(event.payload.role);
      if (member.role === 'owner' && role !== 'owner' && ownerCount(trip) === 1) {
        throw new Error('last_owner_required');
      }
      member.role = role;
      break;
    }
    case 'memberRemoved': {
      const userId = requiredString(event.payload.userId, 'member_user_required');
      const member = trip.members.find((item) => item.userId === userId);
      if (!member) throw new Error('member_not_found');
      if (member.role === 'owner' && ownerCount(trip) === 1) throw new Error('last_owner_required');
      trip.members = trip.members.filter((item) => item.userId !== userId);
      break;
    }
    case 'tripCreated':
      throw new Error('duplicate_trip_created_event');
  }
};

const ownerCount = (trip: TripRecord): number => trip.members.filter((member) => member.role === 'owner').length;

const requiredString = (value: unknown, error: string): string => {
  if (typeof value !== 'string' || value.trim().length === 0) throw new Error(error);
  return value.trim();
};

const stringArray = (value: unknown, error: string): string[] => {
  if (!Array.isArray(value) || value.some((item) => typeof item !== 'string')) throw new Error(error);
  return value;
};

const tripKind = (value: unknown): TripKind => {
  if (value === 'kuzey2026' || value === 'standard') return value;
  throw new Error('invalid_trip_kind');
};

const tripRole = (value: unknown): TripRole => {
  if (value === 'owner' || value === 'member' || value === 'viewer') return value;
  throw new Error('invalid_trip_role');
};

const routeStop = (value: unknown): RouteStopRecord => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('invalid_stop');
  const raw = value as Record<string, unknown>;
  const lat = finiteNumber(raw.lat, 'invalid_stop_coordinates');
  const lng = finiteNumber(raw.lng, 'invalid_stop_coordinates');
  const order = finiteNumber(raw.order, 'invalid_stop_order');
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180 || order < 0) throw new Error('invalid_stop_coordinates');
  return {
    id: requiredString(raw.id, 'stop_id_required'),
    name: requiredString(raw.name, 'stop_name_required'),
    lat,
    lng,
    order,
    ...optionalStopFields(raw),
  };
};

const stopChanges = (value: unknown): Partial<RouteStopRecord> => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('invalid_stop_changes');
  const raw = value as Record<string, unknown>;
  const result: Partial<RouteStopRecord> = optionalStopFields(raw);
  if (raw.name !== undefined) result.name = requiredString(raw.name, 'stop_name_required');
  if (raw.lat !== undefined) result.lat = finiteNumber(raw.lat, 'invalid_stop_coordinates');
  if (raw.lng !== undefined) result.lng = finiteNumber(raw.lng, 'invalid_stop_coordinates');
  if (raw.order !== undefined) result.order = finiteNumber(raw.order, 'invalid_stop_order');
  return result;
};

const optionalStopFields = (raw: Record<string, unknown>): Partial<RouteStopRecord> => {
  const result: Partial<RouteStopRecord> = {};
  for (const key of ['note', 'arrivalAt', 'accommodation', 'link'] as const) {
    if (raw[key] !== undefined) result[key] = String(raw[key]);
  }
  return result;
};

const finiteNumber = (value: unknown, error: string): number => {
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error(error);
  return value;
};
