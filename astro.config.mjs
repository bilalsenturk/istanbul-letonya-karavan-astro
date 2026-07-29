// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import vercel from '@astrojs/vercel';

export default defineConfig({
  site: 'https://istanbul-letonya-karavan-astro.vercel.app',
  integrations: [sitemap()],
  // Sayfalar statik kalır; yalnızca `prerender = false` işaretli API rotaları
  // (ör. /api/v2/trips/[id]) sunucuda çalışır.
  adapter: vercel(),
});
