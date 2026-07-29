import type { TripEvent } from './domain.ts';
import { createPrivateJSON, listPrivatePaths, PrivateBlobConflictError, readPrivateJSON } from './privateBlob.ts';
import { TripStorageConflictError, type TripEventStorage } from './tripRepository.ts';

export class BlobTripEventStorage implements TripEventStorage {
  async listTripIds(): Promise<string[]> {
    const paths = await listPrivatePaths('accounts/trips/');
    return [...new Set(paths.map((path) => path.split('/')[2]).filter(Boolean))];
  }

  async list(tripId: string): Promise<TripEvent[]> {
    const paths = await listPrivatePaths(`accounts/trips/${tripId}/events/`);
    const events = await Promise.all(paths.map((path) => readPrivateJSON<TripEvent>(path)));
    return events.filter((event): event is TripEvent => event !== null)
      .sort((left, right) => left.revision - right.revision);
  }

  async append(event: TripEvent, expectedRevision: number): Promise<void> {
    if (event.revision !== expectedRevision + 1) throw new TripStorageConflictError();
    const revision = String(event.revision).padStart(10, '0');
    try {
      await createPrivateJSON(`accounts/trips/${event.tripId}/events/${revision}.json`, event);
    } catch (error) {
      if (error instanceof PrivateBlobConflictError) throw new TripStorageConflictError();
      throw error;
    }
  }
}

export const tripEventStorage = new BlobTripEventStorage();
