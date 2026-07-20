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

const liveHeaders = {
  'Content-Type': 'application/json',
  'Cache-Control': 'no-store',
  'Access-Control-Allow-Origin': '*',
};

// Yerel dev fallback (BLOB_READ_WRITE_TOKEN yokken dev sunucu belleğinde tutulur).
let memRecord: string | null = null;

export const POST: APIRoute = async ({ request }) => {
  const secret = import.meta.env.LIVE_POST_SECRET;
  if (!secret || request.headers.get('x-live-secret') !== secret) {
    return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401 });
  }

  let body: {
    lat?: number; lng?: number; speedKmh?: number; ts?: string;
    city?: string; nextStop?: string; nextFlag?: string;
    remainingKm?: number; remainingToFinalKm?: number; remainingMin?: number; traveledKm?: number; legProgress?: number;
  };
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: 'bad json' }), { status: 400 });
  }

  const { lat, lng, speedKmh, ts } = body;
  if (typeof lat !== 'number' || typeof lng !== 'number' || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
    return new Response(JSON.stringify({ error: 'bad coords' }), { status: 400 });
  }

  const num = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null);
  const str = (v: unknown): string | null => (typeof v === 'string' && v.length <= 80 ? v : null);

  // App'in canlı durumu (dinamik site için birebir yansıtılır).
  const record = {
    lat,
    lng,
    speedKmh: typeof speedKmh === 'number' ? Math.max(0, Math.round(speedKmh)) : null,
    city: str(body.city),
    nextStop: str(body.nextStop),
    nextFlag: str(body.nextFlag),
    remainingKm: num(body.remainingKm),
    remainingToFinalKm: num(body.remainingToFinalKm),
    remainingMin: num(body.remainingMin),
    traveledKm: num(body.traveledKm),
    legProgress: num(body.legProgress),
    ts: ts ?? new Date().toISOString(),
    receivedAt: new Date().toISOString(),
  };

  const payload = JSON.stringify(record);
  if (import.meta.env.BLOB_READ_WRITE_TOKEN) {
    await put(BLOB_PATH, payload, {
      access: 'public',
      addRandomSuffix: false,
      allowOverwrite: true,
      contentType: 'application/json',
    });
  } else {
    memRecord = payload;
  }

  return new Response(JSON.stringify({ ok: true }), { headers: liveHeaders });
};

export const GET: APIRoute = async () => {
  if (!import.meta.env.BLOB_READ_WRITE_TOKEN) {
    if (memRecord) return new Response(memRecord, { headers: liveHeaders });
    return new Response(JSON.stringify({ error: 'no data yet' }), { status: 404, headers: liveHeaders });
  }
  try {
    const meta = await head(BLOB_PATH);
    const res = await fetch(meta.downloadUrl, { cache: 'no-store' });
    const data = await res.text();
    return new Response(data, { headers: liveHeaders });
  } catch {
    return new Response(JSON.stringify({ error: 'no data yet' }), { status: 404, headers: liveHeaders });
  }
};
