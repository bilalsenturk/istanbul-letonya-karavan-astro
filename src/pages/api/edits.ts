import type { APIRoute } from 'astro';
import { put, head } from '@vercel/blob';

export const prerender = false;

// Kullanıcı DÜZENLEMELERİ (kalkış tarihi + gün değişiklikleri) — cihazlar arası
// ortak kaynak. Türetilmiş takvim değil, ham düzenlemeler taşınır: her cihaz
// tarihleri kendi TripPlanner'ıyla hesaplar, böylece tarih mantığı tek yerde kalır.
//
// Yazma yalnızca "plan sahibi" cihazda açıktır (app tarafı kuralı) — iki kişi
// aynı anda oynayınca sessizce veri kaybolmasın diye son-yazan-kazanır yok.
//
// POST: sahip cihaz (x-live-secret) yazar. GET: diğer cihazlar okur.

const BLOB_PATH = 'kuzey/edits.json';

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

  let body: { departureAt?: string | null; days?: Record<string, unknown> };
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad json' }, 400);
  }

  // departureAt ya geçerli bir tarih ya da null (web verisine dön demek).
  if (body.departureAt != null &&
      (typeof body.departureAt !== 'string' || Number.isNaN(Date.parse(body.departureAt)))) {
    return json({ error: 'bad departureAt' }, 400);
  }
  if (body.days != null && (typeof body.days !== 'object' || Array.isArray(body.days))) {
    return json({ error: 'bad days' }, 400);
  }

  const payload = JSON.stringify({
    departureAt: body.departureAt ?? null,
    days: body.days ?? {},
    updatedAt: new Date().toISOString(),
  });

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
