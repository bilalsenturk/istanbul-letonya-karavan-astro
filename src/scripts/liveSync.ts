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
