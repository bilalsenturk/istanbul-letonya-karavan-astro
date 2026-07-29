export type RouteMapMode = 'journey' | 'day';

export type Stop = { name: string; lat: number; lng: number };
export type Leg = { from: string; to: string; distance: number; duration: number; coords: [number, number][] };
export type Geometry = { legs: Leg[]; totalDistanceKm?: number; totalDurationH?: number };

const sameStop = (a: string, b: string): boolean => a.localeCompare(b, 'tr', { sensitivity: 'base' }) === 0;

export function selectRouteStops(stops: Stop[], from: string, to: string, mode: RouteMapMode): Stop[] {
  if (mode === 'journey') return stops;
  return stops.filter((stop) => sameStop(stop.name, from) || sameStop(stop.name, to));
}

export function selectGeometryLegs(geometry: Geometry, from: string, to: string, mode: RouteMapMode): Leg[] {
  if (mode === 'journey') return geometry.legs;
  return geometry.legs.filter((leg) => sameStop(leg.from, from) && sameStop(leg.to, to));
}
