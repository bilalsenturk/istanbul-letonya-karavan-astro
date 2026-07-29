export type PublishedResource =
  | 'live-location'
  | 'expense-summary'
  | 'plan-edits'
  | 'published-plan'
  | 'shared-journal';

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
  read<T>(tripId: string, resource: PublishedResource): Promise<{ state: PublishedStateEnvelope<T>; etag: string } | null>;
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
  const totalEur = nonnegativeNumber(raw.totalEur);
  const count = nonnegativeInteger(raw.count);
  const categoryInput = record(raw.byCategory);
  const entries = Object.entries(categoryInput);
  if (entries.length > 32) invalid();
  const byCategory: Record<string, number> = {};
  for (const [key, value] of entries) {
    if (!key.trim() || key.length > 80) invalid();
    byCategory[key] = nonnegativeNumber(value);
  }
  return {
    totalEur,
    count,
    byCategory,
    ts: raw.ts === undefined ? receivedAt : timestamp(raw.ts),
    receivedAt,
  };
};

export const normalizePlanEdits = (input: unknown): { baseRevision: number; data: PlanEditsState } => {
  const raw = record(input);
  const baseRevision = nonnegativeInteger(raw.baseRevision);
  const departureAt = raw.departureAt === null ? null : timestamp(raw.departureAt);
  const days = record(raw.days);
  if (Object.keys(days).length > 60) invalid();
  return { baseRevision, data: { departureAt, days: structuredClone(days) } };
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
  const byCategory: Record<string, number> = {};
  let totalEur = 0;
  let count = 0;
  for (const contribution of contributions) {
    totalEur += contribution.totalEur;
    count += contribution.count;
    for (const [category, amount] of Object.entries(contribution.byCategory)) {
      byCategory[category] = roundCurrency((byCategory[category] ?? 0) + amount);
    }
  }
  const latestTimestamp = [...contributions].sort((left, right) => right.ts.localeCompare(left.ts))[0].ts;
  const latestReceipt = [...contributions].sort((left, right) => right.receivedAt.localeCompare(left.receivedAt))[0].receivedAt;
  return {
    totalEur: roundCurrency(totalEur),
    count,
    byCategory: Object.fromEntries(Object.entries(byCategory).sort(([left], [right]) => left.localeCompare(right))),
    ts: latestTimestamp,
    receivedAt: latestReceipt,
  };
};

export const flattenJournal = (state: ContributionState<JournalContribution>): JournalEntry[] =>
  Object.values(state.contributions)
    .flatMap((contribution) => contribution.entries)
    .sort((left, right) => right.createdAt.localeCompare(left.createdAt) || left.id.localeCompare(right.id));

const invalid = (): never => { throw new PublishedStateValidationError(); };

const record = (value: unknown): Record<string, unknown> => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) invalid();
  return value as Record<string, unknown>;
};

const finite = (value: unknown): number | null => typeof value === 'number' && Number.isFinite(value) ? value : null;

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
  return typeof value === 'string' && values.includes(value as T) ? value as T : invalid();
};

const optionalTimestamp = (value: unknown): string | null => value === undefined || value === null ? null : timestamp(value);

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

const roundCurrency = (value: number): number => Math.round((value + Number.EPSILON) * 100) / 100;
