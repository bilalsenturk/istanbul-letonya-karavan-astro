import { Window } from 'happy-dom';
import { describe, expect, test } from 'vitest';

import * as homeDashboard from '../src/scripts/homeDashboard';

function createFakeClock(startAt: number) {
  let currentTime = startAt;
  let nextTimerId = 1;
  const timers = new Map<number, { callback: () => void | Promise<void>; dueAt: number }>();
  const scheduledDelays: number[] = [];

  const runDue = async () => {
    while (true) {
      const next = [...timers.entries()]
        .filter(([, timer]) => timer.dueAt <= currentTime)
        .sort((left, right) => left[1].dueAt - right[1].dueAt || left[0] - right[0])[0];
      if (!next) return;
      const [id, timer] = next;
      timers.delete(id);
      await timer.callback();
      await Promise.resolve();
    }
  };

  return {
    now: () => currentTime,
    schedule(callback: () => void | Promise<void>, delayMs: number) {
      const id = nextTimerId++;
      scheduledDelays.push(delayMs);
      timers.set(id, { callback, dueAt: currentTime + delayMs });
      return id;
    },
    cancel(id: unknown) {
      timers.delete(id as number);
    },
    elapse(delayMs: number) {
      currentTime += delayMs;
    },
    async runCurrent() {
      await runDue();
    },
    pendingDelays() {
      return [...timers.values()].map((timer) => timer.dueAt - currentTime).sort((left, right) => left - right);
    },
    scheduleCount() {
      return scheduledDelays.length;
    },
  };
}

function createDashboardFixture() {
  const window = new Window({ url: 'https://kuzey.test/' });
  window.document.body.innerHTML = `
    <main data-home-dashboard>
      <span id="hero-live-text"></span>
      <span id="hero-countdown-label"></span>
      <span id="countdown-days"></span>
      <span id="countdown-hours"></span>
      <span id="countdown-minutes"></span>
      <span id="countdown-seconds"></span>
      <span id="live-updated"></span>
      <span id="last-seen"></span>
      <span id="live-next"></span>
      <span id="remaining-distance"></span>
      <span id="remaining-note"></span>
      <span id="live-traveled"></span>
      <span id="journey-progress-note"></span>
      <span id="live-leg-remaining"></span>
      <span id="live-speed"></span>
      <span id="live-dot"></span>
      <span id="live-altitude"></span>
      <span id="live-pressure"></span>
      <span id="weather-now"></span>
      <span id="weather-detail"></span>
      <span id="weather-wind"></span>
      <span id="weather-rain"></span>
      <span id="fuel-used"></span>
      <span id="fuel-note"></span>
      <span id="fuel-spend"></span>
      <span id="roadfeed-fuel"></span>
      <span id="spend-amount"></span>
      <span id="spend-total-detail"></span>
      <span id="spend-note"></span>
      <span id="border-note"></span>
      <div role="progressbar" aria-valuenow="0"><span id="journey-progress"></span></div>
      <span id="hero-route-fill"></span>
      <i data-hero-role="start"></i>
      <i data-hero-role="current"></i>
      <i data-hero-role="next"></i>
      <i data-hero-role="end"></i>
      <details data-route-details open>
        <span id="route-timeline-summary"></span>
        <span id="route-timeline-progress"></span>
        <article data-leg-index="0">
          <span data-leg-status></span>
          <span data-leg-fill></span>
        </article>
      </details>
      <section class="follow-gallery">
        <button type="button" data-gallery-scroll="1">Next</button>
        <div data-gallery-track></div>
      </section>
    </main>
  `;
  Object.defineProperty(window.document, 'hidden', { configurable: true, writable: true, value: false });
  const root = window.document.querySelector('[data-home-dashboard]') as unknown as HTMLElement;
  root.dataset.totalKm = '1000';
  root.dataset.departureAt = '2026-08-05T00:00:00Z';
  root.dataset.routeCodes = JSON.stringify(['TR', 'BG']);
  root.dataset.routeTimeline = JSON.stringify([{ from: 'İstanbul', to: 'Sofya', distanceKm: 500 }]);
  const track = root.querySelector<HTMLElement>('[data-gallery-track]')!;
  Object.defineProperty(track, 'clientWidth', { configurable: true, value: 1000 });
  Object.defineProperty(track, 'scrollBy', {
    configurable: true,
    value: (optionsOrX: ScrollToOptions | number = 0) => {
      track.scrollLeft += typeof optionsOrX === 'number' ? optionsOrX : (optionsOrX.left ?? 0);
    },
  });

  return { window, root, track };
}

