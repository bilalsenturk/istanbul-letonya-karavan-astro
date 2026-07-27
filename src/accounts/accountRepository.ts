import { createHash, createHmac } from 'node:crypto';
import type { AppleIdentity } from './appleAuth.ts';
import { normalizeEmail, resolveGlobalRole, type GlobalRole } from './domain.ts';
import { readPrivateJSON, writePrivateJSON } from './privateBlob.ts';

export type AccountRecord = {
  id: string;
  email: string | null;
  displayName: string | null;
  globalRole: GlobalRole;
  createdAt: string;
  updatedAt: string;
  travelProfile: TravelProfileRecord;
};

export type TravelProfileRecord = {
  contactName: string;
  contactEmail: string | null;
  adults: number;
  children: number;
  vehicleDescription: string;
  totalLengthMeters: number | null;
  needsElectricity: boolean;
  hasPet: boolean;
  additionalNeeds: string;
  preferredLanguage: 'english' | 'turkish';
  updatedAt: string;
};

type SessionRecord = {
  id: string;
  userId: string;
  expiresAt: string;
  revokedAt: string | null;
};

const subjectId = (subject: string): string => {
  const secret = import.meta.env.AUTH_SESSION_SECRET;
  if (!secret) {
    if (!import.meta.env.DEV) throw new Error('AUTH_SESSION_SECRET missing');
    return createHash('sha256').update(subject).digest('hex');
  }
  return createHmac('sha256', secret).update(subject).digest('hex');
};

export const upsertAppleAccount = async (
  identity: AppleIdentity,
  displayName: string | null,
): Promise<AccountRecord> => {
  const id = subjectId(identity.appleSubject);
  const existing = await accountById(id);
  const now = new Date().toISOString();
  const email = identity.email ? normalizeEmail(identity.email) : existing?.email ?? null;
  const record: AccountRecord = {
    id,
    email,
    displayName: displayName?.trim() || existing?.displayName || null,
    globalRole: existing?.globalRole === 'globalAdmin' ? 'globalAdmin' : resolveGlobalRole(email),
    createdAt: existing?.createdAt ?? now,
    updatedAt: now,
    travelProfile: existing?.travelProfile ?? defaultTravelProfile(
      displayName?.trim() || existing?.displayName || '', email, now,
    ),
  };
  await writePrivateJSON(`accounts/users/${id}.json`, record);
  if (email) await writePrivateJSON(`accounts/email-index/${emailHash(email)}.json`, { userId: id });
  return record;
};

export const accountById = (id: string): Promise<AccountRecord | null> =>
  readPrivateJSON<AccountRecord>(`accounts/users/${id}.json`);

export const accountByEmail = async (email: string): Promise<AccountRecord | null> => {
  const link = await readPrivateJSON<{ userId: string }>(`accounts/email-index/${emailHash(email)}.json`);
  return link ? accountById(link.userId) : null;
};

export const normalizeTravelProfile = (
  input: Partial<TravelProfileRecord>,
  fallback?: TravelProfileRecord,
): TravelProfileRecord => {
  const invalid = (): never => { throw new Error('invalid_travel_profile'); };
  const string = (value: unknown, maximum: number, defaultValue = ''): string => {
    const resolved = value === undefined ? defaultValue : value;
    if (typeof resolved !== 'string') return invalid();
    const normalized = resolved.trim();
    if (normalized.length > maximum) return invalid();
    return normalized;
  };
  const integer = (value: unknown, minimum: number, maximum: number, defaultValue: number): number => {
    const resolved = value === undefined ? defaultValue : value;
    if (!Number.isInteger(resolved) || resolved < minimum || resolved > maximum) return invalid();
    return resolved;
  };
  const boolean = (value: unknown, defaultValue: boolean): boolean => {
    const resolved = value === undefined ? defaultValue : value;
    if (typeof resolved !== 'boolean') return invalid();
    return resolved;
  };
  const emailValue = input.contactEmail === undefined ? fallback?.contactEmail ?? null : input.contactEmail;
  if (emailValue !== null && typeof emailValue !== 'string') return invalid();
  const contactEmail = emailValue === null ? null : string(emailValue, 254);
  if (contactEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contactEmail)) return invalid();
  const totalLength = input.totalLengthMeters === undefined ? fallback?.totalLengthMeters ?? null : input.totalLengthMeters;
  if (totalLength !== null && (!Number.isFinite(totalLength) || totalLength < 1 || totalLength > 30)) return invalid();
  const preferredLanguage = input.preferredLanguage ?? fallback?.preferredLanguage ?? 'english';
  if (preferredLanguage !== 'english' && preferredLanguage !== 'turkish') return invalid();
  return {
    contactName: string(input.contactName, 120, fallback?.contactName),
    contactEmail: contactEmail ? normalizeEmail(contactEmail) : null,
    adults: integer(input.adults, 1, 12, fallback?.adults ?? 2),
    children: integer(input.children, 0, 12, fallback?.children ?? 0),
    vehicleDescription: string(input.vehicleDescription, 160, fallback?.vehicleDescription),
    totalLengthMeters: totalLength,
    needsElectricity: boolean(input.needsElectricity, fallback?.needsElectricity ?? true),
    hasPet: boolean(input.hasPet, fallback?.hasPet ?? false),
    additionalNeeds: string(input.additionalNeeds, 1_000, fallback?.additionalNeeds),
    preferredLanguage,
    updatedAt: string(input.updatedAt, 64, fallback?.updatedAt ?? new Date().toISOString()),
  };
};

export const updateTravelProfile = async (
  userId: string,
  profile: Partial<TravelProfileRecord>,
): Promise<AccountRecord> => {
  const account = await accountById(userId);
  if (!account) throw new Error('account_not_found');
  const now = new Date().toISOString();
  const updated: AccountRecord = {
    ...account,
    updatedAt: now,
    travelProfile: { ...normalizeTravelProfile(profile, account.travelProfile), updatedAt: now },
  };
  await writePrivateJSON(`accounts/users/${userId}.json`, updated);
  return updated;
};

export const saveSession = async (id: string, userId: string, expiresAt: Date): Promise<void> => {
  const record: SessionRecord = { id, userId, expiresAt: expiresAt.toISOString(), revokedAt: null };
  await writePrivateJSON(`accounts/sessions/${id}.json`, record);
};

export const sessionIsActive = async (id: string, userId: string): Promise<boolean> => {
  const session = await readPrivateJSON<SessionRecord>(`accounts/sessions/${id}.json`);
  return Boolean(session && session.userId === userId && !session.revokedAt && new Date(session.expiresAt) > new Date());
};

export const revokeSession = async (id: string): Promise<void> => {
  const pathname = `accounts/sessions/${id}.json`;
  const session = await readPrivateJSON<SessionRecord>(pathname);
  if (session) await writePrivateJSON(pathname, { ...session, revokedAt: new Date().toISOString() });
};

const emailHash = (email: string): string => createHash('sha256').update(normalizeEmail(email)).digest('hex');

const defaultTravelProfile = (contactName: string, contactEmail: string | null, updatedAt: string): TravelProfileRecord =>
  normalizeTravelProfile({ contactName, contactEmail, updatedAt });
