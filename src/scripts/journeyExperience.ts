import { heroLiveLabels, subscribeLiveLocation, type FriendlyLocationRecord, type PlannedStop } from './liveSync.ts';

export interface CampLinkInput {
  arrivalTarget?: {
    latitude: number;
    longitude: number;
    websiteURL?: string | null;
  };
  camp: {
    place: string;
    link: string;
  };
}

export interface CampLinks {
  directionsURL: string;
  websiteURL: string | null;
}

export interface RouteStatusState {
  routeStarted: boolean;
  target?: string | null;
}

export function isGoogleMapsURL(value: string): boolean {
  try {
    const url = new URL(value);
    const hostname = url.hostname.toLowerCase().replace(/^www\./, '');
    const pathname = url.pathname.toLowerCase();

    if (hostname === 'maps.app.goo.gl') return true;
    if (hostname === 'goo.gl') return pathname === '/maps' || pathname.startsWith('/maps/');
    if (hostname.startsWith('maps.google.')) return true;
    return /(?:^|\.)google\.[a-z.]+$/.test(hostname)
      && (pathname === '/maps' || pathname.startsWith('/maps/'));
  } catch {
    return false;
  }
}

export function buildCampLinks({ arrivalTarget, camp }: CampLinkInput): CampLinks {
  const destination = arrivalTarget
    ? `${arrivalTarget.latitude},${arrivalTarget.longitude}`
    : camp.place;
  const directions = new URL('https://www.google.com/maps/dir/');
  directions.searchParams.set('api', '1');
  directions.searchParams.set('destination', destination);
  directions.searchParams.set('travelmode', 'driving');

  return {
    directionsURL: directions.toString(),
    websiteURL: arrivalTarget?.websiteURL?.trim()
      || (isGoogleMapsURL(camp.link) ? null : camp.link),
  };
}

export function createRouteStatusController(write: (message: string) => void) {
  let priorState: string | null = null;

  return ({ routeStarted, target }: RouteStatusState): boolean => {
    const normalizedTarget = target?.trim() || 'Yolda';
    const state = routeStarted ? `active:${normalizedTarget}` : 'waiting';
    if (state === priorState) return false;

    priorState = state;
    write(routeStarted ? `${normalizedTarget} yönünde rota aktif.` : 'Rota başlamadı.');
    return true;
  };
}

type LiveWindow = Window & { __kuzeyLiveState?: FriendlyLocationRecord };

export function initJourneyHero(
  root: HTMLElement,
  view: Window = root.ownerDocument.defaultView ?? window,
): () => void {
  const stops = (() => {
    try {
      return JSON.parse(root.dataset.stops || '[]') as PlannedStop[];
    } catch {
      return [];
    }
  })();

  const setText = (id: string, value: string) => {
    const element = root.querySelector<HTMLElement>(`#${id}`);
    if (element) element.textContent = value;
  };
  const updateRouteStatus = createRouteStatusController((message) => {
    setText('hero-route-status', message);
  });

  const apply = (record: FriendlyLocationRecord | undefined) => {
    if (!record) return;
    const labels = heroLiveLabels(record, stops);
    setText('live-city', labels.place);
    setText('hero-live-text', labels.state);
    setText('hero-current-place', labels.current);
    setText('hero-next-place', labels.next);
    updateRouteStatus({
      routeStarted: record.routeStarted,
      target: record.activeRouteStop || record.nextStop,
    });
  };

  const cleanup = subscribeLiveLocation((event) => {
    apply((event as CustomEvent<FriendlyLocationRecord>).detail);
  }, view);
  apply((view as LiveWindow).__kuzeyLiveState);
  return cleanup;
}
