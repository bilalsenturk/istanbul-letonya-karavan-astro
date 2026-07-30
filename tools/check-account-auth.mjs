/* global structuredClone */

import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import {
  createLocalJWKSet,
  exportJWK,
  generateKeyPair,
  SignJWT,
} from 'jose';
import { verifyAppleIdentityToken } from '../src/accounts/appleAuth.ts';
import { createAccountRepository, normalizeTravelProfile } from '../src/accounts/accountRepository.ts';
import { errorResponse, json, requestJSON } from '../src/accounts/api.ts';
import { createMeHandlers } from '../src/accounts/meHandler.ts';
import { UnauthorizedError, issueSession, requireSession, verifyAccessToken, verifyRefreshToken } from '../src/accounts/session.ts';
import { TripRepositoryError } from '../src/accounts/tripRepository.ts';
import { createRefreshHandler } from '../src/pages/api/v2/auth/refresh.ts';

const travelProfile = normalizeTravelProfile({
  contactName: ' Bilal Şentürk ', contactEmail: ' BILAL@EXAMPLE.COM ',
  adults: 2, children: 0, vehicleDescription: 'VW Passat + Adria',
  totalLengthMeters: 10.8, needsElectricity: true, hasPet: false,
  additionalNeeds: '', preferredLanguage: 'english', updatedAt: '2026-07-26T08:00:00Z',
});
assert.equal(travelProfile.contactName, 'Bilal Şentürk');
assert.equal(travelProfile.contactEmail, 'bilal@example.com');
assert.equal(travelProfile.updatedAt, '2026-07-26T08:00:00.000Z');
for (const timestamp of ['2027-02-30T00:00:00Z', '2027-13-01T00:00:00Z', '2027-02-29T00:00:00Z', '2027-01-01T24:00:00Z']) {
  assert.throws(() => normalizeTravelProfile({ ...travelProfile, updatedAt: timestamp }), /invalid_travel_profile/);
}
assert.equal(normalizeTravelProfile({ ...travelProfile, updatedAt: '2028-02-29T12:34:56Z' }).updatedAt, '2028-02-29T12:34:56.000Z');
assert.equal(normalizeTravelProfile({ ...travelProfile, updatedAt: '2028-02-29T12:34:56.789Z' }).updatedAt, '2028-02-29T12:34:56.789Z');
assert.throws(() => normalizeTravelProfile({ ...travelProfile, adults: 99 }), /invalid_travel_profile/);
assert.throws(() => normalizeTravelProfile({ ...travelProfile, children: -1 }), /invalid_travel_profile/);
assert.throws(() => normalizeTravelProfile({ ...travelProfile, totalLengthMeters: 30.1 }), /invalid_travel_profile/);
const preservedProfile = normalizeTravelProfile({ contactName: ' Leyla ' }, travelProfile);
assert.equal(preservedProfile.contactName, 'Leyla');
assert.equal(preservedProfile.contactEmail, 'bilal@example.com');
assert.equal(preservedProfile.vehicleDescription, 'VW Passat + Adria');

const accountData = new Map();
const accountRepository = createAccountRepository({
  read: async (path) => accountData.has(path) ? structuredClone(accountData.get(path)) : null,
  write: async (path, value) => { accountData.set(path, structuredClone(value)); },
  list: async (prefix) => [...accountData.keys()].filter((path) => path.startsWith(prefix)),
  subjectId: (subject) => `user-${subject}`,
  now: (() => {
    let second = 0;
    return () => new Date(Date.UTC(2026, 6, 26, 8, 0, second++)).toISOString();
  })(),
});
const seeded = await accountRepository.upsertAppleAccount({
  appleSubject: 'apple-1', email: ' BILAL@EXAMPLE.COM ', emailVerified: true,
}, ' Bilal Şentürk ');
assert.equal(seeded.travelProfile.contactName, 'Bilal Şentürk');
assert.equal(seeded.travelProfile.contactEmail, 'bilal@example.com');
const saved = await accountRepository.updateTravelProfile(seeded.id, {
  ...travelProfile, contactName: 'Leyla', updatedAt: '2026-07-26T08:00:00Z',
});
assert.equal(saved.travelProfile.contactName, 'Leyla');
assert.notEqual(saved.travelProfile.updatedAt, '2026-07-26T08:00:00.000Z');
const reauthenticated = await accountRepository.upsertAppleAccount({
  appleSubject: 'apple-1', email: 'bilal@example.com', emailVerified: true,
}, 'Changed Apple Name');
assert.equal(reauthenticated.travelProfile.contactName, 'Leyla');
await assert.rejects(accountRepository.updateTravelProfile('missing', travelProfile), /account_not_found/);
const isolated = await accountRepository.upsertAppleAccount({
  appleSubject: 'apple-2', email: 'second@example.com', emailVerified: true,
}, 'Second User');
await accountRepository.updateTravelProfile(isolated.id, { ...travelProfile, contactName: 'Second Profile' });
assert.equal((await accountRepository.accountById(seeded.id)).travelProfile.contactName, 'Leyla');
assert.equal((await accountRepository.accountById(isolated.id)).travelProfile.contactName, 'Second Profile');

