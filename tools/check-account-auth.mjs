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
import { errorResponse } from '../src/accounts/api.ts';
import { createMeHandlers } from '../src/accounts/meHandler.ts';
import { UnauthorizedError, issueSession, requireSession, verifyAccessToken, verifyRefreshToken } from '../src/accounts/session.ts';

const travelProfile = normalizeTravelProfile({
  contactName: ' Bilal Şentürk ', contactEmail: ' BILAL@EXAMPLE.COM ',
  adults: 2, children: 0, vehicleDescription: 'VW Passat + Adria',
  totalLengthMeters: 10.8, needsElectricity: true, hasPet: false,
  additionalNeeds: '', preferredLanguage: 'english', updatedAt: 'client-controlled',
});
assert.equal(travelProfile.contactName, 'Bilal Şentürk');
assert.equal(travelProfile.contactEmail, 'bilal@example.com');
assert.equal(travelProfile.updatedAt, 'client-controlled');
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
  ...travelProfile, contactName: 'Leyla', updatedAt: 'client-time',
});
assert.equal(saved.travelProfile.contactName, 'Leyla');
assert.notEqual(saved.travelProfile.updatedAt, 'client-time');
const reauthenticated = await accountRepository.upsertAppleAccount({
  appleSubject: 'apple-1', email: 'bilal@example.com', emailVerified: true,
}, 'Changed Apple Name');
assert.equal(reauthenticated.travelProfile.contactName, 'Leyla');
await assert.rejects(accountRepository.updateTravelProfile('missing', travelProfile), /account_not_found/);

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
await interleavedUpsert;
assert.equal(interleavedData.get('accounts/users/user-apple-race.json').travelProfile.contactName, 'Race User');
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
    if (pauseProfileWrite && path === 'accounts/profiles/user-apple-reverse.json') {
      profileWriteStarted();
      await releaseWriteGate;
    }
    reverseData.set(path, structuredClone(value));
  },
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
  listTripsForUser: async () => [],
});
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
await assert.rejects(requireSession(accessRequest, new TextEncoder().encode('a-test-secret-with-at-least-thirty-two-bytes'), authNow), UnauthorizedError);
const expired = await issueSession({ id: 'expired', email: null, displayName: null, globalRole: 'user' },
  new TextEncoder().encode('a-test-secret-with-at-least-thirty-two-bytes'), new Date('2026-07-01T00:00:00.000Z'));
await assert.rejects(requireSession(new Request('https://test.invalid', { headers: { authorization: `Bearer ${expired.accessToken}` } }),
  new TextEncoder().encode('a-test-secret-with-at-least-thirty-two-bytes'), authNow), UnauthorizedError);
const unauthorized = errorResponse(new UnauthorizedError());
assert.equal(unauthorized.status, 401);
assert.deepEqual(await unauthorized.json(), { error: 'unauthorized', message: 'Oturum açmanız gerekiyor.' });
const unauthorizedHandlers = createMeHandlers({
  authenticate: async () => { throw new UnauthorizedError(); },
  updateTravelProfile: accountRepository.updateTravelProfile,
  ensureKuzeyTrip: async () => {},
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
