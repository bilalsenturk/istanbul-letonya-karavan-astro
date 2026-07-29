import { formatAltitude, mapLiveEventDetail, normalizeLiveRecord, type NormalizedLiveRecord } from './liveSync';
import { createPollingLoop } from './polling';

const PUBLIC_TRIP = '/api/v2/public/trips/kuzey-2026';
const urls = {
  live: `${PUBLIC_TRIP}/live-location`,
  expenses: `${PUBLIC_TRIP}/expense-summary`,
  plan: `${PUBLIC_TRIP}/published-plan`,
  roadfeed: '/api/roadfeed',
};

interface RouteTimelineLeg {
  from?: string;
  to?: string;
  distanceKm?: number;
}

interface DashboardState {
  live: NormalizedLiveRecord | null;
  expenses: Record<string, unknown> | null;
  roadfeed: Record<string, unknown> | null;
  weatherKey: string;
  weatherAbort: AbortController | null;
}

export interface HomeDashboardDependencies {
  fetch?: typeof fetch;
  now?: () => number;
  schedule?: (callback: () => void | Promise<void>, delayMs: number) => unknown;
  cancel?: (timer: unknown) => void;
}

const activeDashboards = new WeakMap<HTMLElement, () => void>();

const parseArray = <T>(value: string | undefined): T[] => {
  try {
    const parsed: unknown = JSON.parse(value || '[]');
    return Array.isArray(parsed) ? (parsed as T[]) : [];
  } catch {
    return [];
  }
};

const isAbortError = (error: unknown): boolean =>
  error instanceof DOMException
    ? error.name === 'AbortError'
    : (error as { name?: unknown } | null)?.name === 'AbortError';

const legacyNumber = (value: unknown): number | null => {
  if (value == null || value === '') return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
};

const legacyText = (value: unknown): string | null => (typeof value === 'string' && value.trim() ? value.trim() : null);

export function normalizeHomeLiveRecord(raw: Record<string, unknown>): NormalizedLiveRecord | null {
  const routeStarted = raw.journeyStarted === true || raw.routeStarted === true;
  const receivedAt = legacyText(raw.receivedAt);
  const altitudeKind = legacyText(raw.altitudeKind);
  const normalized = normalizeLiveRecord({
    ...raw,
    lat: legacyNumber(raw.lat),
    lng: legacyNumber(raw.lng),
    speedKmh: legacyNumber(raw.speedKmh),
    remainingKm: legacyNumber(raw.remainingKm),
    remainingToFinalKm: legacyNumber(raw.remainingToFinalKm),
    remainingMin: legacyNumber(raw.remainingMin),
    traveledKm: legacyNumber(raw.traveledKm),
    legProgress: legacyNumber(raw.legProgress),
    altitudeMeters: legacyNumber(raw.altitudeMeters),
    altitudeKind,
    pressureHpa: legacyNumber(raw.pressureHpa),
    journeyStarted: routeStarted,
    ts: legacyText(raw.ts) ?? receivedAt,
    receivedAt,
  });
  if (!normalized) return null;

  const progress = legacyNumber(raw.legProgress);
  normalized.legProgress =
    routeStarted && progress != null ? clampValue(progress > 1 ? progress / 100 : progress, 0, 1) : 0;
  return normalized;
}

const clampValue = (value: number, min: number, max: number): number => Math.max(min, Math.min(max, value));

