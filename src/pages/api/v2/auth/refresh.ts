import type { APIRoute } from 'astro';
import { accountById, revokeSession, saveSession, sessionIsActive } from '../../../../accounts/accountRepository.ts';
import { errorResponse, json, requestJSON } from '../../../../accounts/api.ts';
import { issueSession, verifyRefreshToken } from '../../../../accounts/session.ts';

export const prerender = false;

export const POST: APIRoute = async ({ request }) => {
  try {
    const body = await requestJSON<{ refreshToken?: string }>(request);
    const claims = await verifyRefreshToken(body.refreshToken ?? '');
    if (!(await sessionIsActive(claims.sessionId, claims.userId))) throw new Error('session_revoked');
    const account = await accountById(claims.userId);
    if (!account) throw new Error('account_not_found');
    await revokeSession(claims.sessionId);
    const session = await issueSession(account);
    await saveSession(session.sessionId, account.id, new Date(Date.now() + 30 * 24 * 60 * 60 * 1000));
    return json(session);
  } catch (error) {
    return errorResponse(error);
  }
};
