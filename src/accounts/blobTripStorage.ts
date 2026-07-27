import type { TripEvent } from './domain.ts';
import { listPrivatePaths, readPrivateJSON, writePrivateJSON } from './privateBlob.ts';
import type { TripEventStorage } from './tripRepository.ts';

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

  async append(event: TripEvent): Promise<void> {
    const revision = String(event.revision).padStart(10, '0');
    await writePrivateJSON(`accounts/trips/${event.tripId}/events/${revision}-${event.id}.json`, event);
  }
}

export const tripEventStorage = new BlobTripEventStorage();
