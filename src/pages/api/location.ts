import type { APIRoute } from 'astro';
import { put, head } from '@vercel/blob';

export const prerender = false;

// Kuzey iOS uygulamasından gelen canlı konum.
// POST: app konum yazar (x-live-secret ile korunur) → Vercel Blob'a kaydedilir.
// GET:  site son konumu okur.
//
// Gerekli Vercel env değişkenleri:
//   BLOB_READ_WRITE_TOKEN  (Vercel > Storage > Blob etkinleştirince otomatik)
//   LIVE_POST_SECRET       (app'teki Config.livePostSecret ile aynı)

const BLOB_PATH = 'kuzey/live-location.json';

export const POST: APIRoute = async ({ request }) => {
  const secret = import.meta.env.LIVE_POST_SECRET;
  if (!secret || request.headers.get('x-live-secret') !== secret) {
    return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401 });
  }

  let body: { lat?: number; lng?: number; speedKmh?: number; ts?: string };
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: 'bad json' }), { status: 400 });
  }

  const { lat, lng, speedKmh, ts } = body;
  if (typeof lat !== 'number' || typeof lng !== 'number' || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
    return new Response(JSON.stringify({ error: 'bad coords' }), { status: 400 });
  }

  const record = {
    lat,
    lng,
    speedKmh: typeof speedKmh === 'number' ? Math.max(0, Math.round(speedKmh)) : null,
    ts: ts ?? new Date().toISOString(),
    receivedAt: new Date().toISOString(),
  };

  await put(BLOB_PATH, JSON.stringify(record), {
    access: 'public',
    addRandomSuffix: false,
    allowOverwrite: true,
    contentType: 'application/json',
  });

  return new Response(JSON.stringify({ ok: true }), {
    headers: { 'Content-Type': 'application/json' },
  });
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
    return new Response(JSON.stringify({ error: 'no data yet' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
    });
  }
};
