import type { APIRoute } from 'astro';
import { tripData } from '../data/tripData';

// iOS uygulamasının veri kaynağı: site her deploy olduğunda app içeriği de
// otomatik güncellenir (app bundle'ındaki gömülü kopya yalnızca çevrimdışı yedek).
export const GET: APIRoute = () =>
  new Response(JSON.stringify(tripData), {
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'public, max-age=300',
    },
  });
