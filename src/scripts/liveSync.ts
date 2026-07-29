export type AltitudeKind = 'absolute' | 'relative';

export type RawLiveRecord = Record<string, unknown>;

export interface NormalizedLiveRecord {
  lat: number;
  lng: number;
  position: { lat: number; lng: number };
  speedKmh: number | null;
  city: string | null;
  routeStarted: boolean;
  journeyStarted: boolean;
  activeRouteStop: string | null;
  activeRouteCode: string | null;
  activeRouteStartedAt: string | null;
  nextStop: string | null;
  nextFlag: string | null;
  remainingKm: number | null;
  remainingToFinalKm: number | null;
  remainingMin: number | null;
  traveledKm: number | null;
  legProgress: number | null;
  altitudeMeters: number | null;
  altitudeKind: AltitudeKind | null;
  altitudeSource: string | null;
  pressureHpa: number | null;
  altitudeAvailable: boolean;
  ts: string | null;
  receivedAt: string | null;
}

export interface LiveMapEventDetail {
  position: { lat: number; lng: number };
  lat: number;
  lng: number;
  routeStarted: boolean;
  activeRouteStop: string | null;
  activeRouteCode: string | null;
  activeRouteStartedAt: string | null;
  nextStop: string | null;
  nextFlag: string | null;
  remainingKm: number | null;
  remainingToFinalKm: number | null;
  remainingMin: number | null;
  traveledKm: number | null;
  legProgress: number | null;
  speedKmh: number | null;
  city: string | null;
  ts: string | null;
}

export interface AltitudeDisplay {
  label: string;
  text: string;
  note: string;
}

export interface PlannedStop {
  name: string;
  lat: number;
  lng: number;
}

export type FriendlyLocationRecord = Pick<
  NormalizedLiveRecord,
  'lat' | 'lng' | 'city' | 'routeStarted' | 'activeRouteStop' | 'nextStop'
>;

export interface HeroLiveLabels {
  place: string;
  state: string;
  current: string;
  next: string;
}

const asNumber = (value: unknown): number | null => {
  if (typeof value !== 'number' || !Number.isFinite(value)) return null;
  return value;
};

const asString = (value: unknown): string | null => {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed.length ? trimmed : null;
};

const clamp = (value: number, min: number, max: number): number => Math.max(min, Math.min(max, value));

const radians = (value: number): number => (value * Math.PI) / 180;

const distanceKm = (from: { lat: number; lng: number }, to: { lat: number; lng: number }): number => {
  const latitudeDelta = radians(to.lat - from.lat);
  const longitudeDelta = radians(to.lng - from.lng);
  const a = Math.sin(latitudeDelta / 2) ** 2
    + Math.cos(radians(from.lat)) * Math.cos(radians(to.lat)) * Math.sin(longitudeDelta / 2) ** 2;
  return 6_371.0088 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
};

const samePlace = (left: string, right: string): boolean =>
  left.localeCompare(right, 'tr', { sensitivity: 'base' }) === 0;

export function formatFriendlyLocation(record: FriendlyLocationRecord, stops: PlannedStop[]): string {
  const city = record.city?.trim() || null;
  const nearest = stops
    .filter((stop) => Number.isFinite(stop.lat) && Number.isFinite(stop.lng) && stop.name.trim().length > 0)
    .map((stop) => ({ ...stop, distanceKm: distanceKm(record, stop) }))
    .sort((left, right) => left.distanceKm - right.distanceKm)[0] ?? null;

  if (city) {
    if (nearest && nearest.distanceKm <= 120 && !samePlace(city, nearest.name)) {
      return `${city}, ${nearest.name}`;
    }
    return city;
  }

  const target = record.activeRouteStop?.trim() || record.nextStop?.trim() || null;
  if (record.routeStarted && target) return `${target} yönünde`;
  if (nearest && nearest.distanceKm <= 120) return `${nearest.name} çevresi`;

  return 'Konum güncelleniyor';
}

