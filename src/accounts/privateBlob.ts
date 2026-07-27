import { get, list, put } from '@vercel/blob';

const memory = new Map<string, string>();

const privateToken = (): string | null => {
  const token = import.meta.env.PRIVATE_BLOB_READ_WRITE_TOKEN ?? import.meta.env.BLOB_READ_WRITE_TOKEN;
  if (token) return token;
  if (import.meta.env.DEV) return null;
  throw new Error('private_blob_not_configured');
};

export const readPrivateJSON = async <T>(pathname: string): Promise<T | null> => {
  const token = privateToken();
  if (!token) {
    const value = memory.get(pathname);
    return value ? JSON.parse(value) as T : null;
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
    memory.set(pathname, payload);
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
