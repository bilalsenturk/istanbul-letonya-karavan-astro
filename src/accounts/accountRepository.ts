import { createHash, createHmac, randomUUID } from 'node:crypto';
import type { AppleIdentity } from './appleAuth.ts';
import { normalizeEmail, resolveGlobalRole, type GlobalRole } from './domain.ts';
import { listPrivatePaths, readPrivateJSON, writePrivateJSON } from './privateBlob.ts';

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

export type AccountStore = {
  read<T>(pathname: string): Promise<T | null>;
  write(pathname: string, value: unknown): Promise<void>;
  list?(prefix: string): Promise<string[]>;
};

export type AccountRepository = {
  upsertAppleAccount(identity: AppleIdentity, displayName: string | null): Promise<AccountRecord>;
  accountById(id: string): Promise<AccountRecord | null>;
  accountByEmail(email: string): Promise<AccountRecord | null>;
  updateTravelProfile(userId: string, profile: Partial<TravelProfileRecord>): Promise<AccountRecord>;
};

type ProfileRevision = { profile: TravelProfileRecord; kind: 'userUpdate' | 'appleSeed' | 'legacyMigration'; revisionId: string; writtenAt: string };

const subjectId = (subject: string): string => {
  const secret = import.meta.env.AUTH_SESSION_SECRET;
  if (!secret) {
    if (!import.meta.env.DEV) throw new Error('AUTH_SESSION_SECRET missing');
    return createHash('sha256').update(subject).digest('hex');
  }
  return createHmac('sha256', secret).update(subject).digest('hex');
};

