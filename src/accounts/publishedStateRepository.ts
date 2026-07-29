import type { AuthenticatedRequest } from './api.ts';
import {
  aggregateExpenses,
  flattenJournal,
  normalizeExpenseSummary,
  normalizeJournalContribution,
  normalizeLiveLocation,
  normalizePlanEdits,
  normalizePublishedPlan,
  type ContributionState,
  type ExpenseSummary,
  type JournalContribution,
  type PlanEditsState,
  type PlanEditsView,
  type PublishedResource,
  type PublishedStateEnvelope,
  type PublishedStateStorage,
} from './publishedState.ts';
import {
  getPublicTrip,
  getTripForAction,
  TripRepositoryError,
  type TripActor,
  type TripEventStorage,
} from './tripRepository.ts';
import type { TripAction } from './domain.ts';

export type PublishedStateRepositoryDependencies = {
  tripStorage: TripEventStorage;
  publishedStateStorage: PublishedStateStorage;
  now?: () => string;
};

const resourceActions: Record<PublishedResource, TripAction> = {
  'live-location': 'startRoute',
  'expense-summary': 'editJournal',
  'plan-edits': 'editStops',
  'published-plan': 'editTrip',
  'shared-journal': 'editJournal',
};

export const getPlanEdits = async (
  dependencies: PublishedStateRepositoryDependencies,
  actor: TripActor,
  tripId: string,
): Promise<PlanEditsView> => {
  await getTripForAction(dependencies.tripStorage, actor, tripId, resourceActions['plan-edits']);
  const current = await dependencies.publishedStateStorage.read<PlanEditsState>(tripId, 'plan-edits');
  return projectPlanEdits(current?.state ?? null, tripId);
};

export const putPlanEdits = async (
  dependencies: PublishedStateRepositoryDependencies,
  actor: TripActor,
  tripId: string,
  input: unknown,
): Promise<PlanEditsView> => {
  await getTripForAction(dependencies.tripStorage, actor, tripId, resourceActions['plan-edits']);
  const normalized = normalizePlanEdits(input);
  const current = await dependencies.publishedStateStorage.read<PlanEditsState>(tripId, 'plan-edits');
  const projected = projectPlanEdits(current?.state ?? null, tripId);
  if (normalized.baseRevision !== projected.revision) conflict(projected);

  const state: PublishedStateEnvelope<PlanEditsState> = {
    schemaVersion: 1,
    tripId,
    revision: projected.revision + 1,
    updatedAt: now(dependencies),
    updatedBy: actor.userId,
    data: normalized.data,
  };
  try {
    const written = await dependencies.publishedStateStorage.write(
      tripId,
      'plan-edits',
      state,
      current?.etag ?? null,
    );
    return projectPlanEdits(written.state, tripId);
  } catch (error) {
    if (!isStorageConflict(error)) throw error;
    const latest = await dependencies.publishedStateStorage.read<PlanEditsState>(tripId, 'plan-edits');
    return conflict(projectPlanEdits(latest?.state ?? null, tripId));
  }
};

export const putPublishedResource = async (
  dependencies: PublishedStateRepositoryDependencies,
  auth: AuthenticatedRequest,
  tripId: string,
  resource: PublishedResource,
  input: unknown,
): Promise<{ ok: true; revision: number; updatedAt: string }> => {
  if (resource === 'plan-edits' || !(resource in resourceActions)) throw new TripRepositoryError('trip_not_found');
  const writableResource = resource as Exclude<PublishedResource, 'plan-edits'>;
  const trip = await getTripForAction(dependencies.tripStorage, auth.actor, tripId, resourceActions[resource]);
  if (trip.kind !== 'kuzey2026') throw new TripRepositoryError('trip_not_found');
  const updatedAt = now(dependencies);
  const normalized = normalizeResource(writableResource, input, auth.account.displayName, updatedAt);

  for (let attempt = 0; attempt < 3; attempt += 1) {
    const current = await dependencies.publishedStateStorage.read<unknown>(tripId, resource);
    requireScopedEnvelope(current?.state ?? null, tripId);
    const state: PublishedStateEnvelope<unknown> = {
      schemaVersion: 1,
      tripId,
      revision: (current?.state.revision ?? 0) + 1,
      updatedAt,
      updatedBy: auth.account.id,
      data: mergeResource(writableResource, current?.state.data, auth.account.id, normalized),
    };
    try {
      const written = await dependencies.publishedStateStorage.write(
        tripId,
        resource,
        state,
        current?.etag ?? null,
      );
      return { ok: true, revision: written.state.revision, updatedAt: written.state.updatedAt };
    } catch (error) {
      if (!isStorageConflict(error)) throw error;
    }
  }
  throw new TripRepositoryError('revision_conflict');
};

