import { BlobPreconditionFailedError, get, list, put } from '@vercel/blob';

type MemoryEntry = { payload: string; etag: string };

const memory = new Map<string, MemoryEntry>();

export class PrivateBlobConflictError extends Error {
  constructor() {
    super('private_blob_conflict');
  }
}

const privateToken = (): string | null => {
  const token = import.meta.env.PRIVATE_BLOB_READ_WRITE_TOKEN ?? import.meta.env.BLOB_READ_WRITE_TOKEN;
  if (token) return token;
  if (import.meta.env.DEV) return null;
  throw new Error('private_blob_not_configured');
};

export const readPrivateJSON = async <T>(pathname: string): Promise<T | null> => {
  const token = privateToken();
  if (!token) {
    const entry = memory.get(pathname);
    return entry ? JSON.parse(entry.payload) as T : null;
  }
  const result = await get(pathname, { access: 'private', token, useCache: false });
  if (!result || result.statusCode !== 200) return null;
  const text = await new Response(result.stream).text();
  return JSON.parse(text) as T;
};

export const writePrivateJSON = async (pathname: string, value: unknown): Promise<void> => {
  const payload = JSON.stringify(value);
  const token = privateToken();
  if (!token) {
    writeMemory(pathname, payload);
    return;
  }
  await put(pathname, payload, {
    access: 'private',
    token,
    contentType: 'application/json',
    addRandomSuffix: false,
    allowOverwrite: true,
    cacheControlMaxAge: 60,
  });
};

export const readPrivateJSONWithETag = async <T>(pathname: string): Promise<{ value: T; etag: string } | null> => {
  const token = privateToken();
  if (!token) {
    const entry = memory.get(pathname);
    return entry ? { value: JSON.parse(entry.payload) as T, etag: entry.etag } : null;
  }
  const result = await get(pathname, { access: 'private', token, useCache: false });
  if (!result || result.statusCode !== 200) return null;
  const text = await new Response(result.stream).text();
  return { value: JSON.parse(text) as T, etag: result.blob.etag };
};

export const writePrivateJSONConditional = async (
  pathname: string,
  value: unknown,
  expectedEtag: string | null,
): Promise<{ etag: string }> => {
  const payload = JSON.stringify(value);
  const token = privateToken();
  if (!token) {
    const current = memory.get(pathname);
    if ((expectedEtag === null && current) || (expectedEtag !== null && current?.etag !== expectedEtag)) {
      throw new PrivateBlobConflictError();
    }
    return { etag: writeMemory(pathname, payload) };
  }
  try {
    const result = await put(pathname, payload, expectedEtag === null ? {
      access: 'private',
      token,
      contentType: 'application/json',
      addRandomSuffix: false,
      allowOverwrite: false,
    } : {
      access: 'private',
      token,
      contentType: 'application/json',
      addRandomSuffix: false,
      ifMatch: expectedEtag,
    });
    return { etag: result.etag };
  } catch (error) {
    if (isBlobConflict(error)) throw new PrivateBlobConflictError();
    throw error;
  }
};

export const createPrivateJSON = async (pathname: string, value: unknown): Promise<{ etag: string }> => {
  return writePrivateJSONConditional(pathname, value, null);
};

export const listPrivatePaths = async (prefix: string): Promise<string[]> => {
  const token = privateToken();
  if (!token) return [...memory.keys()].filter((key) => key.startsWith(prefix)).sort();
  const paths: string[] = [];
  let cursor: string | undefined;
  do {
    const page = await list({ prefix, cursor, limit: 1000, token });
    paths.push(...page.blobs.map((blob) => blob.pathname));
    cursor = page.hasMore ? page.cursor : undefined;
  } while (cursor);
  return paths.sort();
};

const isBlobConflict = (error: unknown): boolean => {
  if (error instanceof BlobPreconditionFailedError) return true;
  if (!error || typeof error !== 'object') return false;
  const details = error as {
    code?: unknown;
    name?: unknown;
    status?: unknown;
    statusCode?: unknown;
    message?: unknown;
  };
  return (
    details.code === 'precondition_failed' ||
    details.code === 'conflict' ||
    details.name === 'BlobPreconditionFailedError' ||
    details.status === 409 ||
    details.status === 412 ||
    details.statusCode === 409 ||
    details.statusCode === 412 ||
    (typeof details.message === 'string' && details.message.includes('Precondition failed'))
  );
};

const writeMemory = (pathname: string, payload: string): string => {
  const etag = crypto.randomUUID();
  memory.set(pathname, { payload, etag });
  return etag;
};
