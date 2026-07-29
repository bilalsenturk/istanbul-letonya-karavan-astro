import type { APIRoute } from 'astro';
import { errorResponse, json } from '../../../../../../accounts/api.ts';
import { publishedStateStorage } from '../../../../../../accounts/blobPublishedStateStorage.ts';
import { tripEventStorage } from '../../../../../../accounts/blobTripStorage.ts';
import {
  getPublicPublishedResource,
  type PublishedStateRepositoryDependencies,
} from '../../../../../../accounts/publishedStateRepository.ts';

type RouteContext = { params: Record<string, string | undefined> };
type HandlerDependencies = {
  errorResponse: typeof errorResponse;
  json: typeof json;
  repositoryDependencies: PublishedStateRepositoryDependencies;
};

export const prerender = false;

export const createHandlers = (dependencies: HandlerDependencies) => ({
  GET: async ({ params }: RouteContext): Promise<Response> => {
    try {
      return dependencies.json(
        await getPublicPublishedResource(dependencies.repositoryDependencies, params.id ?? '', 'live-location'),
      );
    } catch (error) {
      return dependencies.errorResponse(error);
    }
  },
});

const handlers = createHandlers({
  errorResponse,
  json,
  repositoryDependencies: { tripStorage: tripEventStorage, publishedStateStorage },
});

export const GET: APIRoute = (context) => handlers.GET(context);