const legacyData = new Map();
const legacyRecord = structuredClone(seeded);
legacyRecord.travelProfile = undefined;
legacyData.set('accounts/users/user-legacy.json', legacyRecord);
const legacyRepository = createAccountRepository({
  read: async (path) => legacyData.has(path) ? structuredClone(legacyData.get(path)) : null,
  write: async (path, value) => { legacyData.set(path, structuredClone(value)); },
  list: async (prefix) => [...legacyData.keys()].filter((path) => path.startsWith(prefix)),
  subjectId: (subject) => `user-${subject}`,
});
const migratedLegacy = await legacyRepository.accountById('user-legacy');
assert.equal(migratedLegacy.travelProfile.contactName, 'Bilal Şentürk');
assert.equal([...legacyData.keys()].some((path) => path.startsWith('accounts/profiles/user-legacy/revisions/')), true);

const repairRaceData = new Map();
const repairRaceAccount = structuredClone(seeded);
repairRaceAccount.travelProfile = undefined;
repairRaceData.set('accounts/users/user-repair-race.json', repairRaceAccount);
let pauseFirstRepairAppend = true;
let repairAppendStarted;
let releaseRepairAppend;
const repairAppendGate = new Promise((resolve) => { repairAppendStarted = resolve; });
const releaseRepairGate = new Promise((resolve) => { releaseRepairAppend = resolve; });
const repairRaceRepository = createAccountRepository({
  read: async (path) => repairRaceData.has(path) ? structuredClone(repairRaceData.get(path)) : null,
  write: async (path, value) => {
    if (pauseFirstRepairAppend && path.startsWith('accounts/profiles/user-repair-race/revisions/')) {
      pauseFirstRepairAppend = false;
      repairAppendStarted();
      await releaseRepairGate;
    }
    repairRaceData.set(path, structuredClone(value));
  },
  list: async (prefix) => [...repairRaceData.keys()].filter((path) => path.startsWith(prefix)),
  subjectId: (subject) => `user-${subject}`,
});
const pendingRepair = repairRaceRepository.accountById('user-repair-race');
await repairAppendGate;
const patchedRepairRace = await repairRaceRepository.updateTravelProfile('user-repair-race', {
  ...travelProfile, contactName: 'Newest Repair Profile',
});
releaseRepairAppend();
const repairedReturn = await pendingRepair;
const repairedReload = await repairRaceRepository.accountById('user-repair-race');
assert.equal(patchedRepairRace.travelProfile.contactName, 'Newest Repair Profile');
assert.equal(repairedReturn.travelProfile.contactName, 'Newest Repair Profile');
assert.equal(repairedReload.travelProfile.contactName, 'Newest Repair Profile');

