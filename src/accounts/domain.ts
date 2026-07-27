export type GlobalRole = 'globalAdmin' | 'user';
export type TripRole = 'owner' | 'member' | 'viewer';
export type TripKind = 'kuzey2026' | 'standard';
export type TransportMode = 'automobile' | 'walking' | 'flight';
export type RouteStopSource = 'place' | 'currentLocation';
export type ArrivalTargetKind = 'campground' | 'hotel' | 'apartment' | 'caravanPark' | 'parking' | 'address' | 'other';
export type ArrivalTargetSource = 'appleMaps' | 'user' | 'migrated';
export type StayReservationStatus = 'notContacted' | 'awaitingReply' | 'confirmed' | 'unavailable';
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
  source?: RouteStopSource;
  note?: string;
  arrivalAt?: string;
  accommodation?: string;
  link?: string;
  arrivalTarget?: ArrivalTargetRecord;
  stayDetails?: StayDetailsRecord;
};

export type ArrivalTargetRecord = {
  id: string;
  mapItemIdentifier?: string;
  name: string;
  kind: ArrivalTargetKind;
  latitude: number;
  longitude: number;
  formattedAddress: string;
  phone?: string;
  whatsAppPhone?: string;
  email?: string;
  websiteURL?: string;
  maximumLengthMeters?: number;
  source: ArrivalTargetSource;
  updatedAt: string;
};

export type StayEstimatedArrivalMode = 'automatic' | 'manual';

export type StayETAWindowRecord = {
  start: string;
  end: string;
  timeZoneIdentifier: string;
};

export type StayDetailsRecord = {
  checkIn?: string;
  checkOut?: string;
  reservationStatus: StayReservationStatus;
  reservationReference?: string;
  note?: string;
  estimatedArrival?: string;
  estimatedArrivalMode?: StayEstimatedArrivalMode;
  estimatedArrivalWindow?: StayETAWindowRecord;
  lastContactedAt?: string;
};

export type TripMemberRecord = {
  userId: string;
  role: TripRole;
};

export type TripInviteRecord = {
  email: string;
  role: Exclude<TripRole, 'owner'>;
};

export type TripRecord = {
  id: string;
  name: string;
  kind: TripKind;
  transportMode: TransportMode;
  revision: number;
  createdAt: string;
  updatedAt: string;
  stops: RouteStopRecord[];
  members: TripMemberRecord[];
  invites: TripInviteRecord[];
};

export type TripEventType =
  | 'tripCreated'
  | 'tripUpdated'
  | 'stopAdded'
  | 'stopUpdated'
  | 'stopRemoved'
  | 'stopsReordered'
  | 'stopsReplaced'
  | 'memberAdded'
  | 'memberInvited'
  | 'inviteRemoved'
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
    transportMode: transportMode(created.payload.transportMode),
    revision: created.revision,
    createdAt: created.occurredAt,
    updatedAt: created.occurredAt,
    stops: [],
    members: [{ userId: ownerUserId, role: 'owner' }],
    invites: [],
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
      if (event.payload.transportMode !== undefined) {
        trip.transportMode = transportMode(event.payload.transportMode);
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
    case 'stopsReplaced': {
      if (!Array.isArray(event.payload.stops)) throw new Error('invalid_stops');
      if (event.payload.stops.length > 50) throw new Error('too_many_stops');
      const stops = event.payload.stops.map(routeStop);
      if (new Set(stops.map((stop) => stop.id)).size !== stops.length) throw new Error('duplicate_stop');
      trip.stops = stops;
      break;
    }
    case 'memberAdded': {
      const userId = requiredString(event.payload.userId, 'member_user_required');
      const role = tripRole(event.payload.role);
      if (trip.members.some((member) => member.userId === userId)) throw new Error('duplicate_member');
      trip.members.push({ userId, role });
      break;
    }
    case 'memberInvited': {
      const email = normalizeEmail(requiredString(event.payload.email, 'invite_email_required'));
      const role = inviteRole(event.payload.role);
      if (trip.invites.some((invite) => invite.email === email)) throw new Error('duplicate_invite');
      trip.invites.push({ email, role });
      break;
    }
    case 'inviteRemoved': {
      const email = normalizeEmail(requiredString(event.payload.email, 'invite_email_required'));
      trip.invites = trip.invites.filter((invite) => invite.email !== email);
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

const inviteRole = (value: unknown): Exclude<TripRole, 'owner'> => {
  if (value === 'member' || value === 'viewer') return value;
  throw new Error('invalid_invite_role');
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
    ...(raw.source === undefined ? {} : { source: routeStopSource(raw.source) }),
    ...optionalStopFields(raw),
  };
};

const routeStopSource = (value: unknown): RouteStopSource => {
  if (value === 'place' || value === 'currentLocation') return value;
  throw new Error('invalid_stop_source');
};

const stopChanges = (value: unknown): Partial<RouteStopRecord> => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('invalid_stop_changes');
  const raw = value as Record<string, unknown>;
  const result: Partial<RouteStopRecord> = optionalStopFields(raw);
  if (raw.name !== undefined) result.name = requiredString(raw.name, 'stop_name_required');
  if (raw.lat !== undefined) result.lat = finiteNumber(raw.lat, 'invalid_stop_coordinates');
  if (raw.lng !== undefined) result.lng = finiteNumber(raw.lng, 'invalid_stop_coordinates');
  if (raw.order !== undefined) result.order = finiteNumber(raw.order, 'invalid_stop_order');
  if (raw.source !== undefined) result.source = routeStopSource(raw.source);
  return result;
};