export function heroLiveLabels(record: FriendlyLocationRecord, stops: PlannedStop[]): HeroLiveLabels {
  const place = formatFriendlyLocation(record, stops);
  const next = record.activeRouteStop?.trim() || record.nextStop?.trim() || 'Sıradaki';
  const current = record.city?.trim()
    || (place.endsWith(' çevresi') ? place.replace(/ çevresi$/, '') : null)
    || (record.routeStarted ? 'Yolda' : 'Şu an');
  const state = record.routeStarted
    ? next === 'Sıradaki' ? 'Rota aktif' : `${next} yönü`
    : 'Kalkış hazırlığı';

  return { place, state, current, next };
}

export function normalizeLiveRecord(raw: RawLiveRecord): NormalizedLiveRecord | null {
  const lat = asNumber(raw.lat);
  const lng = asNumber(raw.lng);
  if (lat == null || lng == null || Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;

  const altitudeKind = raw.altitudeKind === 'absolute' || raw.altitudeKind === 'relative'
    ? raw.altitudeKind
    : null;
  const legProgress = asNumber(raw.legProgress);
  const journeyStarted = raw.journeyStarted === true;

  return {
    lat,
    lng,
    position: { lat, lng },
    speedKmh: asNumber(raw.speedKmh),
    city: asString(raw.city),
    routeStarted: journeyStarted,
    journeyStarted,
    activeRouteStop: journeyStarted ? asString(raw.activeRouteStop) : null,
    activeRouteCode: journeyStarted ? asString(raw.activeRouteCode) : null,
    activeRouteStartedAt: journeyStarted ? asString(raw.activeRouteStartedAt) : null,
    nextStop: asString(raw.nextStop),
    nextFlag: asString(raw.nextFlag),
    remainingKm: asNumber(raw.remainingKm),
    remainingToFinalKm: asNumber(raw.remainingToFinalKm),
    remainingMin: asNumber(raw.remainingMin),
    traveledKm: journeyStarted ? asNumber(raw.traveledKm) : 0,
    legProgress: journeyStarted ? (legProgress == null ? null : clamp(legProgress, 0, 100)) : 0,
    altitudeMeters: asNumber(raw.altitudeMeters),
    altitudeKind,
    altitudeSource: asString(raw.altitudeSource),
    pressureHpa: asNumber(raw.pressureHpa),
    altitudeAvailable: raw.altitudeAvailable === true,
    ts: asString(raw.ts),
    receivedAt: asString(raw.receivedAt),
  };
}

export function formatMinutes(minutes: number): string {
  const rounded = Math.max(0, Math.round(minutes));
  if (rounded >= 60) return `${Math.floor(rounded / 60)} sa ${rounded % 60} dk`;
  return `${rounded} dk`;
}

export function formatAltitude(record: NormalizedLiveRecord): AltitudeDisplay {
  if (record.altitudeMeters == null) {
    return {
      label: 'Yükseklik',
      text: '—',
      note: record.altitudeAvailable ? 'Ölçüm bekleniyor' : 'Cihazdan yükseklik bekleniyor',
    };
  }

  const rounded = Math.round(record.altitudeMeters);
  if (record.altitudeKind === 'relative') {
    return {
      label: 'Rakım değişimi',
      text: `${rounded > 0 ? '+' : ''}${rounded} m`,
      note: 'Barometre göreli ölçüm',
    };
  }

  return {
    label: 'Rakım',
    text: `${rounded.toLocaleString('tr-TR')} m`,
    note: record.altitudeSource === 'gps' ? 'GPS rakımı' : 'Mutlak rakım',
  };
}

export function mapLiveEventDetail(record: NormalizedLiveRecord): LiveMapEventDetail {
  return {
    position: record.position,
    lat: record.lat,
    lng: record.lng,
    routeStarted: record.routeStarted,
    activeRouteStop: record.activeRouteStop,
    activeRouteCode: record.activeRouteCode,
    activeRouteStartedAt: record.activeRouteStartedAt,
    nextStop: record.nextStop,
    nextFlag: record.nextFlag,
    remainingKm: record.remainingKm,
    remainingToFinalKm: record.remainingToFinalKm,
    remainingMin: record.remainingMin,
    traveledKm: record.traveledKm,
    legProgress: record.legProgress,
    speedKmh: record.speedKmh,
    city: record.city,
    ts: record.ts,
  };
}