const malformedTimestampData = new Map();
const malformedSnapshot = structuredClone(seeded);
malformedSnapshot.id = 'user-malformed';
malformedSnapshot.travelProfile.updatedAt = 'not-a-date';
malformedTimestampData.set('accounts/users/user-malformed.json', malformedSnapshot);
malformedTimestampData.set('accounts/profiles/user-malformed.json', { ...travelProfile, contactName: 'Bad Fixed', updatedAt: 'bad' });
malformedTimestampData.set('accounts/profiles/user-malformed/revisions/bad.json', { ...travelProfile, contactName: 'Bad Revision', updatedAt: 'bad' });
const malformedTimestampRepository = createAccountRepository({
  read: async (path) => malformedTimestampData.has(path) ? structuredClone(malformedTimestampData.get(path)) : null,
  write: async (path, value) => { malformedTimestampData.set(path, structuredClone(value)); },
  list: async (prefix) => [...malformedTimestampData.keys()].filter((path) => path.startsWith(prefix)),
  subjectId: (subject) => `user-${subject}`,
});
const malformedResolved = await malformedTimestampRepository.accountById('user-malformed');
assert.notEqual(malformedResolved.travelProfile.contactName, 'Bad Fixed');
assert.notEqual(malformedResolved.travelProfile.contactName, 'Bad Revision');
assert.match(malformedResolved.travelProfile.updatedAt, /^\d{4}-\d{2}-\d{2}T/);
for (const malformed of [9999, {}, [], null]) {
  malformedTimestampData.set(`accounts/profiles/user-malformed/revisions/type-${String(malformed)}.json`, { ...travelProfile, updatedAt: malformed });
}
assert.equal((await malformedTimestampRepository.accountById('user-malformed')).travelProfile.contactName, malformedResolved.travelProfile.contactName);

const equalTimeData = new Map();
const equalTime = '2026-07-26T08:00:00.000Z';
const equalSnapshot = { ...seeded, id: 'user-equal', travelProfile: { ...travelProfile, contactName: 'Seed S', updatedAt: equalTime } };
equalTimeData.set('accounts/users/user-equal.json', equalSnapshot);
equalTimeData.set('accounts/profiles/user-equal.json', { ...travelProfile, contactName: 'Fixed S', updatedAt: equalTime });
equalTimeData.set('accounts/profiles/user-equal/revisions/old.json', { ...travelProfile, contactName: 'Bare S', updatedAt: equalTime });
equalTimeData.set('accounts/profiles/user-equal/revisions/new.json', { profile: { ...travelProfile, contactName: 'Patch N', updatedAt: equalTime }, kind: 'userUpdate', revisionId: 'n', writtenAt: equalTime });
const equalRepository = createAccountRepository({
  read: async (path) => equalTimeData.has(path) ? structuredClone(equalTimeData.get(path)) : null,
  write: async (path, value) => { equalTimeData.set(path, structuredClone(value)); },
  list: async (prefix) => [...equalTimeData.keys()].filter((path) => path.startsWith(prefix)),
  subjectId: (subject) => `user-${subject}`,
});
assert.equal((await equalRepository.accountById('user-equal')).travelProfile.contactName, 'Patch N');
const orderingData = new Map();
const orderingAccount = { ...equalSnapshot, id: 'user-ordering' };
orderingData.set('accounts/users/user-ordering.json', orderingAccount);
const orderingPrefix = 'accounts/profiles/user-ordering/revisions/';
orderingData.set(`${orderingPrefix}a.json`, { profile: { ...travelProfile, contactName: 'Path A', updatedAt: equalTime }, kind: 'appleSeed', revisionId: 'same', writtenAt: equalTime });
orderingData.set(`${orderingPrefix}z.json`, { profile: { ...travelProfile, contactName: 'Path Z', updatedAt: equalTime }, kind: 'appleSeed', revisionId: 'same', writtenAt: equalTime });
const orderedRead = (reverse) => createAccountRepository({
  read: async (path) => orderingData.has(path) ? structuredClone(orderingData.get(path)) : null,
  write: async (path, value) => { orderingData.set(path, structuredClone(value)); },
  list: async (prefix) => [...orderingData.keys()].filter((path) => path.startsWith(prefix)).sort(reverse ? (a, b) => b > a ? 1 : -1 : (a, b) => a > b ? 1 : -1),
  subjectId: (subject) => `user-${subject}`,
});
assert.equal((await orderedRead(false).accountById('user-ordering')).travelProfile.contactName, 'Path Z');
assert.equal((await orderedRead(true).accountById('user-ordering')).travelProfile.contactName, 'Path Z');
for (const badEnvelope of [
  { profile: { ...travelProfile, contactName: 'Bad kind', updatedAt: equalTime }, kind: 'bad', revisionId: 'x', writtenAt: equalTime },
  { profile: { ...travelProfile, contactName: 'Bad id', updatedAt: equalTime }, kind: 'userUpdate', revisionId: {}, writtenAt: equalTime },
  { profile: { ...travelProfile, contactName: 'Bad written', updatedAt: equalTime }, kind: 'userUpdate', revisionId: 'x', writtenAt: 'bad' },
]) equalTimeData.set(`accounts/profiles/user-equal/revisions/bad-${Math.random()}.json`, badEnvelope);
assert.equal((await equalRepository.accountById('user-equal')).travelProfile.contactName, 'Patch N');

