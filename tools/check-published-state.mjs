import assert from 'node:assert/strict';
import { createServer } from 'vite';

class MemoryPublishedStateStorage {
  entries = new Map();
  writeCalls = [];

  async read(tripId, resource) {
    return this.entries.get(`${tripId}:${resource}`) ?? null;
  }

  async write(tripId, resource, state, expectedEtag) {
    this.writeCalls.push(expectedEtag);
    const key = `${tripId}:${resource}`;
    const current = this.entries.get(key);
    if ((current && current.etag !== expectedEtag) || (!current && expectedEtag !== null)) {
      throw new Error('private_blob_conflict');
    }
    const next = { state: structuredClone(state), etag: `memory-${this.entries.size + this.writeCalls.length}` };
    this.entries.set(key, next);
    return next;
  }
}

const tripId = 'published-state-check';
const resource = 'shared-journal';
const initialState = {
  schemaVersion: 1,
  tripId,
  revision: 1,
  updatedAt: '2026-07-29T12:00:00.000Z',
  updatedBy: 'owner-1',
  data: { entries: ['İstanbul’dan yola çıktık'] },
};

const memoryStorage = new MemoryPublishedStateStorage();
const created = await memoryStorage.write(tripId, resource, initialState, null);
assert.deepEqual(memoryStorage.writeCalls, [null], 'creates must use a null expected ETag');
await assert.rejects(
  memoryStorage.write(tripId, resource, { ...initialState, revision: 2 }, 'stale-etag'),
  /private_blob_conflict/,
  'stale ETags must reject replacement',
);
const replacement = await memoryStorage.write(
  tripId,
  resource,
  { ...initialState, revision: 2, updatedAt: '2026-07-29T12:05:00.000Z' },
  created.etag,
);
assert.equal(replacement.state.revision, 2, 'successful replacements must persist the next revision');
assert.equal(JSON.stringify(replacement.state).includes('etag'), false, 'API state projections must not expose ETags');

const vite = await createServer({
  root: process.cwd(),
  configFile: false,
  appType: 'custom',
  logLevel: 'silent',
  server: { middlewareMode: true },
});
try {
  const { BlobPublishedStateStorage } = await vite.ssrLoadModule('/src/accounts/blobPublishedStateStorage.ts');
  const { PrivateBlobConflictError, listPrivatePaths } = await vite.ssrLoadModule('/src/accounts/privateBlob.ts');
  const storage = new BlobPublishedStateStorage();
  const localTripId = `${tripId}-local`;
  const localInitialState = { ...initialState, tripId: localTripId };
  const localCreated = await storage.write(localTripId, resource, localInitialState, null);
  assert.deepEqual(
    await listPrivatePaths(`accounts/trips/${localTripId}/state/`),
    [`accounts/trips/${localTripId}/state/${resource}.json`],
    'production storage must use the private published-state path',
  );
  const localRead = await storage.read(localTripId, resource);
  assert.deepEqual(localRead?.state, localInitialState, 'production storage must read its locally persisted envelope');
  assert.equal(JSON.stringify(localRead?.state).includes('etag'), false, 'read API projections must not expose ETags');
  const contenders = await Promise.allSettled([
    storage.write(localTripId, resource, { ...localInitialState, revision: 2 }, localCreated.etag),
    storage.write(localTripId, resource, { ...localInitialState, revision: 2 }, localCreated.etag),
  ]);
  assert.equal(contenders.filter((result) => result.status === 'fulfilled').length, 1, 'one writer must win the stale-ETag race');
  assert.equal(contenders.filter((result) => result.status === 'rejected').length, 1, 'one writer must conflict in the stale-ETag race');
  const winner = contenders.find((result) => result.status === 'fulfilled');
  const loser = contenders.find((result) => result.status === 'rejected');
  assert.notEqual(winner.value.etag, localCreated.etag, 'each successful local write must produce a new opaque ETag');
  assert.ok(loser.reason instanceof PrivateBlobConflictError, 'stale writes must become private-blob conflicts');
} finally {
  await vite.close();
}
