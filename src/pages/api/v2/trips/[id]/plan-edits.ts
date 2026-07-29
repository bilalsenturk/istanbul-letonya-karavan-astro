import type { APIRoute } from 'astro';
import { authenticateRequest, errorResponse, json, requestJSON } from '../../../../../accounts/api.ts';
import { publishedStateStorage } from '../../../../../accounts/blobPublishedStateStorage.ts';
import { tripEventStorage } from '../../../../../accounts/blobTripStorage.ts';
import {
  getPlanEdits,
  putPlanEdits,
  type PublishedStateRepositoryDependencies,
} from '../../../../../accounts/publishedStateRepository.ts';

type RouteContext = { request: Request; params: Record<string, string | undefined> };
type HandlerDependencies = {
  authenticateRequest: typeof authenticateRequest;
  errorResponse: typeof errorResponse;
  json: typeof json;
  requestJSON: typeof requestJSON;
  repositoryDependencies: PublishedStateRepositoryDependencies;
};

export const prerender = false;

export const createHandlers = (dependencies: HandlerDependencies) => ({
  GET: async ({ request, params }: RouteContext): Promise<Response> => {
    try {
      const auth = await dependencies.authenticateRequest(request);
      return dependencies.json(await getPlanEdits(dependencies.repositoryDependencies, auth.actor, params.id ?? ''));
    } catch (error) {
      return dependencies.errorResponse(error);
    }
  },
  PUT: async ({ request, params }: RouteContext): Promise<Response> => {
    try {
      const auth = await dependencies.authenticateRequest(request);
      const body = await dependencies.requestJSON<unknown>(request);
      return dependencies.json(await putPlanEdits(dependencies.repositoryDependencies, auth.actor, params.id ?? '', body));
    } catch (error) {
      return dependencies.errorResponse(error);
    }
  },
});

const handlers = createHandlers({
  authenticateRequest,
  errorResponse,
  json,
  requestJSON,
  repositoryDependencies: { tripStorage: tripEventStorage, publishedStateStorage },
});

export const GET: APIRoute = (context) => handlers.GET(context);
export const PUT: APIRoute = (context) => handlers.PUT(context);
