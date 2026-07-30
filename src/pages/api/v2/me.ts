import type { APIRoute } from 'astro';
import { authenticateRequest } from '../../../accounts/api.ts';
import { updateTravelProfile } from '../../../accounts/accountRepository.ts';
import { ensureKuzeyTrip, reconcileKuzeyMembership } from '../../../accounts/bootstrap.ts';
import { tripEventStorage } from '../../../accounts/blobTripStorage.ts';
import { listTripsForUser } from '../../../accounts/tripRepository.ts';
import { createMeHandlers } from '../../../accounts/meHandler.ts';

export const prerender = false;

const handlers = createMeHandlers({
  authenticate: authenticateRequest,
  updateTravelProfile,
  ensureKuzeyTrip: () => ensureKuzeyTrip(tripEventStorage),
  reconcileKuzeyMembership: (account) => reconcileKuzeyMembership(tripEventStorage, account),
  listTripsForUser: (actor) => listTripsForUser(tripEventStorage, actor),
});

export const GET: APIRoute = ({ request }) => handlers.GET(request);
export const PATCH: APIRoute = ({ request }) => handlers.PATCH(request);