const optionalStopFields = (raw: Record<string, unknown>): Partial<RouteStopRecord> => {
  const result: Partial<RouteStopRecord> = {};
  for (const key of ['note', 'arrivalAt', 'accommodation', 'link'] as const) {
    if (raw[key] !== undefined) result[key] = String(raw[key]);
  }
  if (raw.arrivalTarget !== undefined) {
    result.arrivalTarget = raw.arrivalTarget === null ? undefined : arrivalTarget(raw.arrivalTarget);
  }
  if (raw.stayDetails !== undefined) {
    result.stayDetails = raw.stayDetails === null ? undefined : stayDetails(raw.stayDetails);
  }
  return result;
};

const arrivalTarget = (value: unknown): ArrivalTargetRecord => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('invalid_arrival_target');
  const raw = value as Record<string, unknown>;
  const latitude = finiteNumber(raw.latitude, 'invalid_arrival_target');
  const longitude = finiteNumber(raw.longitude, 'invalid_arrival_target');
  if (Math.abs(latitude) > 90 || Math.abs(longitude) > 180) throw new Error('invalid_arrival_target');
  const kind = raw.kind;
  if (!['campground', 'hotel', 'apartment', 'caravanPark', 'parking', 'address', 'other'].includes(String(kind))) {
    throw new Error('invalid_arrival_target');
  }
  const source = raw.source;
  if (!['appleMaps', 'user', 'migrated'].includes(String(source))) throw new Error('invalid_arrival_target');
  const updatedAt = isoDate(raw.updatedAt, 'invalid_arrival_target');
  const websiteURL = optionalURL(raw.websiteURL, 'invalid_arrival_target');
  const maximumLengthMeters = raw.maximumLengthMeters === undefined || raw.maximumLengthMeters === null
    ? undefined
    : finiteNumber(raw.maximumLengthMeters, 'invalid_arrival_target');
  if (maximumLengthMeters !== undefined && (maximumLengthMeters <= 0 || maximumLengthMeters > 30)) {
    throw new Error('invalid_arrival_target');
  }
  const email = optionalString(raw.email, 254);
  if (email && !/^\S+@\S+\.\S+$/.test(email)) throw new Error('invalid_arrival_target');
  return {
    id: limitedRequiredString(raw.id, 120, 'invalid_arrival_target'),
    ...(optionalString(raw.mapItemIdentifier, 300) ? { mapItemIdentifier: optionalString(raw.mapItemIdentifier, 300) } : {}),
    name: limitedRequiredString(raw.name, 200, 'invalid_arrival_target'),
    kind: kind as ArrivalTargetKind,
    latitude,
    longitude,
    formattedAddress: limitedRequiredString(raw.formattedAddress, 500, 'invalid_arrival_target'),
    ...(optionalString(raw.phone, 40) ? { phone: optionalString(raw.phone, 40) } : {}),
    ...(optionalString(raw.whatsAppPhone, 40) ? { whatsAppPhone: optionalString(raw.whatsAppPhone, 40) } : {}),
    ...(email ? { email } : {}),
    ...(websiteURL ? { websiteURL } : {}),
    ...(maximumLengthMeters !== undefined ? { maximumLengthMeters } : {}),
    source: source as ArrivalTargetSource,
    updatedAt,
  };
};