describe('home live compatibility', () => {
  test('preserves every value accepted by the former homepage parser', () => {
    expect(typeof homeDashboard.normalizeHomeLiveRecord).toBe('function');
    const normalize = homeDashboard.normalizeHomeLiveRecord as (
      raw: Record<string, unknown>,
    ) => Record<string, unknown> | null;

    expect(
      normalize({
        lat: '41.6764',
        lng: '26.5581',
        speedKmh: '82.3',
        city: ' Edirne ',
        routeStarted: true,
        activeRouteStop: ' Sofya ',
        activeRouteCode: ' BG ',
        activeRouteStartedAt: ' 2026-07-22T08:00:00Z ',
        nextStop: ' Sofya ',
        nextFlag: ' 🇧🇬 ',
        remainingKm: '321.4',
        remainingToFinalKm: '2980.7',
        remainingMin: '245',
        traveledKm: '194.2',
        legProgress: '64.5',
        altitudeMeters: '126.2',
        altitudeKind: ' relative ',
        altitudeSource: ' barometer ',
        pressureHpa: '1009.6',
        altitudeAvailable: true,
        ts: ' ',
        receivedAt: ' 2026-07-22T08:12:00Z ',
      }),
    ).toMatchObject({
      lat: 41.6764,
      lng: 26.5581,
      position: { lat: 41.6764, lng: 26.5581 },
      speedKmh: 82.3,
      city: 'Edirne',
      routeStarted: true,
      journeyStarted: true,
      activeRouteStop: 'Sofya',
      activeRouteCode: 'BG',
      activeRouteStartedAt: '2026-07-22T08:00:00Z',
      nextStop: 'Sofya',
      nextFlag: '🇧🇬',
      remainingKm: 321.4,
      remainingToFinalKm: 2980.7,
      remainingMin: 245,
      traveledKm: 194.2,
      legProgress: 0.645,
      altitudeMeters: 126.2,
      altitudeKind: 'relative',
      altitudeSource: 'barometer',
      pressureHpa: 1009.6,
      altitudeAvailable: true,
      ts: '2026-07-22T08:12:00Z',
      receivedAt: '2026-07-22T08:12:00Z',
    });
  });

  test('still rejects coerced coordinates outside the valid geographic range', () => {
    expect(typeof homeDashboard.normalizeHomeLiveRecord).toBe('function');
    const normalize = homeDashboard.normalizeHomeLiveRecord as (
      raw: Record<string, unknown>,
    ) => Record<string, unknown> | null;

    expect(normalize({ lat: '91', lng: '29' })).toBeNull();
  });
});

