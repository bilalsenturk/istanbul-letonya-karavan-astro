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
const blobToken = import.meta.env.LIVE_BLOB_READ_WRITE_TOKEN || import.meta.env.BLOB_READ_WRITE_TOKEN;

const fallbackRecord = () => JSON.stringify({
  lat: 41.0201024108056,
  lng: 29.099259743749787,
  speedKmh: 0,
  city: 'Ümraniye',
  nextStop: 'Sofya',
  nextFlag: '🇧🇬',
  remainingKm: null,
  remainingToFinalKm: null,
  remainingMin: null,
  traveledKm: 0,
  legProgress: 0,
  journeyStarted: false,
  activeRouteStop: null,
  activeRouteCode: null,
  activeRouteStartedAt: null,
  altitudeMeters: null,
  altitudeKind: null,
  altitudeSource: null,
  pressureHpa: null,
  altitudeAvailable: false,
  ts: '2026-07-22T17:15:12.121Z',
  receivedAt: '2026-07-22T17:15:12.121Z',
});

const sanitizeRecordText = (data: string): string => {
  try {
    const record = JSON.parse(data) as Record<string, unknown>;
    if (record.journeyStarted !== true) {
      record.traveledKm = 0;
      record.legProgress = 0;
      record.activeRouteStop = null;
      record.activeRouteCode = null;
      record.activeRouteStartedAt = null;
    }
    return JSON.stringify(record);
  } catch {
    return data;
  }
};

export const POST: APIRoute = async ({ request }) => {
  const secret = import.meta.env.LIVE_POST_SECRET;
  if (!secret || request.headers.get('x-live-secret') !== secret) {
    return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401 });
  }

  let body: {
    lat?: number; lng?: number; speedKmh?: number; ts?: string;
    city?: string; nextStop?: string; nextFlag?: string;
    remainingKm?: number; remainingToFinalKm?: number; remainingMin?: number; traveledKm?: number; legProgress?: number;
    journeyStarted?: boolean; activeRouteStop?: string; activeRouteCode?: string; activeRouteStartedAt?: string;
    altitudeMeters?: number; altitudeKind?: string; altitudeSource?: string; pressureHpa?: number; altitudeAvailable?: boolean;
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
  const journeyStarted = body.journeyStarted === true;

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
    traveledKm: journeyStarted ? num(body.traveledKm) : 0,
    legProgress: journeyStarted ? num(body.legProgress) : 0,
    journeyStarted,
    activeRouteStop: journeyStarted ? str(body.activeRouteStop) : null,
    activeRouteCode: journeyStarted ? str(body.activeRouteCode) : null,
    activeRouteStartedAt: journeyStarted ? str(body.activeRouteStartedAt) : null,
    altitudeMeters: num(body.altitudeMeters),
    altitudeKind: body.altitudeKind === 'absolute' || body.altitudeKind === 'relative' ? body.altitudeKind : null,
    altitudeSource: body.altitudeSource === 'barometer' || body.altitudeSource === 'gps' ? body.altitudeSource : null,
    pressureHpa: num(body.pressureHpa),
    altitudeAvailable: body.altitudeAvailable === true,
    ts: ts ?? new Date().toISOString(),
    receivedAt: new Date().toISOString(),
  };

  const payload = JSON.stringify(record);
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

  return new Response(JSON.stringify({ ok: true }), { headers: liveHeaders });
};

export const GET: APIRoute = async () => {
  if (!blobToken) {
    if (memRecord) return new Response(sanitizeRecordText(memRecord), { headers: liveHeaders });
    return new Response(fallbackRecord(), { headers: liveHeaders });
  }
  try {
    const meta = await head(BLOB_PATH, { token: blobToken });
    const res = await fetch(meta.downloadUrl, { cache: 'no-store' });
    const data = await res.text();
    return new Response(sanitizeRecordText(data), { headers: liveHeaders });
  } catch {
    return new Response(fallbackRecord(), { headers: liveHeaders });
  }
};
