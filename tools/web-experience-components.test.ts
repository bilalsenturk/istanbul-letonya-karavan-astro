import { Window as HappyDOMWindow } from 'happy-dom';
import { describe, expect, test } from 'vitest';

import {
  buildCampLinks,
  createRouteStatusController,
  initJourneyHero,
} from '../src/scripts/journeyExperience';

describe('camp links', () => {
  test('uses exact coordinates for directions and a place only as fallback', () => {
    const exact = buildCampLinks({
      arrivalTarget: { latitude: 45.2410861, longitude: 20.0255373, websiteURL: null },
      camp: {
        place: 'Branka Bajića 60, Kovilj, Sırbistan',
        link: 'https://campuccino.org/',
      },
    });
    const fallback = buildCampLinks({
      camp: {
        place: 'Fallback Camping, Riga, Letonya',
        link: 'https://fallback-camping.test/',
      },
    });

    expect(new URL(exact.directionsURL).searchParams.get('destination')).toBe('45.2410861,20.0255373');
    expect(new URL(fallback.directionsURL).searchParams.get('destination')).toBe('Fallback Camping, Riga, Letonya');
  });

  test.each([
    'https://www.google.com/maps/search/?api=1&query=camp',
    'https://maps.google.com/?q=camp',
    'https://maps.app.goo.gl/AbCdEf',
    'https://goo.gl/maps/AbCdEf',
  ])('suppresses Google map links from the camp website action: %s', (link) => {
    expect(buildCampLinks({ camp: { place: 'Camp', link } }).websiteURL).toBeNull();
  });

  test('retains legitimate camp sites and prefers an arrival-target website', () => {
    expect(buildCampLinks({
      camp: { place: 'Camp', link: 'https://camp.example/reserve' },
    }).websiteURL).toBe('https://camp.example/reserve');
    expect(buildCampLinks({
      arrivalTarget: { latitude: 1, longitude: 2, websiteURL: 'https://official.example/' },
      camp: { place: 'Camp', link: 'https://alternate.example/' },
    }).websiteURL).toBe('https://official.example/');
  });
});

test('route status announces only route-start or target changes', () => {
  const announcements: string[] = [];
  const update = createRouteStatusController((message) => announcements.push(message));

  update({ routeStarted: false, target: null });
  update({ routeStarted: false, target: null });
  update({ routeStarted: false, target: null });
  update({ routeStarted: true, target: 'Sofya' });
  update({ routeStarted: true, target: 'Sofya' });
  update({ routeStarted: true, target: 'Sofya' });
  update({ routeStarted: true, target: 'Novi Sad' });
  update({ routeStarted: false, target: null });

  expect(announcements).toEqual([
    'Rota başlamadı.',
    'Sofya yönünde rota aktif.',
    'Novi Sad yönünde rota aktif.',
    'Rota başlamadı.',
  ]);
});

test('journey hero receives one live update after bfcache restore and detaches on final teardown', () => {
  const window = new HappyDOMWindow({ url: 'https://kuzey.test/' });
  window.document.body.innerHTML = `
    <section data-journey-hero data-stops="[]">
      <strong id="live-city">Konum güncelleniyor</strong>
      <b id="hero-live-text">Kalkış hazırlığı</b>
      <small id="hero-current-place">Şu an</small>
      <small id="hero-next-place">Sofya</small>
      <p id="hero-route-status">Rota başlamadı.</p>
    </section>
  `;
  const root = window.document.querySelector('[data-journey-hero]') as unknown as HTMLElement;
  const liveCity = root.querySelector<HTMLElement>('#live-city')!;
  let liveCityText = liveCity.textContent ?? '';
  let liveCityWrites = 0;
  Object.defineProperty(liveCity, 'textContent', {
    configurable: true,
    get: () => liveCityText,
    set: (value: string | null) => {
      liveCityWrites += 1;
      liveCityText = value ?? '';
    },
  });

  const dispatchTransition = (type: 'pagehide' | 'pageshow', persisted: boolean) => {
    const event = new window.Event(type);
    Object.defineProperty(event, 'persisted', { value: persisted });
    window.dispatchEvent(event);
  };
  const dispatchLive = (city: string) => {
    window.dispatchEvent(
      new window.CustomEvent('kuzey:live-location', {
        detail: {
          lat: 41.67,
          lng: 26.56,
          city,
          routeStarted: true,
          activeRouteStop: 'Sofya',
          nextStop: 'Sofya',
        },
      }),
    );
  };

  const cleanup = initJourneyHero(root, window as unknown as globalThis.Window);
  try {
    dispatchTransition('pagehide', true);
    dispatchTransition('pageshow', true);
    dispatchLive('Edirne');
    expect(liveCity.textContent).toBe('Edirne');
    expect(liveCityWrites).toBe(1);

    dispatchTransition('pageshow', true);
    dispatchTransition('pageshow', true);
    dispatchLive('Plovdiv');
    expect(liveCity.textContent).toBe('Plovdiv');
    expect(liveCityWrites).toBe(2);

    dispatchTransition('pagehide', false);
    dispatchLive('Sofya');
    expect(liveCity.textContent).toBe('Plovdiv');
    expect(liveCityWrites).toBe(2);
  } finally {
    cleanup();
    window.close();
  }
});