const stayDetails = (value: unknown): StayDetailsRecord => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('invalid_stay_details');
  const raw = value as Record<string, unknown>;
  const status = raw.reservationStatus ?? 'notContacted';
  if (!['notContacted', 'awaitingReply', 'confirmed', 'unavailable'].includes(String(status))) {
    throw new Error('invalid_stay_details');
  }
  const checkIn = optionalISODate(raw.checkIn, 'invalid_stay_details');
  const checkOut = optionalISODate(raw.checkOut, 'invalid_stay_details');
  if (checkIn && checkOut && Date.parse(checkOut) <= Date.parse(checkIn)) throw new Error('invalid_stay_details');
  const estimatedArrivalMode = raw.estimatedArrivalMode;
  if (estimatedArrivalMode !== undefined && estimatedArrivalMode !== null
    && !['automatic', 'manual'].includes(String(estimatedArrivalMode))) {
    throw new Error('invalid_stay_details');
  }
  const estimatedArrivalWindow = raw.estimatedArrivalWindow === undefined || raw.estimatedArrivalWindow === null
    ? undefined
    : stayETAWindow(raw.estimatedArrivalWindow);
  return {
    ...(checkIn ? { checkIn } : {}),
    ...(checkOut ? { checkOut } : {}),
    reservationStatus: status as StayReservationStatus,
    ...(optionalString(raw.reservationReference, 160) ? { reservationReference: optionalString(raw.reservationReference, 160) } : {}),
    ...(optionalString(raw.note, 2_000) ? { note: optionalString(raw.note, 2_000) } : {}),
    ...(optionalString(raw.estimatedArrival, 40) ? { estimatedArrival: optionalString(raw.estimatedArrival, 40) } : {}),
    ...(estimatedArrivalMode ? { estimatedArrivalMode: estimatedArrivalMode as StayEstimatedArrivalMode } : {}),
    ...(estimatedArrivalWindow ? { estimatedArrivalWindow } : {}),
    ...(optionalISODate(raw.lastContactedAt, 'invalid_stay_details') ? { lastContactedAt: optionalISODate(raw.lastContactedAt, 'invalid_stay_details') } : {}),
  };
};

const stayETAWindow = (value: unknown): StayETAWindowRecord => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('invalid_stay_details');
  const raw = value as Record<string, unknown>;
  const start = isoDate(raw.start, 'invalid_stay_details');
  const end = isoDate(raw.end, 'invalid_stay_details');
  if (Date.parse(end) <= Date.parse(start)) throw new Error('invalid_stay_details');
  return {
    start,
    end,
    timeZoneIdentifier: limitedRequiredString(raw.timeZoneIdentifier, 100, 'invalid_stay_details'),
  };
};

const limitedRequiredString = (value: unknown, max: number, error: string): string => {
  const result = requiredString(value, error);
  if (result.length > max) throw new Error(error);
  return result;
};

const optionalString = (value: unknown, max: number): string | undefined => {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'string') throw new Error('invalid_optional_string');
  const result = value.trim();
  if (!result) return undefined;
  if (result.length > max) throw new Error('invalid_optional_string');
  return result;
};

const isoDate = (value: unknown, error: string): string => {
  if (typeof value !== 'string' || Number.isNaN(Date.parse(value))) throw new Error(error);
  return value;
};

const optionalISODate = (value: unknown, error: string): string | undefined =>
  value === undefined || value === null ? undefined : isoDate(value, error);

const optionalURL = (value: unknown, error: string): string | undefined => {
  const text = optionalString(value, 2_000);
  if (!text) return undefined;
  try {
    const url = new URL(text);
    if (url.protocol !== 'http:' && url.protocol !== 'https:') throw new Error(error);
    return url.toString();
  } catch {
    throw new Error(error);
  }
};

const finiteNumber = (value: unknown, error: string): number => {
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error(error);
  return value;
};

const transportMode = (value: unknown): TransportMode => {
  if (value === undefined) return 'automobile';
  if (value === 'automobile' || value === 'walking' || value === 'flight') return value;
  throw new Error('invalid_transport_mode');
};
