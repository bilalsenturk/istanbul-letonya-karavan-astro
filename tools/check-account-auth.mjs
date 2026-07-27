import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import {
  createLocalJWKSet,
  exportJWK,
  generateKeyPair,
  SignJWT,
} from 'jose';
import { verifyAppleIdentityToken } from '../src/accounts/appleAuth.ts';
import { normalizeTravelProfile } from '../src/accounts/accountRepository.ts';
import { issueSession, verifyAccessToken, verifyRefreshToken } from '../src/accounts/session.ts';

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

const [accountRepositorySource, meSource, accountAPISource, accountStoreSource] = await Promise.all([
  readFile(new URL('../src/accounts/accountRepository.ts', import.meta.url), 'utf8'),
  readFile(new URL('../src/pages/api/v2/me.ts', import.meta.url), 'utf8'),
  readFile(new URL('../ios/Karavan/Accounts/AccountAPI.swift', import.meta.url), 'utf8'),
  readFile(new URL('../ios/Karavan/Accounts/AccountSessionStore.swift', import.meta.url), 'utf8'),
]);
assert.match(accountRepositorySource, /export const updateTravelProfile/);
assert.match(accountRepositorySource, /updatedAt:\s*now/);
assert.match(meSource, /export const PATCH/);
assert.match(meSource, /authenticateRequest\(request\)/);
assert.match(meSource, /updateTravelProfile\(auth\.account\.id, body\.travelProfile\)/);
assert.match(accountAPISource, /func updateTravelProfile\(_ profile: AccountTravelProfile, accessToken: String\)/);
assert.match(accountAPISource, /path: "me",\s*method: "PATCH"/s);
assert.match(accountStoreSource, /func saveTravelProfile\(_ profile: AccountTravelProfile\)/);
assert.match(accountStoreSource, /user = updatedUser/);

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
