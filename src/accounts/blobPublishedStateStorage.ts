import type { PublishedResource, PublishedStateEnvelope, PublishedStateStorage } from './publishedState.ts';
import { readPrivateJSONWithETag, writePrivateJSONConditional } from './privateBlob.ts';

const pathnameFor = (tripId: string, resource: PublishedResource): string =>
  `accounts/trips/${tripId}/state/${resource}.json`;

export class BlobPublishedStateStorage implements PublishedStateStorage {
  async read<T>(tripId: string, resource: PublishedResource): Promise<{ state: PublishedStateEnvelope<T>; etag: string } | null> {
    const result = await readPrivateJSONWithETag<PublishedStateEnvelope<T>>(pathnameFor(tripId, resource));
    return result && { state: result.value, etag: result.etag };
  }

  async write<T>(
    tripId: string,
    resource: PublishedResource,
    state: PublishedStateEnvelope<T>,
    expectedEtag: string | null,
  ): Promise<{ state: PublishedStateEnvelope<T>; etag: string }> {
    const { etag } = await writePrivateJSONConditional(pathnameFor(tripId, resource), state, expectedEtag);
    return { state, etag };
  }
}

export const publishedStateStorage = new BlobPublishedStateStorage();
