import type { APIRoute } from 'astro';
import { put, head } from '@vercel/blob';

export const prerender = false;

// PAYLAŞILAN günlük kayıtları. Gizli kayıtlar buraya asla gelmez —
// app yalnızca isShared=true olanları gönderir.
//
// POST: app (x-live-secret) yazar. GET: site okur.

const BLOB_PATH = 'kuzey/journal.json';

const jsonHeaders = {
  'Content-Type': 'application/json',
  'Cache-Control': 'no-store',
  'Access-Control-Allow-Origin': '*',
};

// Yerel dev fallback (Blob yokken dev sunucu belleğinde tutulur).
let memRecord: string | null = null;
const blobToken = import.meta.env.LIVE_BLOB_READ_WRITE_TOKEN || import.meta.env.BLOB_READ_WRITE_TOKEN;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

export const POST: APIRoute = async ({ request }) => {
  const secret = import.meta.env.LIVE_POST_SECRET;
  if (!secret || request.headers.get('x-live-secret') !== secret) {
    return json({ error: 'unauthorized' }, 401);
  }

  let body: { entries?: unknown };
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad json' }, 400);
  }

  if (!Array.isArray(body.entries)) {
    return json({ error: 'bad entries' }, 400);
  }

  // Sınırsız uzunlukta metin/id Blob'a yazılabiliyordu — makul bir üst sınır
  // koy (bozuk/kötü niyetli bir istek depolamayı şişirmesin).
  const MAX_ID_LEN = 200;
  const MAX_TEXT_LEN = 5000;

  const entries = body.entries
    .filter((e): e is Record<string, unknown> => typeof e === 'object' && e !== null)
    .map((e) => ({
      id: String(e.id ?? '').slice(0, MAX_ID_LEN),
      text: String(e.text ?? '').slice(0, MAX_TEXT_LEN),
      // `edits.ts`'deki gibi: sadece string olması yetmez, gerçekten geçerli
      // bir tarih olmalı — aksi halde geçersiz createdAt'e sahip bozuk bir
      // kayıt sessizce siteye yazılır.
      createdAt:
        typeof e.createdAt === 'string' && !Number.isNaN(Date.parse(e.createdAt))
          ? e.createdAt
          : null,
      author: typeof e.author === 'string' ? e.author : null,
      mood: typeof e.mood === 'string' ? e.mood : null,
      stopId: typeof e.stopId === 'string' ? e.stopId : null,
    }))
    .filter((e) => e.id && e.text && e.createdAt);

  const payload = JSON.stringify({ entries, updatedAt: new Date().toISOString() });

  if (blobToken) {
    await put(BLOB_PATH, payload, {
      access: 'public',
      token: blobToken,
      addRandomSuffix: false,
      allowOverwrite: true,
      contentType: 'application/json',
    });
  } else {
    memRecord = payload;
  }

  return json({ ok: true, count: entries.length });
};

export const GET: APIRoute = async () => {
  if (!blobToken) {
    return memRecord
      ? new Response(memRecord, { headers: jsonHeaders })
      : json({ error: 'no data yet' }, 404);
  }
  try {
    const meta = await head(BLOB_PATH, { token: blobToken });
    const res = await fetch(meta.downloadUrl, { cache: 'no-store' });
    return new Response(await res.text(), { headers: jsonHeaders });
  } catch {
    return json({ error: 'no data yet' }, 404);
  }
};
