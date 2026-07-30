import { createPollingLoop } from './polling';

const PUBLIC_PLAN_URL = '/api/v2/public/trips/kuzey-2026/published-plan';
const activePublishedPlans = new WeakMap<object, () => void>();

type PublishedPlanDay = {
  slug: string;
  date: string | null;
  label: string | null;
  origin: string | null;
  destination: string | null;
};

export interface PublishedPlanDependencies {
  fetch?: typeof fetch;
  now?: () => number;
  schedule?: (callback: () => void | Promise<void>, delayMs: number) => unknown;
  cancel?: (timer: unknown) => void;
}

const record = (value: unknown): Record<string, unknown> | null =>
  value !== null && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;

const text = (value: unknown): string | null => {
  if (typeof value !== 'string') return null;
  const normalized = value.trim();
  return normalized || null;
};

const timestamp = (value: unknown): string | null => {
  const normalized = text(value);
  return normalized && Number.isFinite(Date.parse(normalized)) ? normalized : null;
};

const dateLabel = (date: string | null): string | null => {
  if (!date) return null;
  return new Intl.DateTimeFormat('tr-TR', {
    day: 'numeric',
    month: 'long',
    weekday: 'long',
    timeZone: 'Europe/Istanbul',
  }).format(new Date(date));
};

const planDays = (value: unknown): PublishedPlanDay[] => {
  if (!Array.isArray(value)) return [];
  return value.flatMap((entry) => {
    const day = record(entry);
    const slug = text(day?.slug);
    if (!day || !slug) return [];
    const date = timestamp(day.date);
    return [{
      slug,
      date,
      label: text(day.label) ?? dateLabel(date),
      origin: text(day.origin),
      destination: text(day.destination),
    }];
  });
};

const matchingElements = (root: ParentNode, selector: string, slug: string): HTMLElement[] =>
  [...root.querySelectorAll<HTMLElement>(selector)].filter((element) => element.dataset.publishedDay === slug);

const directionsURL = (origin: string, destination: string): string => {
  const url = new URL('https://www.google.com/maps/dir/');
  url.searchParams.set('api', '1');
  url.searchParams.set('origin', origin);
  url.searchParams.set('destination', destination);
  url.searchParams.set('travelmode', 'driving');
  return url.toString();
};

const mergeRouteTimeline = (root: ParentNode, days: PublishedPlanDay[]): void => {
  const element = root as HTMLElement;
  if (!element.dataset?.routeTimeline) return;
  try {
    const timeline = JSON.parse(element.dataset.routeTimeline) as Array<Record<string, unknown>>;
    if (!Array.isArray(timeline)) return;
    const bySlug = new Map(days.map((day) => [day.slug, day]));
    element.dataset.routeTimeline = JSON.stringify(timeline.map((leg) => {
      const day = typeof leg.slug === 'string' ? bySlug.get(leg.slug) : undefined;
      if (!day) return leg;
      return {
        ...leg,
        ...(day.origin ? { from: day.origin } : {}),
        ...(day.destination ? { to: day.destination } : {}),
      };
    }));
  } catch {
    // Static fallback data remains authoritative if its JSON is malformed.
  }
};

const setText = (root: ParentNode, selector: string, value: string | null): boolean => {
  if (!value) return false;
  let changed = false;
  root.querySelectorAll<HTMLElement>(selector).forEach((element) => {
    if (element.textContent === value) return;
    element.textContent = value;
    changed = true;
  });
  return changed;
};

