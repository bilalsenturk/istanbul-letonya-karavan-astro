import type { APIRoute } from 'astro';
import { put, head } from '@vercel/blob';

export const prerender = false;

// Kuzey iOS uygulamasından gelen harcama TOPLAMI.
// POST: app yalnızca toplamı yazar (x-live-secret ile korunur) → Vercel Blob.
// GET:  site son toplamı okur. Kalem listesi asla web'e gelmez — cihazda kalır.
//
// Gerekli Vercel env değişkenleri:
//   BLOB_READ_WRITE_TOKEN  (Vercel > Storage > Blob etkinleştirince otomatik)
//   LIVE_POST_SECRET       (app'teki Config.livePostSecret ile aynı)

const BLOB_PATH = 'kuzey/expenses.json';

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
      'Access-Control-Allow-Origin': '*',
    },
  });
}

export const POST: APIRoute = async ({ request }) => {
  const secret = import.meta.env.LIVE_POST_SECRET;
  if (!secret || request.headers.get('x-live-secret') !== secret) {
    return json({ error: 'unauthorized' }, 401);
  }

  // Yerel geliştirmede Blob yapılandırılmamış olabilir; sessizce kabul et.
  if (!import.meta.env.BLOB_READ_WRITE_TOKEN) {
    return json({ ok: true, stored: false });
  }

  let body: { totalEur?: number; count?: number; byCategory?: Record<string, number>; ts?: string };
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad json' }, 400);
  }

  const totalEur = Number(body.totalEur);
  if (!Number.isFinite(totalEur) || totalEur < 0) {
    return json({ error: 'bad total' }, 400);
  }

  const record = {
    totalEur: Math.round(totalEur * 100) / 100,
    count: Number.isFinite(body.count) ? body.count : null,
    byCategory: body.byCategory && typeof body.byCategory === 'object' ? body.byCategory : null,
    ts: typeof body.ts === 'string' ? body.ts : new Date().toISOString(),
    receivedAt: new Date().toISOString(),
  };

  await put(BLOB_PATH, JSON.stringify(record), {
    access: 'public',
    addRandomSuffix: false,
    allowOverwrite: true,
    contentType: 'application/json',
  });

  return json({ ok: true });
};

export const GET: APIRoute = async () => {
  try {
    const meta = await head(BLOB_PATH);
    const res = await fetch(meta.downloadUrl, { cache: 'no-store' });
    const data = await res.text();
    return new Response(data, {
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store',
        'Access-Control-Allow-Origin': '*',
      },
    });
  } catch {
    return json({ error: 'no data yet' }, 404);
  }
};
