import type { APIRoute } from 'astro';
import { authenticateRequest, errorResponse, json, requestJSON } from '../../../../accounts/api.ts';
import { tripEventStorage } from '../../../../accounts/blobTripStorage.ts';
import { createTrip, getTripForUser, listTripsForUser } from '../../../../accounts/tripRepository.ts';
import type { RouteStopRecord, TransportMode } from '../../../../accounts/domain.ts';

export const prerender = false;

export const GET: APIRoute = async ({ request }) => {
  try {
    const auth = await authenticateRequest(request);
    return json({ trips: await listTripsForUser(tripEventStorage, auth.actor) });
  } catch (error) {
    return errorResponse(error);
  }
};

export const POST: APIRoute = async ({ request }) => {
  try {
    const auth = await authenticateRequest(request);
    const body = await requestJSON<{ name?: string; kind?: string; transportMode?: TransportMode; stops?: RouteStopRecord[] }>(request);
    const created = await createTrip(tripEventStorage, auth.actor, {
      name: body.name ?? '',
      kind: body.kind,
      transportMode: body.transportMode,
      stops: Array.isArray(body.stops) ? body.stops : [],
    });
    return json({ trip: await getTripForUser(tripEventStorage, auth.actor, created.id) }, 201);
  } catch (error) {
    return errorResponse(error);
  }
};
