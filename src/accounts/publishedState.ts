export type PublishedResource =
  'live-location' | 'expense-summary' | 'plan-edits' | 'published-plan' | 'shared-journal';

export type PublicPublishedResource = Exclude<PublishedResource, 'plan-edits'>;

export type LiveLocationState = {
  lat: number;
  lng: number;
  speedKmh: number | null;
  city: string | null;
  nextStop: string | null;
  nextFlag: string | null;
  remainingKm: number | null;
  remainingToFinalKm: number | null;
  remainingMin: number | null;
  traveledKm: number | null;
  legProgress: number | null;
  journeyStarted: boolean;
  activeRouteStop: string | null;
  activeRouteCode: string | null;
  activeRouteStartedAt: string | null;
  altitudeMeters: number | null;
  altitudeKind: 'absolute' | 'relative' | null;
  altitudeSource: 'barometer' | 'gps' | null;
  pressureHpa: number | null;
  altitudeAvailable: boolean;
  ts: string;
  receivedAt: string;
};

export type ExpenseSummary = {
  totalEur: number;
  count: number;
  byCategory: Record<string, number>;
  ts: string;
  receivedAt: string;
};

export type PlanEditsState = {
  departureAt: string | null;
  days: Record<string, unknown>;
};

export type PlanEditsView = PlanEditsState & {
  revision: number;
  updatedAt: string | null;
};

export type PublishedPlanDay = {
  slug: string;
  date: string;
  label: string | null;
  origin: string | null;
  destination: string | null;
  restDay: boolean;
  dayCount: number;
};

export type PublishedPlanState = {
  departureAt: string;
  arrivalAt: string | null;
  totalDays: number;
  days: PublishedPlanDay[];
  receivedAt: string;
};

export type JournalEntry = {
  id: string;
  text: string;
  createdAt: string;
  author: string | null;
  mood: string | null;
  stopId: string | null;
};

export type JournalContribution = {
  entries: JournalEntry[];
  receivedAt: string;
};

export type ContributionState<T> = { contributions: Record<string, T> };

// Keeps cent scaling and every accepted aggregate below Number.MAX_SAFE_INTEGER.
const MAX_EXPENSE_EUR = 90_000_000_000_000;
const MAX_EXPENSE_COUNT = 10_000_000;

export class PublishedStateValidationError extends Error {
  readonly code = 'invalid_published_state';

  constructor() {
    super('invalid_request_body');
    this.name = 'PublishedStateValidationError';
  }
}

export type PublishedStateEnvelope<T> = {
  schemaVersion: 1;
  tripId: string;
  revision: number;
  updatedAt: string;
  updatedBy: string;
  data: T;
};

export interface PublishedStateStorage {
  read<T>(
    tripId: string,
    resource: PublishedResource,
  ): Promise<{ state: PublishedStateEnvelope<T>; etag: string } | null>;
  write<T>(
    tripId: string,
    resource: PublishedResource,
    state: PublishedStateEnvelope<T>,
    expectedEtag: string | null,
  ): Promise<{ state: PublishedStateEnvelope<T>; etag: string }>;
}

export const normalizeLiveLocation = (input: unknown, receivedAt: string): LiveLocationState => {
  const raw = record(input);
  const lat = finite(raw.lat);
  const lng = finite(raw.lng);
  if (lat === null || lng === null) throw new PublishedStateValidationError();
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180) invalid();
  const journeyStarted = optionalBoolean(raw.journeyStarted, false);
  const speedKmh = optionalNumber(raw.speedKmh);
  return {
    lat,
    lng,
    speedKmh: speedKmh === null ? null : Math.max(0, Math.round(speedKmh)),
    city: optionalString(raw.city, 80),
    nextStop: optionalString(raw.nextStop, 80),
    nextFlag: optionalString(raw.nextFlag, 80),
    remainingKm: optionalNumber(raw.remainingKm),
    remainingToFinalKm: optionalNumber(raw.remainingToFinalKm),
    remainingMin: optionalNumber(raw.remainingMin),
    traveledKm: journeyStarted ? optionalNumber(raw.traveledKm) : 0,
    legProgress: journeyStarted ? optionalNumber(raw.legProgress) : 0,
    journeyStarted,
    activeRouteStop: journeyStarted ? optionalString(raw.activeRouteStop, 80) : null,
    activeRouteCode: journeyStarted ? optionalString(raw.activeRouteCode, 80) : null,
    activeRouteStartedAt: journeyStarted ? optionalTimestamp(raw.activeRouteStartedAt) : null,
    altitudeMeters: optionalNumber(raw.altitudeMeters),
    altitudeKind: optionalEnum(raw.altitudeKind, ['absolute', 'relative']),
    altitudeSource: optionalEnum(raw.altitudeSource, ['barometer', 'gps']),
    pressureHpa: optionalNumber(raw.pressureHpa),
    altitudeAvailable: optionalBoolean(raw.altitudeAvailable, false),
    ts: raw.ts === undefined ? receivedAt : timestamp(raw.ts),
    receivedAt,
  };
};

