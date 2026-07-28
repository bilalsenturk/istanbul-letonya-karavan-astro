import type { APIRoute } from 'astro';
import { authenticateRequest, errorResponse, json, requestJSON } from '../../../../../accounts/api.ts';
import { tripEventStorage } from '../../../../../accounts/blobTripStorage.ts';
import { getTripForUser, mutateTrip } from '../../../../../accounts/tripRepository.ts';
import type { RouteStopRecord } from '../../../../../accounts/domain.ts';

export const prerender = false;

export const POST: APIRoute = async ({ request, params }) => {
  try {
    const auth = await authenticateRequest(request);
    const body = await requestJSON<{ baseRevision?: number; stop?: RouteStopRecord }>(request);
    const changed = await mutateTrip(tripEventStorage, auth.actor, {
      tripId: params.id ?? '',
      baseRevision: body.baseRevision ?? -1,
      type: 'stopAdded',
      payload: { stop: body.stop },
    });
    return json({ trip: await getTripForUser(tripEventStorage, auth.actor, changed.id) }, 201);
  } catch (error) {
    return errorResponse(error);
  }
};

export const PATCH: APIRoute = async ({ request, params }) => {
  try {
    const auth = await authenticateRequest(request);
    const body = await requestJSON<{
      baseRevision?: number;
      stopId?: string;
      changes?: Partial<RouteStopRecord>;
      stopIds?: string[];
      stops?: RouteStopRecord[];
    }>(request);
    const replaced = Array.isArray(body.stops);
    const reordered = !replaced && Array.isArray(body.stopIds);
    const changed = await mutateTrip(tripEventStorage, auth.actor, {
      tripId: params.id ?? '',
      baseRevision: body.baseRevision ?? -1,
      type: replaced ? 'stopsReplaced' : reordered ? 'stopsReordered' : 'stopUpdated',
      payload: replaced
        ? { stops: body.stops }
        : reordered
          ? { stopIds: body.stopIds }
          : { stopId: body.stopId, changes: body.changes },
    });
    return json({ trip: await getTripForUser(tripEventStorage, auth.actor, changed.id) });
  } catch (error) {
    return errorResponse(error);
  }
};

export const DELETE: APIRoute = async ({ request, params }) => {
  try {
    const auth = await authenticateRequest(request);
    const body = await requestJSON<{ baseRevision?: number; stopId?: string }>(request);
    const changed = await mutateTrip(tripEventStorage, auth.actor, {
      tripId: params.id ?? '',
      baseRevision: body.baseRevision ?? -1,
      type: 'stopRemoved',
      payload: { stopId: body.stopId },
    });
    return json({ trip: await getTripForUser(tripEventStorage, auth.actor, changed.id) });
  } catch (error) {
    return errorResponse(error);
  }
};