const equalRaceData = new Map();
const equalRaceAccount = { ...equalSnapshot, id: 'user-equal-race' };
equalRaceData.set('accounts/users/user-equal-race.json', equalRaceAccount);
let pauseEqualSeed = true; let equalSeedStarted; let releaseEqualSeed;
const equalSeedGate = new Promise((resolve) => { equalSeedStarted = resolve; });
const releaseEqualGate = new Promise((resolve) => { releaseEqualSeed = resolve; });
const equalStore = {
  read: async (path) => equalRaceData.has(path) ? structuredClone(equalRaceData.get(path)) : null,
  write: async (path, value) => {
    if (pauseEqualSeed && path.startsWith('accounts/profiles/user-equal-race/revisions/')) { pauseEqualSeed = false; equalSeedStarted(); await releaseEqualGate; }
    equalRaceData.set(path, structuredClone(value));
  },
  list: async (prefix) => [...equalRaceData.keys()].filter((path) => path.startsWith(prefix)),
  subjectId: (subject) => `user-${subject}`,
  now: () => equalTime,
};
const equalMigrationRepository = createAccountRepository(equalStore);
const equalPatchRepository = createAccountRepository(equalStore);
const delayedEqualMigration = equalMigrationRepository.accountById('user-equal-race');
await equalSeedGate;
const equalPatch = await equalPatchRepository.updateTravelProfile('user-equal-race', { ...travelProfile, contactName: 'Equal Patch N' });
releaseEqualSeed();
const equalMigration = await delayedEqualMigration;
const equalReload = await equalMigrationRepository.accountById('user-equal-race');
assert.equal(equalPatch.travelProfile.contactName, 'Equal Patch N');
assert.equal(equalMigration.travelProfile.contactName, 'Equal Patch N');
assert.equal(equalReload.travelProfile.contactName, 'Equal Patch N');

const firstSeedData = new Map();
let firstSeedProfileWriteStarted;
let releaseFirstSeedProfileWrite;
const firstSeedProfileWriteGate = new Promise((resolve) => { firstSeedProfileWriteStarted = resolve; });
const releaseFirstSeedGate = new Promise((resolve) => { releaseFirstSeedProfileWrite = resolve; });
const firstSeedRepository = createAccountRepository({
  read: async (path) => firstSeedData.has(path) ? structuredClone(firstSeedData.get(path)) : null,
  write: async (path, value) => {
    if (path.startsWith('accounts/profiles/user-apple-first/revisions/')) {
      firstSeedProfileWriteStarted();
      await releaseFirstSeedGate;
    }
    firstSeedData.set(path, structuredClone(value));
  },
  list: async (prefix) => [...firstSeedData.keys()].filter((path) => path.startsWith(prefix)),
  subjectId: (subject) => `user-${subject}`,
});
const firstSeedIdentity = { appleSubject: 'apple-first', email: 'first@example.com', emailVerified: true };
const pendingFirstSeed = firstSeedRepository.upsertAppleAccount(firstSeedIdentity, 'First User');
await firstSeedProfileWriteGate;
assert.equal(await firstSeedRepository.accountById('user-apple-first'), null);
releaseFirstSeedProfileWrite();
await pendingFirstSeed;
await firstSeedRepository.updateTravelProfile('user-apple-first', { ...travelProfile, contactName: 'First Saved' });
assert.equal((await firstSeedRepository.accountById('user-apple-first')).travelProfile.contactName, 'First Saved');

const interleavedData = new Map();
let pauseProfileRead = false;
let profileReadStarted;
let releaseProfileRead;
const profileReadGate = new Promise((resolve) => { profileReadStarted = resolve; });
const releaseGate = new Promise((resolve) => { releaseProfileRead = resolve; });
const interleavedRepository = createAccountRepository({
  read: async (path) => {
    const value = interleavedData.has(path) ? structuredClone(interleavedData.get(path)) : null;
    if (pauseProfileRead && path === 'accounts/profiles/user-apple-race.json') {
      profileReadStarted();
      await releaseGate;
    }
    return value;
  },
  write: async (path, value) => { interleavedData.set(path, structuredClone(value)); },
  list: async (prefix) => [...interleavedData.keys()].filter((path) => path.startsWith(prefix)),
  subjectId: (subject) => `user-${subject}`,
});
const raceIdentity = { appleSubject: 'apple-race', email: 'race@example.com', emailVerified: true };
await interleavedRepository.upsertAppleAccount(raceIdentity, 'Race User');
pauseProfileRead = true;
const interleavedUpsert = interleavedRepository.upsertAppleAccount(raceIdentity, 'Apple Retry');
await profileReadGate;
pauseProfileRead = false;
await interleavedRepository.updateTravelProfile('user-apple-race', { ...travelProfile, contactName: 'Saved Profile' });
releaseProfileRead();
const interleavedReturned = await interleavedUpsert;
assert.equal(interleavedReturned.travelProfile.contactName, 'Saved Profile');
assert.equal((await interleavedRepository.accountById('user-apple-race')).travelProfile.contactName, 'Saved Profile');

