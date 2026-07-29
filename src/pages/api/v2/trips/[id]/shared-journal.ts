import type { APIRoute } from 'astro';
import { authenticateRequest, errorResponse, json, requestJSON } from '../../../../../accounts/api.ts';
import { publishedStateStorage } from '../../../../../accounts/blobPublishedStateStorage.ts';
import { tripEventStorage } from '../../../../../accounts/blobTripStorage.ts';
import { putPublishedResource, type PublishedStateRepositoryDependencies } from '../../../../../accounts/publishedStateRepository.ts';

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
  PUT: async ({ request, params }: RouteContext): Promise<Response> => {
    try {
      const auth = await dependencies.authenticateRequest(request);
      const body = await dependencies.requestJSON<unknown>(request);
      return dependencies.json(await putPublishedResource(
        dependencies.repositoryDependencies, auth, params.id ?? '', 'shared-journal', body));
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

export const PUT: APIRoute = (context) => handlers.PUT(context);