export const normalizeExpenseSummary = (input: unknown, receivedAt: string): ExpenseSummary => {
  const raw = record(input);
  const totalEur = expenseAmount(raw.totalEur);
  const count = boundedInteger(raw.count, 0, MAX_EXPENSE_COUNT);
  const categoryInput = record(raw.byCategory);
  const entries = Object.entries(categoryInput);
  if (entries.length > 32) invalid();
  const byCategoryEntries = entries.map(([key, value]): [string, number] => {
    if (!key.trim() || key.length > 80) invalid();
    return [key, expenseAmount(value)];
  });
  return {
    totalEur,
    count,
    byCategory: Object.fromEntries(byCategoryEntries),
    ts: raw.ts === undefined ? receivedAt : timestamp(raw.ts),
    receivedAt,
  };
};

export const normalizePlanEdits = (input: unknown): { baseRevision: number; data: PlanEditsState } => {
  const raw = record(input);
  const baseRevision = nonnegativeInteger(raw.baseRevision);
  const departureAt = raw.departureAt === null ? null : timestamp(raw.departureAt);
  const rawDays = record(raw.days);
  const entries = Object.entries(rawDays);
  if (entries.length > 60) invalid();
  const days: Record<string, unknown> = {};
  for (const [slug, value] of entries) {
    if (!slug.trim() || slug.length > 200) invalid();
    const day = normalizeDayEdit(value);
    if (serializedBytes(day) > 64 * 1_024) invalid();
    Object.defineProperty(days, slug, { value: day, enumerable: true, configurable: true, writable: true });
  }
  if (serializedBytes(days) > 256 * 1_024) invalid();
  return { baseRevision, data: { departureAt, days } };
};

export const normalizePublishedPlan = (input: unknown, receivedAt: string): PublishedPlanState => {
  const raw = record(input);
  if (!Array.isArray(raw.days) || raw.days.length > 60) invalid();
  const rawDays = raw.days as unknown[];
  const days = rawDays.map((value: unknown): PublishedPlanDay => {
    const day = record(value);
    return {
      slug: requiredString(day.slug, 80),
      date: timestamp(day.date),
      label: optionalString(day.label, 60),
      origin: optionalString(day.origin, 60),
      destination: optionalString(day.destination, 60),
      restDay: optionalBoolean(day.restDay, false),
      dayCount: day.dayCount === undefined ? 1 : nonnegativeInteger(day.dayCount),
    };
  });
  const totalDays = raw.totalDays === undefined ? days.length : nonnegativeInteger(raw.totalDays);
  if (totalDays > 60) invalid();
  return {
    departureAt: timestamp(raw.departureAt),
    arrivalAt: raw.arrivalAt === null || raw.arrivalAt === undefined ? null : timestamp(raw.arrivalAt),
    totalDays,
    days,
    receivedAt,
  };
};

export const normalizeJournalContribution = (
  input: unknown,
  author: string | null,
  receivedAt: string,
): JournalContribution => {
  const raw = record(input);
  if (!Array.isArray(raw.entries) || raw.entries.length > 250) invalid();
  const rawEntries = raw.entries as unknown[];
  return {
    entries: rawEntries.map((value: unknown): JournalEntry => {
      const entry = record(value);
      return {
        id: requiredString(entry.id, 200),
        text: requiredString(entry.text, 5_000, false),
        createdAt: timestamp(entry.createdAt),
        author,
        mood: optionalString(entry.mood, 200),
        stopId: optionalString(entry.stopId, 200),
      };
    }),
    receivedAt,
  };
};