const reverseData = new Map();
let pauseProfileWrite = false;
let profileWriteStarted;
let releaseProfileWrite;
const profileWriteGate = new Promise((resolve) => { profileWriteStarted = resolve; });
const releaseWriteGate = new Promise((resolve) => { releaseProfileWrite = resolve; });
const reverseRepository = createAccountRepository({
  read: async (path) => reverseData.has(path) ? structuredClone(reverseData.get(path)) : null,
  write: async (path, value) => {
    if (pauseProfileWrite && path.startsWith('accounts/profiles/user-apple-reverse/revisions/')) {
      profileWriteStarted();
      await releaseWriteGate;
    }
    reverseData.set(path, structuredClone(value));
  },
  list: async (prefix) => [...reverseData.keys()].filter((path) => path.startsWith(prefix)),
  subjectId: (subject) => `user-${subject}`,
});
const reverseIdentity = { appleSubject: 'apple-reverse', email: 'reverse@example.com', emailVerified: true };
await reverseRepository.upsertAppleAccount(reverseIdentity, 'Reverse User');
pauseProfileWrite = true;
const pendingProfileUpdate = reverseRepository.updateTravelProfile('user-apple-reverse', { ...travelProfile, contactName: 'Reverse Saved' });
await profileWriteGate;
pauseProfileWrite = false;
await reverseRepository.upsertAppleAccount(reverseIdentity, 'Apple Retry');
releaseProfileWrite();
await pendingProfileUpdate;
assert.equal((await reverseRepository.accountById('user-apple-reverse')).travelProfile.contactName, 'Reverse Saved');

const handlers = createMeHandlers({
  authenticate: async () => ({ account: seeded, actor: { userId: seeded.id, globalRole: 'user' }, sessionId: 's1' }),
  updateTravelProfile: accountRepository.updateTravelProfile,
  ensureKuzeyTrip: async () => {},
  reconcileKuzeyMembership: async () => {},
  listTripsForUser: async () => [],
});
const getOrder = [];
const migrationHandlers = createMeHandlers({
  authenticate: async () => {
    getOrder.push('authenticate');
    return { account: seeded, actor: { userId: seeded.id, globalRole: 'user' }, sessionId: 's1' };
  },
  updateTravelProfile: accountRepository.updateTravelProfile,
  ensureKuzeyTrip: async () => { getOrder.push('ensureKuzeyTrip'); },
  reconcileKuzeyMembership: async (account) => {
    assert.equal(account.id, seeded.id);
    getOrder.push('reconcileKuzeyMembership');
  },
  listTripsForUser: async () => {
    getOrder.push('listTripsForUser');
    return [];
  },
});
const migrationResponse = await migrationHandlers.GET(new Request('https://test.invalid/api/v2/me'));
assert.equal(migrationResponse.status, 200);
assert.deepEqual(
  getOrder,
  ['authenticate', 'ensureKuzeyTrip', 'reconcileKuzeyMembership', 'listTripsForUser'],
  'session restore migrates pending and existing Kuzey memberships before returning trips',
);
for (const body of [null, [], 'profile', { travelProfile: null }, { travelProfile: [] }, { travelProfile: 'profile' }]) {
  const response = await handlers.PATCH(new Request('https://test.invalid/api/v2/me', {
    method: 'PATCH', body: JSON.stringify(body), headers: { 'content-type': 'application/json' },
  }));
  assert.equal(response.status, 400);
}
const malformed = await handlers.PATCH(new Request('https://test.invalid/api/v2/me', { method: 'PATCH', body: '{' }));
assert.equal(malformed.status, 400);
const nullLanguage = await handlers.PATCH(new Request('https://test.invalid/api/v2/me', {
  method: 'PATCH', body: JSON.stringify({ travelProfile: { ...travelProfile, preferredLanguage: null } }),
}));
assert.equal(nullLanguage.status, 422);
const patched = await handlers.PATCH(new Request('https://test.invalid/api/v2/me', {
  method: 'PATCH', body: JSON.stringify({ travelProfile: { ...travelProfile, contactName: 'Ayşe' } }),
}));
assert.equal(patched.status, 200);
assert.equal((await patched.json()).user.travelProfile.contactName, 'Ayşe');

