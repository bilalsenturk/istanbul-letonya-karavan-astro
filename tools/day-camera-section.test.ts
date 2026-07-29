import { experimental_AstroContainer as AstroContainer } from 'astro/container';
import { expect, test } from 'vitest';

import DayCameraSection from '../src/components/DayCameraSection.astro';

const camera = {
  title: 'Riga merkez kamerası',
  url: 'https://camera.example/live',
  source: 'Fixture source',
  kind: 'web' as const,
};

test('the real day camera section renders h2 then h3 with a 44px action', async () => {
  const container = await AstroContainer.create();
  const html = await container.renderToString(DayCameraSection, {
    props: { cameras: [camera] },
  });

  const sectionHeading = html.search(/<h2[^>]*>Şehir Kameraları<\/h2>/);
  const cameraHeading = html.search(/<h3[^>]*>Riga merkez kamerası<\/h3>/);
  const action = html.match(/<a\b[^>]*data-camera-action[^>]*>Kamerayı yeni sekmede aç<\/a>/)?.[0] ?? '';

  expect(sectionHeading).toBeGreaterThanOrEqual(0);
  expect(cameraHeading).toBeGreaterThan(sectionHeading);
  expect(action).toMatch(/class="open-link"/);
  expect(action).toMatch(/style="[^"]*min-height:\s*44px/);
});

test('the real day camera section emits nothing for an empty camera list', async () => {
  const container = await AstroContainer.create();
  const html = await container.renderToString(DayCameraSection, {
    props: { cameras: [] },
  });

  expect(html).not.toContain('Şehir Kameraları');
  expect(html).not.toContain('data-camera-action');
});