export function initHomeDashboard(root?: HTMLElement, dependencies: HomeDashboardDependencies = {}): () => void {
  const dashboard = root ?? document.querySelector<HTMLElement>('[data-home-dashboard]');
  if (!dashboard) return () => undefined;

  activeDashboards.get(dashboard)?.();

  const doc = dashboard.ownerDocument;
  const view = doc.defaultView ?? window;
  const fetchImpl = dependencies.fetch ?? ((input, init) => fetch(input, init));
  const now = dependencies.now ?? Date.now;
  const schedule = dependencies.schedule ?? ((callback, delayMs) => setTimeout(callback, delayMs));
  const cancel = dependencies.cancel ?? ((timer) => clearTimeout(timer as ReturnType<typeof setTimeout>));
  const totalKm = Number(dashboard.dataset.totalKm || '0');
  let departureAt = dashboard.dataset.departureAt || '';
  const routeCodes = parseArray<string>(dashboard.dataset.routeCodes);
  const routeTimeline = parseArray<RouteTimelineLeg>(dashboard.dataset.routeTimeline);
  const routeTimelineTotalKm = routeTimeline.reduce((sum, leg) => sum + Math.max(0, Number(leg.distanceKm) || 0), 0);
  const elements = new Map<string, HTMLElement | null>();
  const state: DashboardState = {
    live: null,
    expenses: null,
    roadfeed: null,
    weatherKey: '',
    weatherAbort: null,
  };

  const byId = (id: string): HTMLElement | null => {
    if (!elements.has(id)) elements.set(id, dashboard.querySelector<HTMLElement>(`#${id}`));
    return elements.get(id) ?? null;
  };
  const setText = (id: string, value: string) => {
    const element = byId(id);
    if (element) element.textContent = value;
  };
  const setProgress = (id: string, value: number) => {
    const element = byId(id);
    const progress = Math.max(0, Math.min(100, value));
    if (element) element.style.width = `${progress}%`;
    element?.closest('[role="progressbar"]')?.setAttribute('aria-valuenow', String(Math.round(progress)));
  };
  const toNum = (value: unknown): number | null => {
    if (value == null || value === '') return null;
    const number = Number(value);
    return Number.isFinite(number) ? number : null;
  };
  const clamp = clampValue;
  const normalizeProgress = (value: unknown): number | null => {
    const number = toNum(value);
    if (number == null) return null;
    return clamp(number > 1 ? number / 100 : number, 0, 1);
  };
  const fmtKm = (value: unknown): string => {
    const number = toNum(value);
    return number == null ? '-' : `${Math.round(number).toLocaleString('tr-TR')} km`;
  };
  const fmtMin = (value: unknown): string | null => {
    const number = toNum(value);
    if (number == null) return null;
    const rounded = Math.max(0, Math.round(number));
    return rounded >= 60 ? `${Math.floor(rounded / 60)} sa ${rounded % 60} dk` : `${rounded} dk`;
  };
  const fmtEur = (value: unknown): string => {
    const number = toNum(value);
    if (number == null) return '-';
    return new Intl.NumberFormat('tr-TR', {
      style: 'currency',
      currency: 'EUR',
      maximumFractionDigits: 0,
    }).format(number);
  };
  const fmtLiters = (value: unknown): string => {
    const number = toNum(value);
    return number == null ? '-' : `${Math.round(number).toLocaleString('tr-TR')} L`;
  };
  const fmtDateTime = (iso: unknown): string => {
    const date = typeof iso === 'string' && iso ? new Date(iso) : null;
    if (!date || Number.isNaN(date.getTime())) return '-';
    return date.toLocaleString('tr-TR', {
      day: '2-digit',
      month: 'short',
      hour: '2-digit',
      minute: '2-digit',
    });
  };
  const ageText = (iso: unknown): string | null => {
    const date = typeof iso === 'string' && iso ? new Date(iso) : null;
    if (!date || Number.isNaN(date.getTime())) return null;
    const minutes = Math.max(0, Math.round((now() - date.getTime()) / 60_000));
    if (minutes < 2) return 'az önce';
    if (minutes < 60) return `${minutes} dk önce`;
    const hours = Math.round(minutes / 60);
    return hours < 24 ? `${hours} sa önce` : fmtDateTime(iso);
  };
  const cleanText = (value: unknown): string | null =>
    typeof value === 'string' && value.trim() ? value.trim() : null;

  const publishMapState = (live: NormalizedLiveRecord) => {
    const detail = mapLiveEventDetail(live);
    (view as Window & { __kuzeyLiveState?: ReturnType<typeof mapLiveEventDetail> }).__kuzeyLiveState = detail;
    view.dispatchEvent(new view.CustomEvent('kuzey:live-location', { detail }));
  };

  const stopKey = (value: unknown): string => cleanText(value)?.toLocaleLowerCase('tr-TR') ?? '';
  const timelineLegs = (): HTMLElement[] => [...dashboard.querySelectorAll<HTMLElement>('[data-leg-index]')];
  const heroRoutePoints = (): HTMLElement[] => [...dashboard.querySelectorAll<HTMLElement>('[data-hero-role]')];
  const routeDetails = dashboard.querySelector<HTMLDetailsElement>('[data-route-details]');
  const routeSummaryQuery = view.matchMedia('(max-width: 760px)');
  const syncRouteDetailsMode = () => {
    if (routeDetails) routeDetails.open = !routeSummaryQuery.matches;
  };
  const cumulativeBefore = (index: number): number =>
    routeTimeline.slice(0, Math.max(0, index)).reduce((sum, leg) => sum + Math.max(0, Number(leg.distanceKm) || 0), 0);
  const activeLegIndex = (live: NormalizedLiveRecord): number => {
    const target = stopKey(live.activeRouteStop || live.nextStop);
    if (!target) return -1;
    return routeTimeline.findIndex((leg) => stopKey(leg.to) === target);
  };
  const deriveRouteProgressKm = (live: NormalizedLiveRecord): number => {
    if (!live.routeStarted) return 0;
    const index = activeLegIndex(live);
    if (index >= 0) {
      const legKm = Math.max(0, Number(routeTimeline[index]?.distanceKm) || 0);
      const before = cumulativeBefore(index);
      const legProgress = normalizeProgress(live.legProgress);
      if (legProgress != null) return before + legKm * legProgress;
      if (live.traveledKm != null) return before + Math.max(0, live.traveledKm);
    }
    if (live.remainingToFinalKm != null && totalKm > 0) return Math.max(0, totalKm - live.remainingToFinalKm);
    return Math.max(0, live.traveledKm ?? 0);
  };

  const updateHeroRoute = (live: NormalizedLiveRecord, progressKm: number) => {
    const routeStarted = live.routeStarted;
    const total = Math.max(totalKm, routeTimelineTotalKm, 1);
    const progress = routeStarted ? clamp((Math.max(0, progressKm) / total) * 100, 0, 100) : 0;

    setProgress('hero-route-fill', progress);
    heroRoutePoints().forEach((point) => {
      const role = point.dataset.heroRole;
      point.classList.toggle('is-passed', role === 'start');
      point.classList.toggle('is-active', role === 'current' && progress < 99.5);
      point.classList.toggle('is-next', role === 'next' && Boolean(live.nextStop || live.activeRouteStop));
      if (role === 'end') point.classList.toggle('is-active', progress >= 99.5);
    });
  };

  const updateTimeline = (live: NormalizedLiveRecord, routeProgressKm: number) => {
    const routeStarted = live.routeStarted;
    const progressKm = routeStarted ? Math.max(0, routeProgressKm) : 0;
    const activeIndex = activeLegIndex(live);
    let activeLabel = 'Rota başlamadı';

    timelineLegs().forEach((element) => {
      const index = Number(element.dataset.legIndex || '0');
      const leg = routeTimeline[index] || {};
      const legKm = Math.max(0, Number(leg.distanceKm) || 0);
      const before = cumulativeBefore(index);
      const rawFill = legKm > 0 ? ((progressKm - before) / legKm) * 100 : progressKm >= before ? 100 : 0;
      const fill = routeStarted ? clamp(rawFill, 0, 100) : 0;
      const done = routeStarted && fill >= 99.5;
      const active = routeStarted && !done && (index === activeIndex || (fill > 0 && fill < 99.5));
      const status = element.querySelector<HTMLElement>('[data-leg-status]');
      const fillElement = element.querySelector<HTMLElement>('[data-leg-fill]');

      if (fillElement) fillElement.style.width = `${fill}%`;
      element.classList.toggle('is-done', done);
      element.classList.toggle('is-active', active);

      if (status) {
        if (done) status.textContent = 'Varıldı';
        else if (active) {
          const driven = Math.max(0, Math.min(legKm, progressKm - before));
          status.textContent = legKm > 0 ? `${Math.round(driven)} / ${Math.round(legKm)} km` : 'Yolda';
        } else if (legKm === 0) status.textContent = routeStarted && progressKm >= before ? 'Dinlenme' : 'Bekliyor';
        else status.textContent = 'Bekliyor';
      }

      if (active) activeLabel = `${leg.from} → ${leg.to}`;
    });

    if (routeStarted && activeLabel === 'Rota başlamadı') {
      activeLabel = progressKm >= routeTimelineTotalKm ? 'Riga' : live.activeRouteStop || live.nextStop || 'Yolda';
    }
    routeDetails?.classList.toggle('is-started', routeStarted);
    setText('route-timeline-summary', activeLabel);
    setText('route-timeline-progress', fmtKm(progressKm));
    updateHeroRoute(live, progressKm);
  };

  const renderCountdown = () => {
    const departure = departureAt ? new Date(departureAt) : null;
    const seconds =
      departure && !Number.isNaN(departure.getTime())
        ? Math.max(0, Math.floor((departure.getTime() - now()) / 1_000))
        : 0;
    const routeStarted = state.live?.routeStarted === true;
    const label = routeStarted ? 'Rota aktif' : seconds > 0 ? 'Kalkışa' : 'Kalkış zamanı';

    setText('hero-countdown-label', label);
    setText('countdown-days', String(Math.floor(seconds / 86_400)));
    setText('countdown-hours', String(Math.floor((seconds % 86_400) / 3_600)).padStart(2, '0'));
    setText('countdown-minutes', String(Math.floor((seconds % 3_600) / 60)).padStart(2, '0'));
    setText('countdown-seconds', String(seconds % 60).padStart(2, '0'));
  };

  let countdownTimer: unknown;
  const stopCountdown = () => {
    if (countdownTimer == null) return;
    cancel(countdownTimer);
    countdownTimer = undefined;
  };
  const scheduleCountdown = () => {
    stopCountdown();
    if (doc.hidden) return;
    renderCountdown();
    const remainder = now() % 1_000;
    countdownTimer = schedule(scheduleCountdown, remainder === 0 ? 1_000 : 1_000 - remainder);
  };

  const updateLiveUi = (live: NormalizedLiveRecord) => {
    state.live = live;
    publishMapState(live);
    renderCountdown();

    const next = live.activeRouteStop || live.nextStop || '-';
    const routeProgressKm = deriveRouteProgressKm(live);
    const remainingFinal = !live.routeStarted
      ? totalKm || null
      : live.remainingToFinalKm != null
        ? Math.max(0, live.remainingToFinalKm)
        : totalKm > 0
          ? Math.max(0, totalKm - routeProgressKm)
          : null;
    const traveled = live.routeStarted ? routeProgressKm : 0;
    const overallProgress = totalKm > 0 ? clamp((traveled / totalKm) * 100, 0, 100) : 0;
    const legProgressValue = normalizeProgress(live.legProgress);
    const legProgress = live.routeStarted && legProgressValue != null ? legProgressValue * 100 : null;
    const last = ageText(live.ts);
    setText('live-updated', last || 'Bekleniyor');
    setText('last-seen', live.ts ? `${fmtDateTime(live.ts)}${last ? ` (${last})` : ''}` : '-');
    setText('live-next', next);
    setText('remaining-distance', fmtKm(remainingFinal));
    setText('remaining-note', live.routeStarted ? "Riga'ya" : 'Planlanan rota');
    setText('live-traveled', fmtKm(traveled));
    setText(
      'journey-progress-note',
      live.routeStarted ? `%${Math.round(overallProgress)} tamamlandı` : 'Rota başlamadı',
    );
    setText(
      'live-leg-remaining',
      live.routeStarted
        ? [
            fmtKm(live.remainingKm),
            fmtMin(live.remainingMin),
            legProgress != null ? `%${Math.round(legProgress)} etap` : null,
          ]
            .filter(Boolean)
            .join(' · ') || '-'
        : 'Rota başlamadı',
    );
    setText('live-speed', live.speedKmh != null ? `${Math.round(live.speedKmh)} km/sa` : '-');
    setProgress('journey-progress', overallProgress);
    updateTimeline(live, routeProgressKm);
    byId('live-dot')?.classList.toggle('is-paused', !live.routeStarted);

    const altitude = formatAltitude(live);
    if (altitude.text === '—') {
      setText('live-altitude', '-');
    } else {
      const kind = live.altitudeKind === 'relative' ? 'göreli' : 'rakım';
      const source =
        live.altitudeSource === 'barometer' ? 'barometre' : live.altitudeSource === 'gps' ? 'GPS' : 'uygulama';
      setText('live-altitude', `${altitude.text.replace(/^\+/, '')} (${kind}, ${source})`);
    }
    setText(
      'live-pressure',
      live.pressureHpa != null ? `${Math.round(live.pressureHpa).toLocaleString('tr-TR')} hPa` : '-',
    );
    updateFuelUi();
    void loadWeather(live);
  };

  const weatherLabel = (code: unknown): string => {
    const numericCode = Number(code);
    if (numericCode === 0) return 'Açık';
    if ([1, 2].includes(numericCode)) return 'Parçalı bulutlu';
    if (numericCode === 3) return 'Bulutlu';
    if ([45, 48].includes(numericCode)) return 'Sis';
    if ([51, 53, 55, 56, 57].includes(numericCode)) return 'Çise';
    if ([61, 63, 65, 66, 67, 80, 81, 82].includes(numericCode)) return 'Yağmur';
    if ([71, 73, 75, 77, 85, 86].includes(numericCode)) return 'Kar';
    if ([95, 96, 99].includes(numericCode)) return 'Fırtına';
    return 'Hava';
  };

  const loadWeather = async (live: NormalizedLiveRecord) => {
    const key = `${live.lat.toFixed(3)},${live.lng.toFixed(3)}`;
    if (state.weatherKey === key) return;
    state.weatherKey = key;
    state.weatherAbort?.abort();
    const weatherController = new AbortController();
    state.weatherAbort = weatherController;

    try {
      const url = new URL('https://api.open-meteo.com/v1/forecast');
      url.searchParams.set('latitude', String(live.lat));
      url.searchParams.set('longitude', String(live.lng));
      url.searchParams.set('current', 'temperature_2m,weather_code,wind_speed_10m,precipitation');
      url.searchParams.set('timezone', 'auto');
      const response = await fetchImpl(url, { signal: weatherController.signal });
      if (!response.ok) throw new Error('weather failed');
      const data = (await response.json()) as { current?: Record<string, unknown> };
      const current = data?.current;
      const temperature = toNum(current?.temperature_2m);
      const wind = toNum(current?.wind_speed_10m);
      const rain = toNum(current?.precipitation);
      const label = weatherLabel(current?.weather_code);

      setText('weather-now', temperature == null ? label : `${Math.round(temperature)}°C`);
      setText('weather-detail', label);
      setText('weather-wind', wind == null ? '-' : `${Math.round(wind)} km/sa`);
      setText('weather-rain', rain == null ? '-' : `${rain.toLocaleString('tr-TR', { maximumFractionDigits: 1 })} mm`);
    } catch (error) {
      if (isAbortError(error)) {
        if (state.weatherAbort === weatherController) state.weatherKey = '';
        return;
      }
      setText('weather-now', '-');
      setText('weather-detail', 'Hava alınamadı');
    }
  };

  const expenseFuelValue = (byCategory: unknown): number | null => {
    if (!byCategory || typeof byCategory !== 'object') return null;
    const categories = byCategory as Record<string, unknown>;
    for (const key of ['yakit', 'yakıt', 'fuel', 'diesel', 'benzin']) {
      const value = toNum(categories[key]);
      if (value != null) return value;
    }
    return null;
  };

  const averageDieselPrice = (): number | null => {
    const fuel = state.roadfeed?.fuel;
    const rows = Array.isArray(fuel) ? (fuel as Record<string, unknown>[]) : [];
    const prices = rows
      .filter((row) => routeCodes.includes(String(row.country)))
      .map((row) => toNum(row.dieselEur))
      .filter((value): value is number => value != null && value > 0);
    if (!prices.length) return null;
    return prices.reduce((sum, value) => sum + value, 0) / prices.length;
  };

  function updateFuelUi() {
    const fuelSpend = expenseFuelValue(state.expenses?.byCategory);
    const averageDiesel = averageDieselPrice();
    const traveled = toNum(state.live?.traveledKm);
    let liters: number | null = null;
    let note = 'Bekleniyor';

    if (fuelSpend != null && averageDiesel != null) {
      liters = fuelSpend / averageDiesel;
      note = `${fmtEur(fuelSpend)} üzerinden`;
    } else if (traveled != null && traveled > 0) {
      liters = (traveled * 13) / 100;
      note = '13 L/100 km';
    }

    setText('fuel-used', fmtLiters(liters));
    setText('fuel-note', note);
    setText('fuel-spend', fuelSpend == null ? '-' : fmtEur(fuelSpend));
    setText(
      'roadfeed-fuel',
      averageDiesel == null
        ? '-'
        : `${averageDiesel.toLocaleString('tr-TR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} €/L`,
    );
  }

  const updateExpensesUi = (data: unknown) => {
    state.expenses = data && typeof data === 'object' ? (data as Record<string, unknown>) : null;
    const total = toNum(state.expenses?.totalEur);
    const count = toNum(state.expenses?.count);
    setText('spend-amount', fmtEur(total));
    setText('spend-total-detail', total == null ? '-' : `${fmtEur(total)}${count != null ? ` · ${count} kayıt` : ''}`);
    const timestamp = state.expenses?.ts;
    setText('spend-note', timestamp ? ageText(timestamp) || fmtDateTime(timestamp) : 'Bekleniyor');
    updateFuelUi();
  };

  const updateRoadfeedUi = (data: unknown) => {
    state.roadfeed = data && typeof data === 'object' ? (data as Record<string, unknown>) : null;
    const borders = state.roadfeed?.borders;
    const border = Array.isArray(borders) ? (borders[0] as Record<string, unknown> | undefined) : undefined;
    setText('border-note', border ? `${String(border.name)}: ${String(border.outbound)}` : '-');
    updateFuelUi();
  };

  const fetchJson = async (path: string, signal: AbortSignal): Promise<unknown> => {
    const response = await fetchImpl(path, { cache: 'no-store', signal });
    if (!response.ok) throw new Error(`${path} ${response.status}`);
    return response.json();
  };

  const refreshLive = async (signal: AbortSignal) => {
    try {
      const data = await fetchJson(urls.live, signal);
      const live = data && typeof data === 'object' ? normalizeHomeLiveRecord(data as Record<string, unknown>) : null;
      if (!live) throw new Error('bad live payload');
      updateLiveUi(live);
    } catch (error) {
      if (!isAbortError(error)) setText('hero-live-text', 'Konum güncelleniyor');
      throw error;
    }
  };

  const refreshExpenses = async (signal: AbortSignal) => {
    try {
      updateExpensesUi(await fetchJson(urls.expenses, signal));
    } catch (error) {
      if (!isAbortError(error)) updateExpensesUi(null);
      throw error;
    }
  };

  const refreshRoadfeed = async (signal: AbortSignal) => {
    try {
      updateRoadfeedUi(await fetchJson(urls.roadfeed, signal));
    } catch (error) {
      if (!isAbortError(error)) updateRoadfeedUi(null);
      throw error;
    }
  };

  const refreshPlan = async (signal: AbortSignal) => {
    try {
      const plan = (await fetchJson(urls.plan, signal)) as Record<string, unknown> | null;
      const publishedDeparture = cleanText(plan?.departureAt);
      if (publishedDeparture && !Number.isNaN(new Date(publishedDeparture).getTime())) departureAt = publishedDeparture;
    } finally {
      renderCountdown();
    }
  };

  const loops = [
    createPollingLoop({
      task: refreshLive,
      intervalMs: 20_000,
      maxBackoffMs: 160_000,
      now,
      schedule,
      cancel,
    }),
    createPollingLoop({
      task: refreshExpenses,
      intervalMs: 60_000,
      maxBackoffMs: 480_000,
      now,
      schedule,
      cancel,
    }),
    createPollingLoop({
      task: refreshPlan,
      intervalMs: 5 * 60_000,
      maxBackoffMs: 40 * 60_000,
      now,
      schedule,
      cancel,
    }),
    createPollingLoop({
      task: refreshRoadfeed,
      intervalMs: 30 * 60_000,
      maxBackoffMs: 4 * 60 * 60_000,
      now,
      schedule,
      cancel,
    }),
  ];

  const galleryCleanups: Array<() => void> = [];
  dashboard.querySelectorAll<HTMLButtonElement>('[data-gallery-scroll]').forEach((button) => {
    const onClick = () => {
      const gallery = button.closest('.follow-gallery');
      const track = gallery?.querySelector<HTMLElement>('[data-gallery-track]');
      const direction = Number(button.dataset.galleryScroll || '1');
      track?.scrollBy({ left: track.clientWidth * 0.82 * direction, behavior: 'smooth' });
    };
    button.addEventListener('click', onClick);
    galleryCleanups.push(() => button.removeEventListener('click', onClick));
  });

  const handleVisibility = () => {
    if (doc.hidden) {
      loops.forEach((loop) => loop.pause());
      stopCountdown();
      state.weatherAbort?.abort();
      state.weatherKey = '';
    } else {
      loops.forEach((loop) => loop.resume());
      scheduleCountdown();
    }
  };
  let cleanedUp = false;
  const cleanup = () => {
    if (cleanedUp) return;
    cleanedUp = true;
    loops.forEach((loop) => loop.stop());
    stopCountdown();
    state.weatherAbort?.abort();
    routeSummaryQuery.removeEventListener?.('change', syncRouteDetailsMode);
    doc.removeEventListener('visibilitychange', handleVisibility);
    view.removeEventListener('pagehide', cleanup);
    galleryCleanups.forEach((removeListener) => removeListener());
    if (activeDashboards.get(dashboard) === cleanup) activeDashboards.delete(dashboard);
  };

  activeDashboards.set(dashboard, cleanup);
  syncRouteDetailsMode();
  routeSummaryQuery.addEventListener?.('change', syncRouteDetailsMode);
  doc.addEventListener('visibilitychange', handleVisibility);
  view.addEventListener('pagehide', cleanup);
  loops.forEach((loop) => loop.start());
  scheduleCountdown();
  if (doc.hidden) handleVisibility();

  return cleanup;
}

export function mountHomeDashboard(root?: HTMLElement, dependencies: HomeDashboardDependencies = {}): () => void {
  const dashboard = root ?? document.querySelector<HTMLElement>('[data-home-dashboard]');
  if (!dashboard) return () => undefined;

  const view = dashboard.ownerDocument.defaultView ?? window;
  let cleanupDashboard = initHomeDashboard(dashboard, dependencies);
  let disposed = false;

  const handlePageShow = (event: PageTransitionEvent) => {
    if (disposed || !event.persisted || activeDashboards.has(dashboard)) return;
    cleanupDashboard = initHomeDashboard(dashboard, dependencies);
  };
  const cleanup = () => {
    if (disposed) return;
    disposed = true;
    cleanupDashboard();
    view.removeEventListener('pageshow', handlePageShow);
  };

  view.addEventListener('pageshow', handlePageShow);
  return cleanup;
}
