import type { APIRoute } from 'astro';
import { upsertAppleAccount, saveSession } from '../../../../accounts/accountRepository.ts';
import { errorResponse, json, requestJSON } from '../../../../accounts/api.ts';
import { verifyAppleIdentityToken } from '../../../../accounts/appleAuth.ts';
import { claimPendingInvites, ensureKuzeyTrip } from '../../../../accounts/bootstrap.ts';
import { tripEventStorage } from '../../../../accounts/blobTripStorage.ts';
import { issueSession } from '../../../../accounts/session.ts';
import { listTripsForUser } from '../../../../accounts/tripRepository.ts';

export const prerender = false;

export const POST: APIRoute = async ({ request }) => {
  try {
    const body = await requestJSON<{
      identityToken?: string;
      rawNonce?: string;
      givenName?: string;
      familyName?: string;
    }>(request);
    const identity = await verifyAppleIdentityToken(body.identityToken ?? '', body.rawNonce ?? '');
    const displayName = [body.givenName, body.familyName].filter(Boolean).join(' ') || null;
    const account = await upsertAppleAccount(identity, displayName);
    await ensureKuzeyTrip(tripEventStorage);
    await claimPendingInvites(tripEventStorage, account);
    const session = await issueSession(account);
    await saveSession(session.sessionId, account.id, new Date(Date.now() + 30 * 24 * 60 * 60 * 1000));
    const trips = await listTripsForUser(tripEventStorage, {
      userId: account.id,
      globalRole: account.globalRole,
    });
    return json({ ...session, user: account, trips });
  } catch (error) {
    return errorResponse(error);
  }
};
