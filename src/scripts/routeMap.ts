import L from 'leaflet';
import 'leaflet/dist/leaflet.css';

export function initRouteMap(containerId: string): void {
  const container = document.getElementById(containerId);
  if (!container) return;

  const wrapper = container.closest('.route-map-container');
  if (!wrapper) return;

  const points = (() => {
    try {
      return JSON.parse(container.dataset.stops || '[]') as Array<{ name: string; lat: number; lng: number }>;
    } catch {
      return [];
    }
  })();

  if (!Array.isArray(points) || points.length === 0) return;

  const bounds: [number, number][] = [];
  const map = L.map(container, { zoomControl: false }).setView([55, 24], 5);

  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    maxZoom: 18,
  }).addTo(map);

  const latlngs = points
    .map((point) => {
      const lat = Number(point.lat);
      const lng = Number(point.lng);
      if (Number.isFinite(lat) && Number.isFinite(lng)) {
        bounds.push([lat, lng]);
        return [lat, lng] as [number, number];
      }
      return null;
    })
    .filter((x): x is [number, number] => x !== null);

  if (latlngs.length === 0) return;

  const from = String(container.dataset.from || '');
  const to = String(container.dataset.to || '');
  const start = points.findIndex((p) => String(p.name).toLowerCase() === from.toLowerCase());
  const end = points.findIndex((p) => String(p.name).toLowerCase() === to.toLowerCase());
  const segmentStart = Math.max(0, start >= 0 ? start : 0);
  const segmentEnd = Math.max(segmentStart, end >= 0 ? end : segmentStart);

  points.forEach((point, index) => {
    if (!point || !Number.isFinite(point.lat) || !Number.isFinite(point.lng)) return;
    const fill = index >= segmentStart && index <= segmentEnd ? '#59e0ff' : '#9bb2ff';
    const radius = index >= segmentStart && index <= segmentEnd ? 7 : 5;
    const marker = L.circleMarker([point.lat, point.lng], {
      radius,
      color: '#0b1a33',
      weight: 2,
      fillColor: fill,
      fillOpacity: 1,
    }).addTo(map);
    marker.bindPopup(`<strong>${point.name}</strong>`);
  });

  L.polyline(latlngs, { color: '#67a6ff', weight: 4, opacity: 0.9 }).addTo(map);
  map.fitBounds(bounds, { padding: [18, 18] });
  wrapper.classList.add('ready');
}