const accessRequest = new Request('https://test.invalid/api/v2/me', { headers: { authorization: 'Bearer malformed' } });
const authNow = new Date('2026-07-26T08:00:00.000Z');
const authSecret = new TextEncoder().encode('a-test-secret-with-at-least-thirty-two-bytes');
await assert.rejects(verifyRefreshToken('not-a-refresh-token', authSecret, authNow), UnauthorizedError);
await assert.rejects(requireSession(new Request('https://test.invalid'), undefined, authNow), UnauthorizedError);
await assert.rejects(requireSession(accessRequest, new TextEncoder().encode('a-test-secret-with-at-least-thirty-two-bytes'), authNow), UnauthorizedError);
const expired = await issueSession({ id: 'expired', email: null, displayName: null, globalRole: 'user' },
  authSecret, new Date('2026-07-01T00:00:00.000Z'));
await assert.rejects(requireSession(new Request('https://test.invalid', { headers: { authorization: `Bearer ${expired.accessToken}` } }),
  authSecret, authNow), UnauthorizedError);
const wrongSignature = await issueSession({ id: 'wrong-signature', email: null, displayName: null, globalRole: 'user' },
  new TextEncoder().encode('another-test-secret-with-at-least-thirty-two-bytes'), authNow);
await assert.rejects(requireSession(new Request('https://test.invalid', { headers: { authorization: `Bearer ${wrongSignature.accessToken}` } }),
  authSecret, authNow), UnauthorizedError);
const invalidClaims = await new SignJWT({ type: 'access', sid: 'invalid-claims', globalRole: 'not-a-role' })
  .setProtectedHeader({ alg: 'HS256' }).setIssuer('kuzey-api').setAudience('kuzey-ios').setSubject('invalid-claims')
  .setIssuedAt(Math.floor(authNow.getTime() / 1000)).setExpirationTime(Math.floor(authNow.getTime() / 1000) + 300).sign(authSecret);
await assert.rejects(requireSession(new Request('https://test.invalid', { headers: { authorization: `Bearer ${invalidClaims}` } }),
  authSecret, authNow), UnauthorizedError);
const configuredSession = await issueSession({ id: 'config', email: null, displayName: null, globalRole: 'user' }, authSecret, authNow);
await assert.rejects(verifyRefreshToken(configuredSession.accessToken, authSecret, authNow), UnauthorizedError);
const invalidRefreshClaims = await new SignJWT({ type: 'refresh' })
  .setProtectedHeader({ alg: 'HS256' }).setIssuer('kuzey-api').setAudience('kuzey-ios').setSubject('missing-session-id')
  .setIssuedAt(Math.floor(authNow.getTime() / 1000)).setExpirationTime(Math.floor(authNow.getTime() / 1000) + 300).sign(authSecret);
await assert.rejects(verifyRefreshToken(invalidRefreshClaims, authSecret, authNow), UnauthorizedError);
await assert.rejects(requireSession(new Request('https://test.invalid', { headers: { authorization: `Bearer ${configuredSession.accessToken}` } }), undefined, authNow),
  (error) => !(error instanceof UnauthorizedError) && /AUTH_SESSION_SECRET/.test(error.message));