export const aggregateExpenses = (state: ContributionState<ExpenseSummary>): ExpenseSummary => {
  const contributions = Object.values(state.contributions);
  if (contributions.length === 0) invalid();
  const byCategory = new Map<string, number>();
  let totalEur = 0;
  let count = 0;
  for (const contribution of contributions) {
    totalEur = addExpenseAmounts(totalEur, expenseAmount(contribution.totalEur));
    count = boundedInteger(count + boundedInteger(contribution.count, 0, MAX_EXPENSE_COUNT), 0, MAX_EXPENSE_COUNT);
    for (const [category, amount] of Object.entries(contribution.byCategory)) {
      if (!category.trim() || category.length > 80) invalid();
      byCategory.set(category, addExpenseAmounts(byCategory.get(category) ?? 0, expenseAmount(amount)));
      if (byCategory.size > 32) invalid();
    }
  }
  const latestTimestamp = [...contributions].sort((left, right) => right.ts.localeCompare(left.ts))[0].ts;
  const latestReceipt = [...contributions].sort((left, right) => right.receivedAt.localeCompare(left.receivedAt))[0]
    .receivedAt;
  return {
    totalEur,
    count,
    byCategory: Object.fromEntries([...byCategory].sort(([left], [right]) => left.localeCompare(right))),
    ts: latestTimestamp,
    receivedAt: latestReceipt,
  };
};

export const flattenJournal = (state: ContributionState<JournalContribution>): JournalEntry[] =>
  Object.values(state.contributions)
    .flatMap((contribution) => contribution.entries)
    .sort((left, right) => right.createdAt.localeCompare(left.createdAt) || left.id.localeCompare(right.id));

const normalizeDayEdit = (value: unknown): Record<string, unknown> => {
  const raw = record(value);
  requireOnlyKeys(raw, [
    'origin',
    'destination',
    'distanceKm',
    'duration',
    'fuel',
    'note',
    'campName',
    'campPlace',
    'arrivalTarget',
    'stayDetails',
    'isRestDay',
    'extraDays',
    'startHour',
    'subplans',
  ]);
  const day: Record<string, unknown> = {};
  copyOptional(day, 'origin', optionalOwnString(raw, 'origin', 500));
  copyOptional(day, 'destination', optionalOwnString(raw, 'destination', 500));
  copyOptional(day, 'distanceKm', optionalOwnString(raw, 'distanceKm', 200));
  copyOptional(day, 'duration', optionalOwnString(raw, 'duration', 200));
  copyOptional(day, 'fuel', optionalOwnString(raw, 'fuel', 200));
  copyOptional(day, 'note', optionalOwnString(raw, 'note', 5_000));
  copyOptional(day, 'campName', optionalOwnString(raw, 'campName', 500));
  copyOptional(day, 'campPlace', optionalOwnString(raw, 'campPlace', 500));
  copyOptional(day, 'arrivalTarget', optionalOwnRecord(raw, 'arrivalTarget', normalizeArrivalTarget));
  copyOptional(day, 'stayDetails', optionalOwnRecord(raw, 'stayDetails', normalizeStayDetails));
  copyOptional(day, 'isRestDay', optionalOwnBoolean(raw, 'isRestDay'));
  copyOptional(day, 'extraDays', optionalOwnInteger(raw, 'extraDays', 0, 60));
  copyOptional(day, 'startHour', optionalOwnInteger(raw, 'startHour', 0, 23));
  const subplans = own(raw, 'subplans');
  if (subplans !== undefined && subplans !== null) {
    if (!Array.isArray(subplans) || subplans.length > 64) invalid();
    day.subplans = (subplans as unknown[]).map(normalizeDaySubplan);
  }
  return day;
};

