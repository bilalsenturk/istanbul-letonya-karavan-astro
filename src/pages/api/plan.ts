import type { APIRoute } from 'astro';
import { put, head } from '@vercel/blob';

export const prerender = false;

// Kuzey app'inin HESAPLANMIŞ takvimi (kalkış + gün tarihleri).
// Logic app'te (TripPlanner) tek kaynak; web yalnızca sonucu gösterir —
// böylece tarih türetme mantığı iki yerde tekrarlanmaz.
//
// POST: app (x-live-secret) yazar. GET: site okur; yoksa 404 → site gömülü veriye düşer.

const BLOB_PATH = 'kuzey/plan.json';

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

  let body: {
    departureAt?: string;
    arrivalAt?: string;
    totalDays?: number;
    days?: { slug?: string; date?: string; label?: string; origin?: string; destination?: string; restDay?: boolean; dayCount?: number }[];
  };
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad json' }, 400);
  }

  if (typeof body.departureAt !== 'string' || Number.isNaN(Date.parse(body.departureAt))) {
    return json({ error: 'bad departureAt' }, 400);
  }

  const days = Array.isArray(body.days)
    ? body.days
        .filter((d) => typeof d?.slug === 'string' && typeof d?.date === 'string')
        .slice(0, 60)
        .map((d) => ({
          slug: String(d.slug).slice(0, 80),
          date: String(d.date),
          label: typeof d.label === 'string' ? d.label.slice(0, 60) : null,
          origin: typeof d.origin === 'string' ? d.origin.slice(0, 60) : null,
          destination: typeof d.destination === 'string' ? d.destination.slice(0, 60) : null,
          restDay: d.restDay === true,
          dayCount: Number.isFinite(d.dayCount) ? Number(d.dayCount) : 1,
        }))
    : [];

  const record = {
    departureAt: body.departureAt,
    arrivalAt: typeof body.arrivalAt === 'string' ? body.arrivalAt : null,
    totalDays: Number.isFinite(body.totalDays) ? Number(body.totalDays) : days.length,
    days,
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

  return json({ ok: true });
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