export const getPublicPublishedResource = async (
  dependencies: PublishedStateRepositoryDependencies,
  tripId: string,
  resource: PublishedResource,
): Promise<unknown> => {
  if (resource === 'plan-edits' || !isPublicResource(resource)) throw new TripRepositoryError('trip_not_found');
  await getPublicTrip(dependencies.tripStorage, tripId);
  const current = await dependencies.publishedStateStorage.read<unknown>(tripId, resource);
  if (!current) throw new TripRepositoryError('trip_not_found');
  requireScopedEnvelope(current.state, tripId);
  if (resource === 'expense-summary') {
    return aggregateExpenses(current.state.data as ContributionState<ExpenseSummary>);
  }
  if (resource === 'shared-journal') {
    return {
      entries: flattenJournal(current.state.data as ContributionState<JournalContribution>),
      updatedAt: current.state.updatedAt,
    };
  }
  return structuredClone(current.state.data);
};

const normalizeResource = (
  resource: Exclude<PublishedResource, 'plan-edits'>,
  input: unknown,
  displayName: string | null,
  receivedAt: string,
): unknown => {
  if (resource === 'live-location') return normalizeLiveLocation(input, receivedAt);
  if (resource === 'expense-summary') return normalizeExpenseSummary(input, receivedAt);
  if (resource === 'published-plan') return normalizePublishedPlan(input, receivedAt);
  return normalizeJournalContribution(input, displayName, receivedAt);
};

const mergeResource = (
  resource: Exclude<PublishedResource, 'plan-edits'>,
  current: unknown,
  accountId: string,
  normalized: unknown,
): unknown => {
  if (resource !== 'expense-summary' && resource !== 'shared-journal') return normalized;
  const existing = contributionRecord(current);
  return { contributions: { ...existing, [accountId]: normalized } };
};

const contributionRecord = (value: unknown): Record<string, unknown> => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
  const contributions = (value as { contributions?: unknown }).contributions;
  if (!contributions || typeof contributions !== 'object' || Array.isArray(contributions)) return {};
  return contributions as Record<string, unknown>;
};

const projectPlanEdits = (state: PublishedStateEnvelope<PlanEditsState> | null, tripId: string): PlanEditsView => {
  if (!state) return { revision: 0, departureAt: null, days: {}, updatedAt: null };
  requireScopedEnvelope(state, tripId);
  return {
    revision: state.revision,
    departureAt: state.data.departureAt,
    days: structuredClone(state.data.days),
    updatedAt: state.updatedAt,
  };
};

const requireScopedEnvelope = (state: PublishedStateEnvelope<unknown> | null, tripId: string): void => {
  if (state && (state.schemaVersion !== 1 || state.tripId !== tripId || !Number.isInteger(state.revision) || state.revision < 1)) {
    throw new Error('published_state_corrupt');
  }
};

const now = (dependencies: PublishedStateRepositoryDependencies): string =>
  dependencies.now?.() ?? new Date().toISOString();

const conflict = (current: PlanEditsView): never => {
  throw new TripRepositoryError('revision_conflict', 'revision_conflict', current as never);
};

const isStorageConflict = (error: unknown): boolean =>
  error instanceof Error && error.message === 'private_blob_conflict';

const isPublicResource = (resource: unknown): resource is Exclude<PublishedResource, 'plan-edits'> =>
  resource === 'live-location'
  || resource === 'expense-summary'
  || resource === 'published-plan'
  || resource === 'shared-journal';