test('runs the real dashboard against controlled DOM, fetch, and clock boundaries', async () => {
  const startAt = Date.parse('2026-08-03T00:00:00.250Z');
  const clock = createFakeClock(startAt);
  const { window, root, track } = createDashboardFixture();
  const fetchCalls: string[] = [];
  const payloads: Record<string, unknown> = {
    '/api/v2/public/trips/kuzey-2026/live-location': {
      lat: '41.5',
      lng: '29',
      speedKmh: '82',
      city: 'Edirne',
      routeStarted: true,
      activeRouteStop: 'Sofya',
      nextStop: 'Sofya',
      remainingKm: '100',
      remainingToFinalKm: '700',
      remainingMin: '90',
      traveledKm: '250',
      legProgress: '50',
      altitudeMeters: '126',
      altitudeKind: 'absolute',
      altitudeSource: 'gps',
      pressureHpa: '1009',
      altitudeAvailable: true,
      receivedAt: '2026-08-02T23:59:00Z',
    },
    '/api/v2/public/trips/kuzey-2026/expense-summary': {
      totalEur: 100,
      count: 2,
      byCategory: { fuel: 50 },
      ts: '2026-08-02T23:59:00Z',
    },
    '/api/v2/public/trips/kuzey-2026/published-plan': {
      departureAt: '2026-08-04T00:00:10Z',
    },
    '/api/roadfeed': {
      fuel: [{ country: 'TR', dieselEur: 2 }],
      borders: [{ name: 'Kapıkule', outbound: '1 saat' }],
    },
  };
  const fetchImpl = async (input: RequestInfo | URL): Promise<Response> => {
    const url = String(input);
    fetchCalls.push(url);
    if (url.startsWith('https://api.open-meteo.com/')) {
      return Response.json({
        current: { temperature_2m: 24, weather_code: 0, wind_speed_10m: 12, precipitation: 0 },
      });
    }
    return Response.json(payloads[url]);
  };
  const init = homeDashboard.initHomeDashboard as (
    root: HTMLElement,
    dependencies: {
      fetch: typeof fetchImpl;
      now: () => number;
      schedule: typeof clock.schedule;
      cancel: typeof clock.cancel;
    },
  ) => () => void;

  const firstCleanup = init(root, {
    fetch: fetchImpl,
    now: clock.now,
    schedule: clock.schedule,
    cancel: clock.cancel,
  });
  let cleanup = () => firstCleanup();
  try {
    const secondCleanup = init(root, {
      fetch: fetchImpl,
      now: clock.now,
      schedule: clock.schedule,
      cancel: clock.cancel,
    });
    cleanup = secondCleanup;
    expect(clock.pendingDelays()).toEqual([0, 0, 0, 0, 750]);

    await clock.runCurrent();
    await Promise.resolve();
    expect(fetchCalls.filter((url) => url.startsWith('/api/'))).toEqual([
      '/api/v2/public/trips/kuzey-2026/live-location',
      '/api/v2/public/trips/kuzey-2026/expense-summary',
      '/api/v2/public/trips/kuzey-2026/published-plan',
      '/api/roadfeed',
    ]);
    expect(clock.pendingDelays()).toEqual([750, 20_000, 60_000, 300_000, 1_800_000]);
    expect(root.querySelector('#live-next')?.textContent).toBe('Sofya');
    expect(root.querySelector('#live-speed')?.textContent).toBe('82 km/sa');
    expect(root.querySelector('#fuel-used')?.textContent).toBe('25 L');
    expect(root.querySelector('#spend-total-detail')?.textContent).toContain('100');
    expect(root.querySelector('#spend-total-detail')?.textContent).toContain('2 kayıt');
    expect(root.querySelector('#roadfeed-fuel')?.textContent).toBe('2,00 €/L');
    expect(root.querySelector('#border-note')?.textContent).toBe('Kapıkule: 1 saat');
    expect(root.querySelector('#route-timeline-summary')?.textContent).toBe('İstanbul → Sofya');
    expect(root.querySelector('[data-leg-index]')?.classList.contains('is-active')).toBe(true);
    expect(root.querySelector('#hero-countdown-label')?.textContent).toBe('Rota aktif');
    expect(root.querySelector('#countdown-days')?.textContent).toBe('1');
    expect(root.querySelector('#countdown-seconds')?.textContent).toBe('09');

    root.querySelector<HTMLButtonElement>('[data-gallery-scroll]')!.click();
    expect(track.scrollLeft).toBe(820);

    (window.document as unknown as { hidden: boolean }).hidden = true;
    window.document.dispatchEvent(new window.Event('visibilitychange'));
    expect(clock.pendingDelays()).toEqual([]);
    clock.elapse(10_000);
    (window.document as unknown as { hidden: boolean }).hidden = false;
    window.document.dispatchEvent(new window.Event('visibilitychange'));
    expect(clock.pendingDelays()).toEqual([750, 10_000, 50_000, 290_000, 1_790_000]);
    window.dispatchEvent(new window.Event('pagehide'));
    expect(clock.pendingDelays()).toEqual([]);
  } finally {
    cleanup();
    expect(clock.pendingDelays()).toEqual([]);
    window.close();
  }
});

test('recreates one dashboard after a persisted bfcache restore', () => {
  expect(typeof homeDashboard.mountHomeDashboard).toBe('function');
  const startAt = Date.parse('2026-08-03T00:00:00.250Z');
  const clock = createFakeClock(startAt);
  const { window, root } = createDashboardFixture();
  const mount = homeDashboard.mountHomeDashboard as (
    root: HTMLElement,
    dependencies: {
      fetch: typeof fetch;
      now: () => number;
      schedule: typeof clock.schedule;
      cancel: typeof clock.cancel;
    },
  ) => () => void;
  const cleanup = mount(root, {
    fetch,
    now: clock.now,
    schedule: clock.schedule,
    cancel: clock.cancel,
  });

  try {
    expect(clock.pendingDelays()).toEqual([0, 0, 0, 0, 750]);
    expect(clock.scheduleCount()).toBe(5);
    window.dispatchEvent(new window.Event('pagehide'));
    expect(clock.pendingDelays()).toEqual([]);

    const restored = new window.Event('pageshow');
    Object.defineProperty(restored, 'persisted', { value: true });
    window.dispatchEvent(restored);
    expect(clock.pendingDelays()).toEqual([0, 0, 0, 0, 750]);
    expect(clock.scheduleCount()).toBe(10);

    const duplicateRestore = new window.Event('pageshow');
    Object.defineProperty(duplicateRestore, 'persisted', { value: true });
    window.dispatchEvent(duplicateRestore);
    expect(clock.pendingDelays()).toEqual([0, 0, 0, 0, 750]);
    expect(clock.scheduleCount()).toBe(10);
  } finally {
    cleanup();
    expect(clock.pendingDelays()).toEqual([]);
    window.close();
  }
});
