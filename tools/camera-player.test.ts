import { experimental_AstroContainer as AstroContainer } from 'astro/container';
import { expect, test } from 'vitest';

import CameraPlayer from '../src/components/CameraPlayer.astro';

test('nonempty camera content renders the requested child heading and preserves its default', async () => {
  const container = await AstroContainer.create();
  const camera = {
    title: 'Riga merkez kamerası',
    url: 'https://camera.example/live',
    source: 'Fixture source',
    kind: 'web' as const,
  };
  const dayHtml = await container.renderToString(CameraPlayer, {
    props: {
      camera,
      headingLevel: 3,
    },
  });
  const defaultHtml = await container.renderToString(CameraPlayer, { props: { camera } });

  expect(dayHtml).toMatch(/<h3[^>]*>Riga merkez kamerası<\/h3>/);
  expect(dayHtml).toMatch(/<a[^>]*class="open-link"[^>]*>Kamerayı yeni sekmede aç<\/a>/);
  expect(defaultHtml).toMatch(/<h4[^>]*>Riga merkez kamerası<\/h4>/);
});
