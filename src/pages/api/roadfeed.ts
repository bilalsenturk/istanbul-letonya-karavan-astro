import type { APIRoute } from 'astro';

export const prerender = false;

// Yol bülteni: rota ülkeleri için dizel fiyatı + sınır beklemesi + döviz kuru.
// Anahtar gerektirmeyen kaynaklar burada toplanır; app tek istekle okur.
//
// DÜRÜSTLÜK NOTU (kaynak kalitesi):
//  • Kur      → frankfurter.app (ECB verisi, ücretsiz, anahtarsız) = GERÇEK canlı
//  • Dizel    → AB Weekly Oil Bulletin haftalık yayımlanır ama makine-okunur ücretsiz
//               API'si yok. Bu yüzden temel değerler burada tutulur ve `source`
//               alanında "baseline" olarak işaretlenir. Güncellemesi kolay: aşağıdaki
//               tabloyu değiştir, deploy et.
//  • Sınır    → Kapıkule için resmî, açık ve güvenilir bir JSON API'si YOK.
//               Tahmini yoğunluk penceresi döndürülür ("estimate"), canlı veri değil.

const jsonHeaders = {
  'Content-Type': 'application/json',
  'Cache-Control': 'public, max-age=1800',
  'Access-Control-Allow-Origin': '*',
};

// €/L dizel — AB Oil Bulletin mertebesindeki temel değerler (elle güncellenir).
const DIESEL_BASELINE: Record<string, number> = {
  TR: 1.28,
  BG: 1.34,
  RO: 1.42,
  HU: 1.55,
  SK: 1.49,
  PL: 1.38,
  LT: 1.44,
  LV: 1.47,
};

// Kapıkule yoğunluk tahmini (canlı değil — deneyim temelli pencere).
function borderEstimate() {
  const now = new Date();
  const day = now.getUTCDay();          // 0 Paz … 6 Cmt
  const hour = now.getUTCHours() + 3;   // TR saati
  const weekend = day === 0 || day === 5 || day === 6;
  const peak = hour >= 8 && hour <= 20;
  const level = weekend && peak ? '2–4 saat' : peak ? '1–2 saat' : '30–60 dk';
  return [
    {
      name: 'Kapıkule (TR → BG)',
      outbound: level,
      inbound: null,
      note: weekend
        ? 'Hafta sonu ve gündüz saatleri en yoğun. Gece geçiş belirgin şekilde hızlı.'
        : 'Gece ve sabah erken saatlerde geçiş hızlanır.',
    },
  ];
}

export const GET: APIRoute = async () => {
  // Kur: ECB verisi (gerçek canlı, anahtarsız)
  let rates: Record<string, number> = {};
  try {
    const res = await fetch('https://api.frankfurter.app/latest?from=EUR&to=TRY,BGN,RON,HUF,PLN,USD', {
      signal: AbortSignal.timeout(8000),
    });
    if (res.ok) {
      const data = await res.json();
      rates = { EUR: 1, ...(data?.rates ?? {}) };
    }
  } catch {
    /* kur alınamadı → boş bırak, app zarifçe gizler */
  }

  const body = {
    fuel: Object.entries(DIESEL_BASELINE).map(([country, dieselEur]) => ({ country, dieselEur })),
    borders: borderEstimate(),
    rates,
    updatedAt: new Date().toISOString(),
    sources: [
      'Kur: frankfurter.app (ECB) — canlı',
      'Dizel: AB Weekly Oil Bulletin mertebesinde temel değerler — elle güncellenir',
      'Sınır: deneyim temelli yoğunluk tahmini — canlı veri değil',
    ],
  };

  return new Response(JSON.stringify(body), { headers: jsonHeaders });
};