const unauthorized = errorResponse(new UnauthorizedError());
assert.equal(unauthorized.status, 401);
assert.deepEqual(await unauthorized.json(), { error: 'unauthorized', message: 'Oturum açmanız gerekiyor.' });
const revoked = errorResponse(new Error('session_revoked'));
assert.equal(revoked.status, 401);
assert.deepEqual(await revoked.json(), { error: 'session_revoked', message: 'Oturum sona erdi. Yeniden giriş yapın.' });
const forbidden = errorResponse(new TripRepositoryError('forbidden'));
assert.equal(forbidden.status, 403);
assert.equal((await forbidden.json()).error, 'forbidden');
const missingTrip = errorResponse(new TripRepositoryError('trip_not_found'));
assert.equal(missingTrip.status, 404);
assert.equal((await missingTrip.json()).error, 'trip_not_found');
const currentTrip = { id: 'trip-1', revision: 7 };
const conflict = errorResponse(new TripRepositoryError('revision_conflict', 'stale revision', currentTrip));
assert.equal(conflict.status, 409);
assert.deepEqual(await conflict.json(), {
  error: 'revision_conflict',
  message: 'Rota başka bir cihazda değişti. Güncel sürüm yüklendi.',
  current: currentTrip,
});
const invalidStopOrder = errorResponse(new TripRepositoryError('invalid_stop_order'));
assert.equal(invalidStopOrder.status, 422);
assert.equal((await invalidStopOrder.json()).error, 'invalid_stop_order');
const invalidInviteEmail = errorResponse(new TripRepositoryError('invalid_email'));
assert.equal(invalidInviteEmail.status, 422);
assert.equal((await invalidInviteEmail.json()).error, 'invalid_email');
const missingInviteEmail = errorResponse(new TripRepositoryError('invite_email_required'));
assert.equal(missingInviteEmail.status, 422);
assert.equal((await missingInviteEmail.json()).error, 'invite_email_required');
const missingTripOwner = errorResponse(new TripRepositoryError('trip_owner_required'));
assert.equal(missingTripOwner.status, 422);
assert.equal((await missingTripOwner.json()).error, 'trip_owner_required');
const invalidProfile = errorResponse(new Error('invalid_travel_profile'));
assert.equal(invalidProfile.status, 422);
assert.equal((await invalidProfile.json()).error, 'invalid_travel_profile');
const invalidAppleNonce = errorResponse(new Error('invalid_apple_nonce'));
assert.equal(invalidAppleNonce.status, 422);
assert.equal((await invalidAppleNonce.json()).error, 'invalid_apple_nonce');
const missingAccount = errorResponse(new Error('account_not_found'));
assert.equal(missingAccount.status, 404);
assert.equal((await missingAccount.json()).error, 'account_not_found');
const malformedRequest = errorResponse(new Error('invalid_json'));
assert.equal(malformedRequest.status, 400);
assert.equal((await malformedRequest.json()).error, 'invalid_json');
const corruptTrip = errorResponse(new TripRepositoryError('trip_corrupt', 'stored trip data is corrupt'));
assert.equal(corruptTrip.status, 500);
assert.deepEqual(await corruptTrip.json(), { error: 'internal_error', message: 'İşlem tamamlanamadı.' });
const unknown = errorResponse(new Error('database credentials leaked'));
assert.equal(unknown.status, 500);
assert.deepEqual(await unknown.json(), { error: 'internal_error', message: 'İşlem tamamlanamadı.' });
const refreshRequest = () => new Request('https://test.invalid/api/v2/auth/refresh', {
  method: 'POST', body: JSON.stringify({ refreshToken: 'refresh-token' }), headers: { 'content-type': 'application/json' },
});
const refreshHandler = (overrides = {}) => createRefreshHandler({
  accountById: async () => ({ id: 'refresh-user' }),
  revokeSession: async () => {},
  saveSession: async () => {},
  sessionIsActive: async () => true,
  errorResponse,
  issueSession: async () => ({ accessToken: 'fresh-access', refreshToken: 'fresh-refresh', sessionId: 'fresh-session', accessExpiresAt: '2026-07-26T08:15:00.000Z' }),
  json,
  requestJSON,
  verifyRefreshToken: async () => ({ userId: 'refresh-user', sessionId: 'prior-session' }),
  ...overrides,
});
const invalidRefresh = await refreshHandler({
  verifyRefreshToken: (token) => verifyRefreshToken(token, authSecret, authNow),
})(refreshRequest());
assert.equal(invalidRefresh.status, 401);
assert.deepEqual(await invalidRefresh.json(), { error: 'unauthorized', message: 'Oturum açmanız gerekiyor.' });
const verifierFailure = await refreshHandler({
  verifyRefreshToken: async () => { throw new Error('AUTH_SESSION_SECRET configuration failed'); },
})(refreshRequest());
assert.equal(verifierFailure.status, 500);
assert.deepEqual(await verifierFailure.json(), { error: 'internal_error', message: 'İşlem tamamlanamadı.' });
const revokedRefresh = await refreshHandler({ sessionIsActive: async () => false })(refreshRequest());
assert.equal(revokedRefresh.status, 401);
assert.deepEqual(await revokedRefresh.json(), { error: 'unauthorized', message: 'Oturum açmanız gerekiyor.' });
const missingRefreshAccount = await refreshHandler({ accountById: async () => null })(refreshRequest());
assert.equal(missingRefreshAccount.status, 401);
assert.deepEqual(await missingRefreshAccount.json(), { error: 'unauthorized', message: 'Oturum açmanız gerekiyor.' });
const unauthorizedHandlers = createMeHandlers({
  authenticate: async () => { throw new UnauthorizedError(); },
  updateTravelProfile: accountRepository.updateTravelProfile,
  ensureKuzeyTrip: async () => {},
  reconcileKuzeyMembership: async () => {},
  listTripsForUser: async () => [],
});
const unauthorizedPatch = await unauthorizedHandlers.PATCH(new Request('https://test.invalid/api/v2/me', {
  method: 'PATCH', body: JSON.stringify({ travelProfile }),
}));
assert.equal(unauthorizedPatch.status, 401);
assert.deepEqual(await unauthorizedPatch.json(), { error: 'unauthorized', message: 'Oturum açmanız gerekiyor.' });

