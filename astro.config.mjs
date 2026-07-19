// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import vercel from '@astrojs/vercel';

export default defineConfig({
  site: 'https://istanbul-riga.vercel.app',
  integrations: [sitemap()],
  // Sayfalar statik kalır; yalnızca `prerender = false` işaretli API rotaları
  // (ör. /api/location) sunucuda çalışır.
  adapter: vercel(),
});
