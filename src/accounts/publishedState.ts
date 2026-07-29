export type PublishedResource =
  | 'live-location'
  | 'expense-summary'
  | 'plan-edits'
  | 'published-plan'
  | 'shared-journal';

export type PublishedStateEnvelope<T> = {
  schemaVersion: 1;
  tripId: string;
  revision: number;
  updatedAt: string;
  updatedBy: string;
  data: T;
};

export interface PublishedStateStorage {
  read<T>(tripId: string, resource: PublishedResource): Promise<{ state: PublishedStateEnvelope<T>; etag: string } | null>;
  write<T>(
    tripId: string,
    resource: PublishedResource,
    state: PublishedStateEnvelope<T>,
    expectedEtag: string | null,
  ): Promise<{ state: PublishedStateEnvelope<T>; etag: string }>;
}
