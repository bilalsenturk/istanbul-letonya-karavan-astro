import type { APIRoute } from 'astro';
import { revokeSession } from '../../../../accounts/accountRepository.ts';
import { authenticateRequest, errorResponse, json } from '../../../../accounts/api.ts';

export const prerender = false;

export const POST: APIRoute = async ({ request }) => {
  try {
    const auth = await authenticateRequest(request);
    await revokeSession(auth.sessionId);
    return json({ ok: true });
  } catch (error) {
    return errorResponse(error);
  }
};
