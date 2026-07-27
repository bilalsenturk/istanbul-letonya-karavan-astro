import type { AccountRecord, TravelProfileRecord } from './accountRepository.ts';
import { errorResponse, json, requestJSON, type AuthenticatedRequest } from './api.ts';

type MeDependencies = {
  authenticate(request: Request): Promise<AuthenticatedRequest>;
  updateTravelProfile(userId: string, profile: Partial<TravelProfileRecord>): Promise<AccountRecord>;
  ensureKuzeyTrip(): Promise<void>;
  listTripsForUser(actor: AuthenticatedRequest['actor']): Promise<unknown[]>;
};

const isPlainObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value) && Object.getPrototypeOf(value) === Object.prototype;

export const createMeHandlers = (dependencies: MeDependencies) => ({
  GET: async (request: Request): Promise<Response> => {
    try {
      const auth = await dependencies.authenticate(request);
      await dependencies.ensureKuzeyTrip();
      return json({ user: auth.account, trips: await dependencies.listTripsForUser(auth.actor) });
    } catch (error) {
      return errorResponse(error);
    }
  },
  PATCH: async (request: Request): Promise<Response> => {
    try {
      const auth = await dependencies.authenticate(request);
      const body = await requestJSON<unknown>(request);
      if (!isPlainObject(body) || !isPlainObject(body.travelProfile)) throw new Error('invalid_request_body');
      const user = await dependencies.updateTravelProfile(auth.account.id, body.travelProfile as Partial<TravelProfileRecord>);
      return json({ user });
    } catch (error) {
      return errorResponse(error);
    }
  },
});
