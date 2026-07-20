import L from 'leaflet';
import 'leaflet/dist/leaflet.css';

type Stop = { name: string; lat: number; lng: number };
type Leg = { from: string; to: string; distance: number; duration: number; coords: [number, number][] };
type Geometry = { legs: Leg[]; totalDistanceKm?: number; totalDurationH?: number };

let geometryCache: Promise<Geometry | null> | null = null;

/** Gerçek sürüş rotası (yolları takip eden). Yoksa null → düz çizgiye düşülür. */
function loadGeometry(): Promise<Geometry | null> {
  if (!geometryCache) {
    geometryCache = fetch('/assets/route-geometry.json')
      .then((r) => (r.ok ? r.json() : null))
      .catch(() => null);
  }
  return geometryCache;
}

export function initRouteMap(containerId: string): void {
  const container = document.getElementById(containerId);
  if (!container) return;

  const wrapper = container.closest('.route-map-container');
  if (!wrapper) return;

  const points: Stop[] = (() => {
    try {
      return JSON.parse(container.dataset.stops || '[]');
    } catch {
      return [];
    }
  })();
  if (!Array.isArray(points) || points.length === 0) return;

  const valid = points.filter((p) => Number.isFinite(Number(p.lat)) && Number.isFinite(Number(p.lng)));
  if (valid.length === 0) return;

  const map = L.map(container, { zoomControl: false, scrollWheelZoom: false });

  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    maxZoom: 18,
  }).addTo(map);

  // Bu sayfa/gün hangi etabı vurgulayacak?
  const from = String(container.dataset.from || '');
  const to = String(container.dataset.to || '');
  const startIdx = valid.findIndex((p) => p.name.toLowerCase() === from.toLowerCase());
  const endIdx = valid.findIndex((p) => p.name.toLowerCase() === to.toLowerCase());
  const segStart = startIdx >= 0 ? startIdx : 0;
  const segEnd = endIdx >= 0 ? Math.max(segStart, endIdx) : segStart;
  const highlighting = startIdx >= 0 && endIdx >= 0;

  // Duraklar
  valid.forEach((point, index) => {
    const inSegment = index >= segStart && index <= segEnd;
    const active = !highlighting || inSegment;
    L.circleMarker([point.lat, point.lng], {
      radius: active ? 7 : 5,
      color: '#0b1a33',
      weight: 2,
      fillColor: active ? '#59e0ff' : '#9bb2ff',
      fillOpacity: 1,
    })
      .addTo(map)
      .bindPopup(`<strong>${point.name}</strong>`);
  });

  // Önce düz çizgiyle çiz (anında bir şey görünsün), sonra gerçek yolla değiştir.
  const straight = L.polyline(
    valid.map((p) => [p.lat, p.lng] as [number, number]),
    { color: '#67a6ff', weight: 3, opacity: 0.45, dashArray: '6 6' },
  ).addTo(map);

  let fitTarget: L.LatLngBounds = straight.getBounds();

  /** Konteyner boyutu kesinleştikten sonra ölç ve sığdır (Leaflet'in klasik 0-boyut hatası). */
  const refit = () => {
    map.invalidateSize({ animate: false });
    if (fitTarget.isValid()) map.fitBounds(fitTarget, { padding: [24, 24] });
  };

  // Gerçek yol geometrisini yükle ve düz çizgiyi değiştir
  loadGeometry().then((geo) => {
    if (!geo?.legs?.length) {
      refit();
      return;
    }
    straight.remove();

    const drawn: L.Polyline[] = [];
    geo.legs.forEach((leg, i) => {
      if (!leg.coords?.length) return;
      const inSegment = i >= segStart && i < segEnd;
      const active = !highlighting || inSegment;
      // Alt gölge + üst renk: kalın, okunur bir rota çizgisi
      L.polyline(leg.coords, { color: '#0b1a33', weight: active ? 8 : 5, opacity: 0.5 }).addTo(map);
      const line = L.polyline(leg.coords, {
        color: active ? '#59e0ff' : '#7f97d6',
        weight: active ? 4.5 : 2.5,
        opacity: active ? 0.95 : 0.55,
        lineJoin: 'round',
        lineCap: 'round',
      }).addTo(map);
      line.bindPopup(
        `<strong>${leg.from} → ${leg.to}</strong><br>${Math.round(leg.distance / 1000)} km · ` +
          `${(leg.duration / 3600).toFixed(1)} sa`,
      );
      if (active) drawn.push(line);
    });

    // Vurgulanan etap varsa ona, yoksa tüm rotaya sığdır
    if (drawn.length) {
      let b = drawn[0].getBounds();
      drawn.slice(1).forEach((l) => { b = b.extend(l.getBounds()); });
      fitTarget = b;
    }
    refit();
  });

  // Boyut kesinleşince / görünür olunca / pencere değişince yeniden sığdır.
  requestAnimationFrame(refit);
  window.addEventListener('load', refit);
  window.addEventListener('resize', refit);

  if ('ResizeObserver' in window) {
    let last = 0;
    new ResizeObserver((entries) => {
      const w = entries[0]?.contentRect.width ?? 0;
      if (w > 0 && Math.abs(w - last) > 1) { last = w; refit(); }
    }).observe(container);
  }

  if ('IntersectionObserver' in window) {
    const io = new IntersectionObserver((entries) => {
      if (entries.some((e) => e.isIntersecting)) { refit(); io.disconnect(); }
    }, { threshold: 0.05 });
    io.observe(container);
  }

  wrapper.classList.add('ready');
}
