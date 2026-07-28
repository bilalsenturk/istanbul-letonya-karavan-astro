import type { APIRoute } from 'astro';
import { authenticateRequest, errorResponse, json, requestJSON } from '../../../../accounts/api.ts';
import { tripEventStorage } from '../../../../accounts/blobTripStorage.ts';
import { getTripForUser, mutateTrip } from '../../../../accounts/tripRepository.ts';

export const prerender = false;

export const GET: APIRoute = async ({ request, params }) => {
  try {
    const auth = await authenticateRequest(request);
    return json({ trip: await getTripForUser(tripEventStorage, auth.actor, params.id ?? '') });
  } catch (error) {
    return errorResponse(error);
  }
};

export const PATCH: APIRoute = async ({ request, params }) => {
  try {
    const auth = await authenticateRequest(request);
    const body = await requestJSON<{ baseRevision?: number; name?: string; transportMode?: string }>(request);
    const changed = await mutateTrip(tripEventStorage, auth.actor, {
      tripId: params.id ?? '',
      baseRevision: body.baseRevision ?? -1,
      type: 'tripUpdated',
      payload: { name: body.name, transportMode: body.transportMode },
    });
    return json({ trip: await getTripForUser(tripEventStorage, auth.actor, changed.id) });
  } catch (error) {
    return errorResponse(error);
  }
};