const normalizeArrivalTarget = (raw: Record<string, unknown>): Record<string, unknown> => {
  requireOnlyKeys(raw, [
    'id',
    'mapItemIdentifier',
    'name',
    'kind',
    'latitude',
    'longitude',
    'formattedAddress',
    'maximumLengthMeters',
    'source',
    'updatedAt',
  ]);
  const latitude = boundedNumber(own(raw, 'latitude'), -90, 90);
  const longitude = boundedNumber(own(raw, 'longitude'), -180, 180);
  const target: Record<string, unknown> = {
    id: requiredString(own(raw, 'id'), 200),
    name: requiredString(own(raw, 'name'), 500),
    kind: requiredEnum(own(raw, 'kind'), [
      'campground',
      'hotel',
      'apartment',
      'caravanPark',
      'parking',
      'address',
      'other',
    ]),
    latitude,
    longitude,
    formattedAddress: requiredString(own(raw, 'formattedAddress'), 1_000),
    source: requiredEnum(own(raw, 'source'), ['appleMaps', 'user', 'migrated']),
    updatedAt: timestamp(own(raw, 'updatedAt')),
  };
  copyOptional(target, 'mapItemIdentifier', optionalOwnString(raw, 'mapItemIdentifier', 500));
  const maximumLength = own(raw, 'maximumLengthMeters');
  if (maximumLength !== undefined && maximumLength !== null) {
    target.maximumLengthMeters = boundedNumber(maximumLength, 0, 100);
  }
  return target;
};

const normalizeStayDetails = (raw: Record<string, unknown>): Record<string, unknown> => {
  requireOnlyKeys(raw, [
    'checkIn',
    'checkOut',
    'reservationStatus',
    'estimatedArrival',
    'estimatedArrivalMode',
    'estimatedArrivalWindow',
  ]);
  const stay: Record<string, unknown> = {
    reservationStatus: requiredEnum(own(raw, 'reservationStatus'), [
      'notContacted',
      'awaitingReply',
      'confirmed',
      'unavailable',
    ]),
    estimatedArrivalMode: requiredEnum(own(raw, 'estimatedArrivalMode'), ['automatic', 'manual']),
  };
  copyOptional(stay, 'checkIn', optionalOwnTimestamp(raw, 'checkIn'));
  copyOptional(stay, 'checkOut', optionalOwnTimestamp(raw, 'checkOut'));
  copyOptional(stay, 'estimatedArrival', optionalOwnString(raw, 'estimatedArrival', 80));
  copyOptional(stay, 'estimatedArrivalWindow', optionalOwnRecord(raw, 'estimatedArrivalWindow', normalizeStayWindow));
  return stay;
};

const normalizeStayWindow = (raw: Record<string, unknown>): Record<string, unknown> => {
  requireOnlyKeys(raw, ['start', 'end', 'timeZoneIdentifier']);
  return {
    start: timestamp(own(raw, 'start')),
    end: timestamp(own(raw, 'end')),
    timeZoneIdentifier: requiredString(own(raw, 'timeZoneIdentifier'), 100),
  };
};

const normalizeDaySubplan = (value: unknown): Record<string, unknown> => {
  const raw = record(value);
  requireOnlyKeys(raw, ['id', 'title', 'placeName', 'latitude', 'longitude', 'startMinute', 'durationMinutes', 'note']);
  const subplan: Record<string, unknown> = {
    id: requiredString(own(raw, 'id'), 200),
    title: requiredString(own(raw, 'title'), 500),
    placeName: requiredString(own(raw, 'placeName'), 500),
    latitude: boundedNumber(own(raw, 'latitude'), -90, 90),
    longitude: boundedNumber(own(raw, 'longitude'), -180, 180),
    startMinute: boundedInteger(own(raw, 'startMinute'), 0, 10_080),
    durationMinutes: boundedInteger(own(raw, 'durationMinutes'), 0, 10_080),
  };
  copyOptional(subplan, 'note', optionalOwnString(raw, 'note', 1_000));
  return subplan;
};

const requireOnlyKeys = (raw: Record<string, unknown>, allowed: readonly string[]): void => {
  const allowlist = new Set(allowed);
  if (Object.keys(raw).some((key) => !allowlist.has(key))) invalid();
};

const own = (raw: Record<string, unknown>, key: string): unknown => (Object.hasOwn(raw, key) ? raw[key] : undefined);

const copyOptional = (target: Record<string, unknown>, key: string, value: unknown): void => {
  if (value !== undefined) target[key] = value;
};

const optionalOwnString = (raw: Record<string, unknown>, key: string, maximum: number): string | undefined => {
  const value = own(raw, key);
  return value === undefined || value === null ? undefined : requiredString(value, maximum, false);
};

const optionalOwnTimestamp = (raw: Record<string, unknown>, key: string): string | undefined => {
  const value = own(raw, key);
  return value === undefined || value === null ? undefined : timestamp(value);
};

const optionalOwnBoolean = (raw: Record<string, unknown>, key: string): boolean | undefined => {
  const value = own(raw, key);
  if (value === undefined || value === null) return undefined;
  return typeof value === 'boolean' ? value : invalid();
};

