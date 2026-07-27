import type { APIRoute } from 'astro';
import { authenticateRequest, errorResponse, json, requestJSON } from '../../../accounts/api.ts';
import { updateTravelProfile, type TravelProfileRecord } from '../../../accounts/accountRepository.ts';
import { ensureKuzeyTrip } from '../../../accounts/bootstrap.ts';
import { tripEventStorage } from '../../../accounts/blobTripStorage.ts';
import { listTripsForUser } from '../../../accounts/tripRepository.ts';

export const prerender = false;

export const GET: APIRoute = async ({ request }) => {
  try {
    const auth = await authenticateRequest(request);
    await ensureKuzeyTrip(tripEventStorage);
    const trips = await listTripsForUser(tripEventStorage, auth.actor);
    return json({ user: auth.account, trips });
  } catch (error) {
    return errorResponse(error);
  }
};

export const PATCH: APIRoute = async ({ request }) => {
  try {
    const auth = await authenticateRequest(request);
    const body = await requestJSON<{ travelProfile?: TravelProfileRecord }>(request);
    if (!body.travelProfile) throw new Error('invalid_travel_profile');
    const user = await updateTravelProfile(auth.account.id, body.travelProfile);
    return json({ user });
  } catch (error) {
    return errorResponse(error);
  }
};