export const createAccountRepository = (dependencies: AccountStore & {
  subjectId?: (subject: string) => string;
  now?: () => string;
}): AccountRepository => {
  const now = dependencies.now ?? (() => new Date().toISOString());
  let lastTimestamp = 0;
  const serverTimestamp = (): string => {
    const parsed = Date.parse(now());
    lastTimestamp = Math.max(lastTimestamp + 1, Number.isFinite(parsed) ? parsed : Date.now());
    return new Date(lastTimestamp).toISOString();
  };
  const identifier = dependencies.subjectId ?? subjectId;
  const userPath = (id: string) => `accounts/users/${id}.json`;
  const profilePath = (id: string) => `accounts/profiles/${id}.json`;
  const revisionPrefix = (id: string) => `accounts/profiles/${id}/revisions/`;
  const validTimestamp = (value: unknown): string | null => {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(value)) return null;
    const time = Date.parse(value);
    return Number.isFinite(time) ? new Date(time).toISOString() : null;
  };
  const appendProfile = async (id: string, profile: TravelProfileRecord, kind: ProfileRevision['kind']): Promise<void> => {
    const timestamp = validTimestamp(profile.updatedAt);
    if (!timestamp) throw new Error('invalid_travel_profile');
    const revisionId = randomUUID();
    await dependencies.write(`${revisionPrefix(id)}${timestamp}-${revisionId}.json`, { profile: { ...profile, updatedAt: timestamp }, kind, revisionId, writtenAt: timestamp } satisfies ProfileRevision);
  };

  const accountById = async (id: string): Promise<AccountRecord | null> => {
    const account = await dependencies.read<AccountRecord>(userPath(id));
    if (!account) return null;
    const snapshotProfile = account.travelProfile && validTimestamp(account.travelProfile.updatedAt)
      ? { ...account.travelProfile, updatedAt: validTimestamp(account.travelProfile.updatedAt)! }
      : defaultTravelProfile(account.displayName ?? '', account.email, account.updatedAt);
    const selectProfile = async () => {
      const fixed = await dependencies.read<TravelProfileRecord>(profilePath(id));
      const paths = await dependencies.list?.(revisionPrefix(id)) ?? [];
      const revisions = await Promise.all(paths.map(async (path) => ({ path, value: await dependencies.read<unknown>(path) })));
      const candidate = (profile: unknown, priority: number, revisionId: string) => {
        if (!profile || typeof profile !== 'object' || !validTimestamp((profile as TravelProfileRecord).updatedAt)) return null;
        return { profile: profile as TravelProfileRecord, priority, revisionId };
      };
      const candidates = [candidate(fixed, 0, 'fixed'), candidate(snapshotProfile, 0, 'snapshot'), ...revisions.map(({ path, value }) => {
        const envelope = value && typeof value === 'object' && 'profile' in value ? value as ProfileRevision : null;
        const priority = envelope?.kind === 'userUpdate' ? 2 : envelope ? 1 : 0;
        return candidate(envelope?.profile ?? value, priority, envelope?.revisionId ?? path);
      })].filter(Boolean) as { profile: TravelProfileRecord; priority: number; revisionId: string }[];
      const selected = candidates.sort((left, right) => Date.parse(right.profile.updatedAt) - Date.parse(left.profile.updatedAt)
        || right.priority - left.priority || right.revisionId.localeCompare(left.revisionId))[0];
      return { profile: selected?.profile ?? snapshotProfile, paths };
    };
    let { profile, paths } = await selectProfile();
    if (paths.length === 0) {
      await appendProfile(id, snapshotProfile, 'legacyMigration');
      ({ profile, paths } = await selectProfile());
    }
    return {
      ...account,
      travelProfile: profile,
    };
  };

  const accountByEmail = async (email: string): Promise<AccountRecord | null> => {
    const link = await dependencies.read<{ userId: string }>(`accounts/email-index/${emailHash(email)}.json`);
    return link ? accountById(link.userId) : null;
  };

  return {
    accountById,
    accountByEmail,
    upsertAppleAccount: async (identity, displayName) => {
      const id = identifier(identity.appleSubject);
      const existing = await accountById(id);
      const timestamp = serverTimestamp();
      const email = identity.email ? normalizeEmail(identity.email) : existing?.email ?? null;
      const travelProfile = existing?.travelProfile ?? defaultTravelProfile(
        displayName?.trim() || existing?.displayName || '', email, timestamp,
      );
      const record: AccountRecord = {
        id,
        email,
        displayName: displayName?.trim() || existing?.displayName || null,
        globalRole: existing?.globalRole === 'globalAdmin' ? 'globalAdmin' : resolveGlobalRole(email),
        createdAt: existing?.createdAt ?? timestamp,
        updatedAt: timestamp,
        travelProfile,
      };
      // Establish private profile authority before publishing a first account. A PATCH can
      // only discover the account after this write has completed, so it cannot be seeded over.
      if (!existing) await appendProfile(id, travelProfile, 'appleSeed');
      await dependencies.write(userPath(id), record);
      if (email) await dependencies.write(`accounts/email-index/${emailHash(email)}.json`, { userId: id });
      return (await accountById(id))!;
    },
    updateTravelProfile: async (userId, profile) => {
      const account = await accountById(userId);
      if (!account) throw new Error('account_not_found');
      const timestamp = serverTimestamp();
      const travelProfile = { ...normalizeTravelProfile(profile, account.travelProfile), updatedAt: timestamp };
      // The profile blob is authoritative: an interleaved Apple upsert can only overwrite
      // the account mirror, never a completed profile update.
      await appendProfile(userId, travelProfile, 'userUpdate');
      const updated: AccountRecord = { ...account, updatedAt: timestamp, travelProfile };
      await dependencies.write(userPath(userId), updated);
      return (await accountById(userId))!;
    },
  };
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
  const preferredLanguage = input.preferredLanguage === undefined ? fallback?.preferredLanguage ?? 'english' : input.preferredLanguage;
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

const productionRepository = createAccountRepository({ read: readPrivateJSON, write: writePrivateJSON, list: listPrivatePaths });

export const upsertAppleAccount = productionRepository.upsertAppleAccount;
export const accountById = productionRepository.accountById;
export const accountByEmail = productionRepository.accountByEmail;
export const updateTravelProfile = productionRepository.updateTravelProfile;

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