export function applyPublishedPlan(root: ParentNode, input: unknown): string | null {
  const plan = record(input);
  if (!plan) return null;

  const days = planDays(plan.days);
  const changedLabels: string[] = [];
  for (const day of days) {
    let dayChanged = false;
    root.querySelectorAll<HTMLElement>('[data-published-day]').forEach((container) => {
      if (container.dataset.publishedDay !== day.slug) return;
      dayChanged = setText(container, '[data-published-day-date]', day.label) || dayChanged;
      dayChanged = setText(container, '[data-published-day-origin]', day.origin) || dayChanged;
      dayChanged = setText(container, '[data-published-day-destination]', day.destination) || dayChanged;
      if (day.destination && container.dataset.legIndex !== undefined) {
        dayChanged = container.dataset.legTo !== day.destination || dayChanged;
        container.dataset.legTo = day.destination;
      }
      if (day.date) {
        container.querySelectorAll<HTMLElement>('[data-published-day-date]').forEach((element) => {
          element.setAttribute('datetime', day.date!);
        });
      }
      if (day.date) container.dataset.publishedDate = day.date;
    });

    if (day.origin && day.destination) {
      matchingElements(root, '[data-published-directions]', day.slug).forEach((element) => {
        if (element.tagName !== 'A') return;
        const anchor = element as HTMLAnchorElement;
        const href = directionsURL(day.origin!, day.destination!);
        dayChanged = anchor.href !== href || dayChanged;
        anchor.href = href;
      });
      matchingElements(root, '[data-published-route-map]', day.slug).forEach((element) => {
        dayChanged = element.dataset.from !== day.origin || element.dataset.to !== day.destination || dayChanged;
        element.dataset.from = day.origin!;
        element.dataset.to = day.destination!;
      });
      const routeNote = `Güncel etap: ${day.origin} → ${day.destination}. Harita sabit ana rota geometrisini gösterir.`;
      matchingElements(root, '[data-published-route-note]', day.slug).forEach((element) => {
        if (element.textContent !== routeNote) {
          element.textContent = routeNote;
          dayChanged = true;
        }
      });
    }
    if (dayChanged) {
      const summary = [day.label, day.origin && day.destination ? `${day.origin} → ${day.destination}` : null]
        .filter(Boolean)
        .join(' · ');
      if (summary) changedLabels.push(summary);
    }
  }

  mergeRouteTimeline(root, days);
  const firstOrigin = days.find((day) => day.origin)?.origin ?? null;
  const finalDestination = [...days].reverse().find((day) => day.destination)?.destination ?? null;
  setText(root, '[data-published-route-start]', firstOrigin);
  setText(root, '[data-published-route-end]', finalDestination);

  if (changedLabels.length > 0) {
    setText(root, '[data-published-plan-status]', `Yolculuk planı güncellendi: ${changedLabels.join(', ')}.`);
  }

  return timestamp(plan.departureAt);
}

export function initPublishedPlan(
  root: ParentNode = document,
  dependencies: PublishedPlanDependencies = {},
): () => void {
  const activeCleanup = activePublishedPlans.get(root as object);
  if (activeCleanup) activeCleanup();
  const doc = root.nodeType === 9 ? root as Document : (root as Element).ownerDocument;
  const view = doc?.defaultView;
  const fetchImpl = dependencies.fetch ?? fetch;
  const loop = createPollingLoop({
    task: async (signal) => {
      const response = await fetchImpl(PUBLIC_PLAN_URL, {
        signal,
        cache: 'no-store',
        headers: { accept: 'application/json' },
      });
      if (!response.ok) throw new Error(`published_plan_${response.status}`);
      applyPublishedPlan(root, await response.json());
    },
    intervalMs: 60_000,
    maxBackoffMs: 8 * 60_000,
    now: dependencies.now,
    schedule: dependencies.schedule,
    cancel: dependencies.cancel,
  });

  const onVisibilityChange = () => {
    if (doc.hidden) loop.pause();
    else loop.resume();
  };
  let cleanedUp = false;
  const cleanup = () => {
    if (cleanedUp) return;
    cleanedUp = true;
    loop.stop();
    doc.removeEventListener('visibilitychange', onVisibilityChange);
    view?.removeEventListener('pagehide', cleanup);
    if (activePublishedPlans.get(root as object) === cleanup) activePublishedPlans.delete(root as object);
  };

  activePublishedPlans.set(root as object, cleanup);
  doc.addEventListener('visibilitychange', onVisibilityChange);
  view?.addEventListener('pagehide', cleanup);
  loop.start();
  if (doc.hidden) loop.pause();
  return cleanup;
}

export function mountPublishedPlan(
  root: ParentNode = document,
  dependencies: PublishedPlanDependencies = {},
): () => void {
  const doc = root.nodeType === 9 ? root as Document : (root as Element).ownerDocument;
  const view = doc?.defaultView;
  let cleanupPlan = initPublishedPlan(root, dependencies);
  let disposed = false;

  const onPageShow = (event: PageTransitionEvent) => {
    if (disposed || !event.persisted || activePublishedPlans.has(root as object)) return;
    cleanupPlan = initPublishedPlan(root, dependencies);
  };
  const cleanup = () => {
    if (disposed) return;
    disposed = true;
    cleanupPlan();
    view?.removeEventListener('pageshow', onPageShow);
  };

  view?.addEventListener('pageshow', onPageShow);
  return cleanup;
}
