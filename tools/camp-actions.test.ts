import { experimental_AstroContainer as AstroContainer } from 'astro/container';
import { expect, test } from 'vitest';

import CampActions from '../src/components/CampActions.astro';

const hrefFor = (html: string, text: string) => {
  const match = [...html.matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/g)]
    .find(([, , body]) => body.trim() === text);
  return match?.[1].match(/\bhref="([^"]+)"/)?.[1]?.replaceAll('&amp;', '&') ?? null;
};

test('camp actions render coordinate directions and place fallback behavior', async () => {
  const container = await AstroContainer.create();
  const exactHtml = await container.renderToString(CampActions, {
    props: {
      arrivalTarget: { latitude: 45.2410861, longitude: 20.0255373, websiteURL: 'https://camp.example/' },
      camp: { place: 'Kovilj fallback', link: 'https://alternate.example/' },
    },
  });
  const fallbackHtml = await container.renderToString(CampActions, {
    props: {
      camp: { place: 'Fallback Camping, Riga, Letonya', link: 'https://maps.app.goo.gl/AbCdEf' },
    },
  });

  expect(new URL(hrefFor(exactHtml, 'Kesin kamp rotasını aç')!).searchParams.get('destination'))
    .toBe('45.2410861,20.0255373');
  expect(hrefFor(exactHtml, 'Kamp web sitesi')).toBe('https://camp.example/');
  expect(new URL(hrefFor(fallbackHtml, 'Kesin kamp rotasını aç')!).searchParams.get('destination'))
    .toBe('Fallback Camping, Riga, Letonya');
  expect(hrefFor(fallbackHtml, 'Kamp web sitesi')).toBeNull();
});