const optionalOwnInteger = (
  raw: Record<string, unknown>,
  key: string,
  minimum: number,
  maximum: number,
): number | undefined => {
  const value = own(raw, key);
  return value === undefined || value === null ? undefined : boundedInteger(value, minimum, maximum);
};

const optionalOwnRecord = (
  raw: Record<string, unknown>,
  key: string,
  normalize: (value: Record<string, unknown>) => Record<string, unknown>,
): Record<string, unknown> | undefined => {
  const value = own(raw, key);
  return value === undefined || value === null ? undefined : normalize(record(value));
};

const boundedNumber = (value: unknown, minimum: number, maximum: number): number => {
  const number = finite(value);
  return number === null || number < minimum || number > maximum ? invalid() : number;
};

const boundedInteger = (value: unknown, minimum: number, maximum: number): number => {
  const number = boundedNumber(value, minimum, maximum);
  return Number.isInteger(number) ? number : invalid();
};

const requiredEnum = <T extends string>(value: unknown, values: readonly T[]): T =>
  typeof value === 'string' && values.includes(value as T) ? (value as T) : invalid();

const serializedBytes = (value: unknown): number => new TextEncoder().encode(JSON.stringify(value)).byteLength;

const invalid = (): never => {
  throw new PublishedStateValidationError();
};

const record = (value: unknown): Record<string, unknown> => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) invalid();
  return value as Record<string, unknown>;
};

const finite = (value: unknown): number | null => (typeof value === 'number' && Number.isFinite(value) ? value : null);

const optionalNumber = (value: unknown): number | null => {
  if (value === undefined || value === null) return null;
  const result = finite(value);
  return result === null ? invalid() : result;
};

const nonnegativeNumber = (value: unknown): number => {
  const result = finite(value);
  return result === null || result < 0 ? invalid() : result;
};

const nonnegativeInteger = (value: unknown): number => {
  const result = nonnegativeNumber(value);
  return Number.isInteger(result) ? result : invalid();
};

const expenseAmount = (value: unknown): number => {
  const amount = nonnegativeNumber(value);
  if (amount > MAX_EXPENSE_EUR) invalid();
  return roundCurrency(amount);
};

const addExpenseAmounts = (left: number, right: number): number => {
  const sum = left + right;
  if (!Number.isFinite(sum) || sum > MAX_EXPENSE_EUR) invalid();
  return roundCurrency(sum);
};

const requiredString = (value: unknown, maximum: number, trim = true): string => {
  if (typeof value !== 'string') invalid();
  const stringValue = value as string;
  const result = trim ? stringValue.trim() : stringValue;
  if (!result.trim() || result.length > maximum) invalid();
  return result;
};

const optionalString = (value: unknown, maximum: number): string | null => {
  if (value === undefined || value === null) return null;
  return requiredString(value, maximum);
};

const optionalBoolean = (value: unknown, fallback: boolean): boolean => {
  if (value === undefined) return fallback;
  return typeof value === 'boolean' ? value : invalid();
};

const optionalEnum = <T extends string>(value: unknown, values: readonly T[]): T | null => {
  if (value === undefined || value === null) return null;
  return typeof value === 'string' && values.includes(value as T) ? (value as T) : invalid();
};

const optionalTimestamp = (value: unknown): string | null =>
  value === undefined || value === null ? null : timestamp(value);

const timestamp = (value: unknown): string => {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/.test(value)) invalid();
  const stringValue = value as string;
  const milliseconds = Date.parse(stringValue);
  if (!Number.isFinite(milliseconds)) invalid();
  const canonical = new Date(milliseconds).toISOString();
  const expected = stringValue.includes('.')
    ? stringValue.replace(/\.(\d{1,3})Z$/, (_, fraction: string) => `.${fraction.padEnd(3, '0')}Z`)
    : stringValue.replace('Z', '.000Z');
  if (canonical !== expected) invalid();
  return canonical;
};

const roundCurrency = (value: number): number => {
  const scaled = value * 100;
  if (!Number.isFinite(scaled) || scaled > Number.MAX_SAFE_INTEGER) invalid();
  const result = Math.round(scaled) / 100;
  return Number.isFinite(result) && result <= MAX_EXPENSE_EUR ? result : invalid();
};
