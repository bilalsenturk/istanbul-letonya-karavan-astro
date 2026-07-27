import { createHash } from 'node:crypto';
import {
  createRemoteJWKSet,
  jwtVerify,
  type JWTVerifyGetKey,
} from 'jose';

const appleIssuer = 'https://appleid.apple.com';
const appleAudience = 'com.bilalsenturk.kuzey';
const appleKeys = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));

export type AppleIdentity = {
  appleSubject: string;
  email: string | null;
  emailVerified: boolean;
};

type VerifyAppleOptions = {
  keySet?: JWTVerifyGetKey;
  now?: Date;
  audience?: string;
};

export const verifyAppleIdentityToken = async (
  identityToken: string,
  rawNonce: string,
  options: VerifyAppleOptions = {},
): Promise<AppleIdentity> => {
  if (!identityToken || !rawNonce) throw new Error('apple_credentials_required');
  const { payload } = await jwtVerify(identityToken, options.keySet ?? appleKeys, {
    issuer: appleIssuer,
    audience: options.audience ?? appleAudience,
    currentDate: options.now,
  });

  const expectedNonce = createHash('sha256').update(rawNonce).digest('hex');
  if (payload.nonce !== expectedNonce) throw new Error('invalid_apple_nonce');
  if (!payload.sub) throw new Error('apple_subject_required');

  const email = typeof payload.email === 'string' ? payload.email.trim().toLocaleLowerCase('en-US') : null;
  const emailVerified = payload.email_verified === true || payload.email_verified === 'true';
  return {
    appleSubject: payload.sub,
    email: emailVerified ? email : null,
    emailVerified,
  };
};
