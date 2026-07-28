import type { APIRoute } from 'astro';
import { accountByEmail } from '../../../../../accounts/accountRepository.ts';
import { authenticateRequest, errorResponse, json, requestJSON } from '../../../../../accounts/api.ts';
import { tripEventStorage } from '../../../../../accounts/blobTripStorage.ts';
import { getTripForUser, inviteMember, mutateTrip } from '../../../../../accounts/tripRepository.ts';
import type { TripRole } from '../../../../../accounts/domain.ts';

export const prerender = false;

export const GET: APIRoute = async ({ request, params }) => {
  try {
    const auth = await authenticateRequest(request);
    const trip = await getTripForUser(tripEventStorage, auth.actor, params.id ?? '');
    return json({ members: trip.members, invites: trip.invites, access: trip.access });
  } catch (error) {
    return errorResponse(error);
  }
};

export const POST: APIRoute = async ({ request, params }) => {
  try {
    const auth = await authenticateRequest(request);
    const body = await requestJSON<{
      baseRevision?: number;
      email?: string;
      role?: Exclude<TripRole, 'owner'>;
    }>(request);
    const email = body.email ?? '';
    const existing = await accountByEmail(email);
    const changed = existing
      ? await mutateTrip(tripEventStorage, auth.actor, {
        tripId: params.id ?? '',
        baseRevision: body.baseRevision ?? -1,
        type: 'memberAdded',
        payload: { userId: existing.id, role: body.role },
      })
      : await inviteMember(tripEventStorage, auth.actor, {
        tripId: params.id ?? '',
        baseRevision: body.baseRevision ?? -1,
        email,
        role: body.role ?? 'member',
      });
    return json({ trip: await getTripForUser(tripEventStorage, auth.actor, changed.id) }, 201);
  } catch (error) {
    return errorResponse(error);
  }
};

export const PATCH: APIRoute = async ({ request, params }) => {
  try {
    const auth = await authenticateRequest(request);
    const body = await requestJSON<{ baseRevision?: number; userId?: string; role?: TripRole }>(request);
    const changed = await mutateTrip(tripEventStorage, auth.actor, {
      tripId: params.id ?? '',
      baseRevision: body.baseRevision ?? -1,
      type: 'memberRoleChanged',
      payload: { userId: body.userId, role: body.role },
    });
    return json({ trip: await getTripForUser(tripEventStorage, auth.actor, changed.id) });
  } catch (error) {
    return errorResponse(error);
  }
};

export const DELETE: APIRoute = async ({ request, params }) => {
  try {
    const auth = await authenticateRequest(request);
    const body = await requestJSON<{ baseRevision?: number; userId?: string; email?: string }>(request);
    const changed = await mutateTrip(tripEventStorage, auth.actor, {
      tripId: params.id ?? '',
      baseRevision: body.baseRevision ?? -1,
      type: body.email ? 'inviteRemoved' : 'memberRemoved',
      payload: body.email ? { email: body.email } : { userId: body.userId },
    });
    return json({ trip: await getTripForUser(tripEventStorage, auth.actor, changed.id) });
  } catch (error) {
    return errorResponse(error);
  }
};
