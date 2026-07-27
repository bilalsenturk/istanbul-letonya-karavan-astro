import { randomUUID } from 'node:crypto';
import { jwtVerify, SignJWT } from 'jose';
import type { GlobalRole } from './domain.ts';

const issuer = 'kuzey-api';
const audience = 'kuzey-ios';

export class UnauthorizedError extends Error {
  constructor() { super('unauthorized'); }
}

export type SessionUser = {
  id: string;
  email: string | null;
  displayName: string | null;
  globalRole: GlobalRole;
};

export type IssuedSession = {
  accessToken: string;
  refreshToken: string;
  sessionId: string;
  accessExpiresAt: string;
};

export type AccessClaims = {
  userId: string;
  globalRole: GlobalRole;
  sessionId: string;
};

export type RefreshClaims = {
  userId: string;
  sessionId: string;
};

export const sessionSecretFromEnv = (): Uint8Array => {
  const value = import.meta.env.AUTH_SESSION_SECRET;
  if (!value || value.length < 32) throw new Error('AUTH_SESSION_SECRET must contain at least 32 characters');
  return new TextEncoder().encode(value);
};

export const issueSession = async (
  user: SessionUser,
  secret = sessionSecretFromEnv(),
  now = new Date(),
): Promise<IssuedSession> => {
  const sessionId = randomUUID();
  const nowSeconds = Math.floor(now.getTime() / 1000);
  const accessSeconds = 15 * 60;
  const refreshSeconds = 30 * 24 * 60 * 60;
  const common = (type: 'access' | 'refresh') => new SignJWT({
    type,
    sid: sessionId,
    ...(type === 'access' ? { globalRole: user.globalRole } : {}),
  })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuer(issuer)
    .setAudience(audience)
    .setSubject(user.id)
    .setIssuedAt(nowSeconds)
    .setJti(randomUUID());

  const [accessToken, refreshToken] = await Promise.all([
    common('access').setExpirationTime(nowSeconds + accessSeconds).sign(secret),
    common('refresh').setExpirationTime(nowSeconds + refreshSeconds).sign(secret),
  ]);
  return {
    accessToken,
    refreshToken,
    sessionId,
    accessExpiresAt: new Date((nowSeconds + accessSeconds) * 1000).toISOString(),
  };
};

export const verifyAccessToken = async (
  token: string,
  secret = sessionSecretFromEnv(),
  now = new Date(),
): Promise<AccessClaims> => {
  const payload = await verifiedPayload(token, secret, now);
  if (payload.type !== 'access') throw new Error('invalid_token_type');
  if (!payload.sub || typeof payload.sid !== 'string') throw new Error('invalid_session_claims');
  if (payload.globalRole !== 'globalAdmin' && payload.globalRole !== 'user') {
    throw new Error('invalid_global_role');
  }
  return { userId: payload.sub, globalRole: payload.globalRole, sessionId: payload.sid };
};

export const verifyRefreshToken = async (
  token: string,
  secret = sessionSecretFromEnv(),
  now = new Date(),
): Promise<RefreshClaims> => {
  const payload = await verifiedPayload(token, secret, now);
  if (payload.type !== 'refresh') throw new Error('invalid_token_type');
  if (!payload.sub || typeof payload.sid !== 'string') throw new Error('invalid_session_claims');
  return { userId: payload.sub, sessionId: payload.sid };
};

export const requireSession = async (request: Request, secret?: Uint8Array, now = new Date()): Promise<AccessClaims> => {
  const authorization = request.headers.get('authorization');
  if (!authorization?.startsWith('Bearer ')) throw new UnauthorizedError();
  try {
    return await verifyAccessToken(authorization.slice(7), secret ?? sessionSecretFromEnv(), now);
  } catch {
    throw new UnauthorizedError();
  }
};

const verifiedPayload = async (token: string, secret: Uint8Array, now: Date) => {
  const { payload } = await jwtVerify(token, secret, {
    issuer,
    audience,
    currentDate: now,
  });
  return payload;
};
