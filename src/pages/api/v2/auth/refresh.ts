import type { APIRoute } from 'astro';
import { accountById, revokeSession, saveSession, sessionIsActive } from '../../../../accounts/accountRepository.ts';
import { errorResponse, json, requestJSON } from '../../../../accounts/api.ts';
import { issueSession, UnauthorizedError, verifyRefreshToken } from '../../../../accounts/session.ts';

export const prerender = false;

type RefreshDependencies = {
  accountById: typeof accountById;
  revokeSession: typeof revokeSession;
  saveSession: typeof saveSession;
  sessionIsActive: typeof sessionIsActive;
  errorResponse: typeof errorResponse;
  issueSession: typeof issueSession;
  json: typeof json;
  requestJSON: typeof requestJSON;
  verifyRefreshToken: typeof verifyRefreshToken;
};

export const createRefreshHandler = (dependencies: RefreshDependencies) => async (request: Request): Promise<Response> => {
  try {
    const body = await dependencies.requestJSON<{ refreshToken?: string }>(request);
    const claims = await dependencies.verifyRefreshToken(body.refreshToken ?? '');
    if (!(await dependencies.sessionIsActive(claims.sessionId, claims.userId))) throw new UnauthorizedError();
    const account = await dependencies.accountById(claims.userId);
    if (!account) throw new UnauthorizedError();
    await dependencies.revokeSession(claims.sessionId);
    const session = await dependencies.issueSession(account);
    await dependencies.saveSession(session.sessionId, account.id, new Date(Date.now() + 30 * 24 * 60 * 60 * 1000));
    return dependencies.json(session);
  } catch (error) {
    return dependencies.errorResponse(error);
  }
};

const refresh = createRefreshHandler({
  accountById,
  revokeSession,
  saveSession,
  sessionIsActive,
  errorResponse,
  issueSession,
  json,
  requestJSON,
  verifyRefreshToken,
});

export const POST: APIRoute = ({ request }) => refresh(request);
