import { Window } from 'happy-dom';
import { describe, expect, test } from 'vitest';

import { applyPublishedPlan, mountPublishedPlan } from '../src/scripts/publishedPlan';

const fakeClock = () => {
  let nextID = 1;
  const timers = new Map<number, number>();
  let schedules = 0;
  return {
    now: () => 0,
    schedule(_callback: () => void | Promise<void>, delayMs: number) {
      const id = nextID++;
      timers.set(id, delayMs);
      schedules += 1;
      return id;
    },
    cancel(id: unknown) { timers.delete(id as number); },
    pendingDelays: () => [...timers.values()].sort((left, right) => left - right),
    scheduleCount: () => schedules,
  };
};

describe('published plan projection', () => {
  test('updates matching date labels without inventing route geometry', () => {
    const window = new Window({ url: 'https://kuzey.test/day/istanbul-sofya' });
    window.document.body.innerHTML = `
      <main>
        <article data-published-day="istanbul-sofya">
          <time data-published-day-date>3 Ağustos · Pazartesi</time>
          <span data-published-day-origin>İstanbul</span>
          <span data-published-day-destination>Sofya</span>
        </article>
        <a
          data-published-day="istanbul-sofya"
          data-published-directions
          href="https://www.google.com/maps/dir/?api=1&origin=Istanbul&destination=Sofia"
        >Rotayı aç</a>
        <div
          data-published-route-map
          data-published-day="istanbul-sofya"
          data-from="İstanbul"
          data-to="Sofya"
        ></div>
        <p data-published-day="istanbul-sofya" data-published-route-note></p>
        <p data-published-plan-status></p>
      </main>
    `;

    const document = window.document as unknown as Document;
    const departureAt = applyPublishedPlan(document, {
      departureAt: '2026-08-04T02:00:00.000Z',
      days: [{
        slug: 'istanbul-sofya',
        date: '2026-08-04T02:00:00.000Z',
        label: '4 Ağustos · Salı',
        origin: 'Silivri',
        destination: 'Filibe',
      }],
    });

    expect(departureAt).toBe('2026-08-04T02:00:00.000Z');
    expect(window.document.querySelector('[data-published-day-date]')?.textContent).toBe('4 Ağustos · Salı');
    expect(window.document.querySelector('[data-published-day-date]')?.getAttribute('datetime'))
      .toBe('2026-08-04T02:00:00.000Z');
    expect(window.document.querySelector('[data-published-day-origin]')?.textContent).toBe('Silivri');
    expect(window.document.querySelector('[data-published-day-destination]')?.textContent).toBe('Filibe');
    const directionsLink = window.document.querySelector('[data-published-directions]') as unknown as HTMLAnchorElement;
    const directions = new URL(directionsLink.href);
    expect(directions.searchParams.get('origin')).toBe('Silivri');
    expect(directions.searchParams.get('destination')).toBe('Filibe');
    const routeMap = window.document.querySelector('[data-published-route-map]') as unknown as HTMLElement;
    expect(routeMap.dataset.from).toBe('Silivri');
    expect(routeMap.dataset.to).toBe('Filibe');
    expect(window.document.querySelector('[data-published-route-note]')?.textContent)
      .toBe('Güncel etap: Silivri → Filibe. Harita sabit ana rota geometrisini gösterir.');
    expect(window.document.querySelector('[data-published-plan-status]')?.textContent)
      .toBe('Yolculuk planı güncellendi: 4 Ağustos · Salı · Silivri → Filibe.');
    window.close();
  });

  test('ignores malformed plan values instead of corrupting rendered content', () => {
    const window = new Window({ url: 'https://kuzey.test/' });
    window.document.body.innerHTML = '<span data-published-day="day-1"><b data-published-day-date>Eski</b></span>';

    expect(applyPublishedPlan(window.document as unknown as Document, { departureAt: 'not-a-date', days: 'bad' })).toBeNull();
    expect(window.document.querySelector('[data-published-day-date]')?.textContent).toBe('Eski');
    window.close();
  });

  test('restarts polling once after a persisted bfcache restore', () => {
    const window = new Window({ url: 'https://kuzey.test/day/istanbul-sofya' });
    const clock = fakeClock();
    const cleanup = mountPublishedPlan(window.document as unknown as Document, {
      fetch,
      now: clock.now,
      schedule: clock.schedule,
      cancel: clock.cancel,
    });

    try {
      expect(clock.pendingDelays()).toEqual([0]);
      expect(clock.scheduleCount()).toBe(1);
      window.dispatchEvent(new window.Event('pagehide'));
      expect(clock.pendingDelays()).toEqual([]);

      const restored = new window.Event('pageshow');
      Object.defineProperty(restored, 'persisted', { value: true });
      window.dispatchEvent(restored);
      expect(clock.pendingDelays()).toEqual([0]);
      expect(clock.scheduleCount()).toBe(2);

      const duplicateRestore = new window.Event('pageshow');
      Object.defineProperty(duplicateRestore, 'persisted', { value: true });
      window.dispatchEvent(duplicateRestore);
      expect(clock.pendingDelays()).toEqual([0]);
      expect(clock.scheduleCount()).toBe(2);
    } finally {
      cleanup();
      expect(clock.pendingDelays()).toEqual([]);
      window.close();
    }
  });
});