const { publicKey, privateKey } = await generateKeyPair('ES256');
const publicJwk = await exportJWK(publicKey);
publicJwk.kid = 'apple-test-key';
publicJwk.alg = 'ES256';
const appleKeys = createLocalJWKSet({ keys: [publicJwk] });
const rawNonce = 'nonce-created-on-the-device';
const nonce = createHash('sha256').update(rawNonce).digest('hex');
const now = new Date('2026-07-26T08:00:00.000Z');

const identityToken = await new SignJWT({
  email: 'senturk.bilal@icloud.com',
  email_verified: 'true',
  nonce,
})
  .setProtectedHeader({ alg: 'ES256', kid: 'apple-test-key' })
  .setIssuer('https://appleid.apple.com')
  .setAudience('com.bilalsenturk.kuzey')
  .setSubject('apple-user-123')
  .setIssuedAt(Math.floor(now.getTime() / 1000))
  .setExpirationTime(Math.floor(now.getTime() / 1000) + 300)
  .sign(privateKey);

const identity = await verifyAppleIdentityToken(identityToken, rawNonce, {
  keySet: appleKeys,
  now,
});
assert.deepEqual(identity, {
  appleSubject: 'apple-user-123',
  email: 'senturk.bilal@icloud.com',
  emailVerified: true,
});

await assert.rejects(
  verifyAppleIdentityToken(identityToken, 'different-nonce', { keySet: appleKeys, now }),
  /invalid_apple_nonce/,
);

const wrongAudienceToken = await new SignJWT({ nonce })
  .setProtectedHeader({ alg: 'ES256', kid: 'apple-test-key' })
  .setIssuer('https://appleid.apple.com')
  .setAudience('wrong.bundle')
  .setSubject('apple-user-123')
  .setIssuedAt(Math.floor(now.getTime() / 1000))
  .setExpirationTime(Math.floor(now.getTime() / 1000) + 300)
  .sign(privateKey);
await assert.rejects(
  verifyAppleIdentityToken(wrongAudienceToken, rawNonce, { keySet: appleKeys, now }),
  /unexpected.*audience|aud.*claim/i,
);

const sessionSecret = new TextEncoder().encode('a-test-secret-with-at-least-thirty-two-bytes');
const session = await issueSession({
  id: 'user-hash-123',
  email: 'senturk.bilal@icloud.com',
  displayName: 'Bilal Şentürk',
  globalRole: 'globalAdmin',
}, sessionSecret, now);

const access = await verifyAccessToken(session.accessToken, sessionSecret, now);
assert.equal(access.userId, 'user-hash-123');
assert.equal(access.globalRole, 'globalAdmin');

const refresh = await verifyRefreshToken(session.refreshToken, sessionSecret, now);
assert.equal(refresh.userId, 'user-hash-123');
assert.equal(refresh.sessionId, session.sessionId);

await assert.rejects(verifyAccessToken(session.refreshToken, sessionSecret, now), /invalid_token_type/);

console.log('Account auth checks passed.');
