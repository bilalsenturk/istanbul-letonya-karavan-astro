export interface WeatherLocation {
  lat: number;
  lng: number;
}

export interface WeatherSnapshot {
  temperatureC: number | null;
  weatherCode: number | null;
  windKmh: number | null;
  precipitationMm: number | null;
}

export interface WeatherRefreshReference extends WeatherLocation {
  fetchedAt: number;
}

export interface WeatherCacheEntry extends WeatherRefreshReference {
  snapshot: WeatherSnapshot;
}

export type WeatherFetcher = (location: WeatherLocation) => Promise<unknown>;

export interface WeatherRefreshResult {
  status: 'cached' | 'fresh' | 'failed';
  entry: WeatherCacheEntry | null;
  error: unknown | null;
}

const EARTH_RADIUS_KM = 6_371.0088;

const radians = (value: number): number => (value * Math.PI) / 180;

const distanceKm = (from: WeatherLocation, to: WeatherLocation): number => {
  const latitudeDelta = radians(to.lat - from.lat);
  const longitudeDelta = radians(to.lng - from.lng);
  const a =
    Math.sin(latitudeDelta / 2) ** 2 +
    Math.cos(radians(from.lat)) * Math.cos(radians(to.lat)) * Math.sin(longitudeDelta / 2) ** 2;
  return EARTH_RADIUS_KM * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
};

const finiteNumber = (value: unknown): number | null => {
  if (value == null || value === '') return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
};

export function normalizeWeatherSnapshot(raw: unknown): WeatherSnapshot | null {
  if (!raw || typeof raw !== 'object') return null;
  const current = (raw as { current?: unknown }).current;
  if (!current || typeof current !== 'object') return null;
  const values = current as Record<string, unknown>;
  const snapshot: WeatherSnapshot = {
    temperatureC: finiteNumber(values.temperature_2m),
    weatherCode: finiteNumber(values.weather_code),
    windKmh: finiteNumber(values.wind_speed_10m),
    precipitationMm: finiteNumber(values.precipitation),
  };
  return Object.values(snapshot).some((value) => value != null) ? snapshot : null;
}

export function shouldRefreshWeather(
  entry: WeatherRefreshReference | null,
  location: WeatherLocation,
  now: number,
  ttlMs = 900_000,
  movementKm = 10,
): boolean {
  if (!entry) return true;
  if (now - entry.fetchedAt >= ttlMs) return true;
  return distanceKm(entry, location) >= movementKm;
}

export async function refreshWeatherCache(
  existing: WeatherCacheEntry | null,
  location: WeatherLocation,
  fetcher: WeatherFetcher,
  now: number,
): Promise<WeatherRefreshResult> {
  if (!shouldRefreshWeather(existing, location, now)) {
    return { status: 'cached', entry: existing, error: null };
  }

  try {
    const snapshot = normalizeWeatherSnapshot(await fetcher(location));
    if (!snapshot) throw new Error('Invalid weather response');
    return {
      status: 'fresh',
      entry: { ...location, fetchedAt: now, snapshot },
      error: null,
    };
  } catch (error) {
    return { status: 'failed', entry: existing, error };
  }
}
