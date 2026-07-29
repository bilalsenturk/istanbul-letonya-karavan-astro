import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { routeMapInteractionOptions } from './liveSync';
import { selectGeometryLegs, type Geometry, type Leg, type RouteMapMode, type Stop } from './routeMapData';
type LiveMapDetail = {
  position?: { lat: number; lng: number };
  lat?: number;
  lng?: number;
  routeStarted?: boolean;
  activeRouteStop?: string | null;
  activeRouteCode?: string | null;
  activeRouteStartedAt?: string | null;
  nextStop?: string | null;
  nextFlag?: string | null;
  remainingKm?: number | null;
  remainingMin?: number | null;
  remainingToFinalKm?: number | null;
  traveledKm?: number | null;
  legProgress?: number | null;
  speedKmh?: number | null;
  city?: string | null;
  ts?: string | null;
};

declare global {
  interface Window {
    __kuzeyLiveState?: LiveMapDetail;
  }
}

let geometryCache: Promise<Geometry | null> | null = null;
const rigIconUrl = '/assets/passat-adria-map-icon.svg';

/** Gerçek sürüş rotası (yolları takip eden). Yoksa null -> düz çizgiye düşülür. */
function loadGeometry(): Promise<Geometry | null> {
  if (!geometryCache) {
    geometryCache = fetch('/assets/route-geometry.json')
      .then((r) => (r.ok ? r.json() : null))
      .catch(() => null);
  }
  return geometryCache;
}

const sameStop = (a: string, b: string): boolean => a.localeCompare(b, 'tr', { sensitivity: 'base' }) === 0;

const fmtKm = (value: number | null | undefined): string | null => {
  if (typeof value !== 'number' || !Number.isFinite(value)) return null;
  return `${Math.round(value).toLocaleString('tr-TR')} km`;
};

const fmtMin = (value: number | null | undefined): string | null => {
  if (typeof value !== 'number' || !Number.isFinite(value)) return null;
  const rounded = Math.max(0, Math.round(value));
  return rounded >= 60 ? `${Math.floor(rounded / 60)} sa ${rounded % 60} dk` : `${rounded} dk`;
};

const clamp = (value: number, min = 0, max = 1): number => Math.max(min, Math.min(max, value));

const normalizedProgress = (value: number | null | undefined): number => {
  if (typeof value !== 'number' || !Number.isFinite(value)) return 0;
  return clamp(value > 1 ? value / 100 : value);
};

const bringToFrontSafely = (layer: { bringToFront?: () => unknown } | null | undefined): void => {
  try {
    layer?.bringToFront?.();
  } catch {
    /* Leaflet can throw while SVG panes are still attaching. Next render restyles the layer. */
  }
};

function bearing(from: L.LatLng, to: L.LatLng): number {
  const toRad = (v: number) => (v * Math.PI) / 180;
  const toDeg = (v: number) => (v * 180) / Math.PI;
  const lat1 = toRad(from.lat);
  const lat2 = toRad(to.lat);
  const dLng = toRad(to.lng - from.lng);
  const y = Math.sin(dLng) * Math.cos(lat2);
  const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLng);
  return (toDeg(Math.atan2(y, x)) + 360) % 360;
}

function coordsUpToProgress(coords: [number, number][], progress: number): [number, number][] {
  const p = normalizedProgress(progress);
  if (coords.length < 2 || p <= 0) return [];
  if (p >= 1) return coords;

  const distances = coords.slice(1).map((coord, i) => {
    const prev = coords[i];
    return L.latLng(prev[0], prev[1]).distanceTo(L.latLng(coord[0], coord[1]));
  });
  const total = distances.reduce((sum, distance) => sum + distance, 0);
  if (total <= 0) return coords.slice(0, 2);

  const target = total * p;
  let traveled = 0;
  const out: [number, number][] = [coords[0]];
  for (let i = 1; i < coords.length; i += 1) {
    const segment = distances[i - 1] ?? 0;
    if (traveled + segment < target) {
      out.push(coords[i]);
      traveled += segment;
      continue;
    }

    const ratio = segment > 0 ? (target - traveled) / segment : 0;
    const prev = coords[i - 1];
    const next = coords[i];
    out.push([
      prev[0] + (next[0] - prev[0]) * ratio,
      prev[1] + (next[1] - prev[1]) * ratio,
    ]);
    break;
  }
  return out.length > 1 ? out : [];
}

function ensureRigStyles(): void {
  if (document.getElementById('kuzey-rig-marker-style')) return;
  const style = document.createElement('style');
  style.id = 'kuzey-rig-marker-style';
  style.textContent = `
    .kuzey-rig-icon {
      background: transparent;
      border: 0;
    }

    .kuzey-rig {
      --rig-rot: 0deg;
      position: relative;
      width: 70px;
      height: 42px;
      transform: rotate(var(--rig-rot));
      transform-origin: 50% 50%;
      filter: drop-shadow(0 9px 13px rgba(0, 0, 0, 0.36));
      will-change: transform;
    }

    .kuzey-rig.is-moving {
      animation: kuzey-rig-drive 900ms ease-in-out infinite alternate;
    }

    .kuzey-rig__shadow {
      position: absolute;
      left: 10px;
      right: 8px;
      bottom: 4px;
      height: 8px;
      border-radius: 999px;
      background: rgba(0, 0, 0, 0.26);
      filter: blur(4px);
    }

    .kuzey-rig__image {
      position: absolute;
      inset: 0;
      width: 100%;
      height: 100%;
      object-fit: contain;
      pointer-events: none;
    }

    @keyframes kuzey-rig-drive {
      from { translate: -0.8px 0.3px; }
      to { translate: 1px -0.4px; }
    }

    .leaflet-control-zoom {
      overflow: hidden;
      border: 1px solid rgba(255, 255, 255, 0.18) !important;
      border-radius: 8px !important;
      background: rgba(7, 13, 24, 0.78) !important;
      box-shadow: 0 10px 28px rgba(0, 0, 0, 0.28) !important;
      backdrop-filter: blur(14px);
      -webkit-backdrop-filter: blur(14px);
    }

    .leaflet-control-zoom a,
    .leaflet-control-zoom-in,
    .leaflet-control-zoom-out {
      display: block !important;
      width: 34px !important;
      height: 34px !important;
      line-height: 32px !important;
      border: 0 !important;
      background: rgba(255, 255, 255, 0.94) !important;
      color: #0a1421 !important;
      font: 700 19px/32px ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif !important;
    }

    .leaflet-control-zoom-in {
      border-bottom: 1px solid rgba(10, 20, 33, 0.12) !important;
    }

    .leaflet-control-zoom-out {
      display: block !important;
    }
  `;
  document.head.appendChild(style);
}

function rigIcon(rotation: number, moving: boolean): L.DivIcon {
  const classes = moving ? 'kuzey-rig is-moving' : 'kuzey-rig';
  return L.divIcon({
    className: 'kuzey-rig-icon',
    iconSize: [70, 42],
    iconAnchor: [35, 21],
    popupAnchor: [0, -22],
    html: `
      <div class="${classes}" style="--rig-rot:${rotation}deg" aria-hidden="true">
        <span class="kuzey-rig__shadow"></span>
        <img class="kuzey-rig__image" src="${rigIconUrl}" alt="" decoding="async" draggable="false" />
      </div>
    `,
  });
}

function liveLatLng(detail: LiveMapDetail | null): L.LatLng | null {
  if (!detail) return null;
  const lat = typeof detail.position?.lat === 'number' ? detail.position.lat : detail.lat;
  const lng = typeof detail.position?.lng === 'number' ? detail.position.lng : detail.lng;
  if (typeof lat !== 'number' || typeof lng !== 'number') return null;
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
  return L.latLng(lat, lng);
}

export function initRouteMap(container: HTMLElement): void {
  if (container.dataset.mapRendered === 'true') return;
  container.dataset.mapRendered = 'true';

  const wrapper = container.closest('.route-map-container');
  if (!wrapper) return;
  const liveStatus = wrapper.querySelector<HTMLElement>('[data-route-live-status]');

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
  ensureRigStyles();

  const compact = container.dataset.compact === 'true';
  const mode: RouteMapMode = container.dataset.mode === 'day' ? 'day' : 'journey';
  const liveEnabled = container.dataset.live === 'true';
  const map = L.map(container, routeMapInteractionOptions(compact));
  if (!compact) L.control.zoom({ position: 'bottomright' }).addTo(map);

  const tiles = L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    maxZoom: 18,
  }).addTo(map);
  tiles.on('load', () => wrapper.classList.add('ready'));
  tiles.on('tileerror', () => wrapper.classList.remove('ready'));

  const from = String(container.dataset.from || '');
  const to = String(container.dataset.to || '');
  const startIdx = valid.findIndex((p) => sameStop(p.name, from));
  const endIdx = valid.findIndex((p) => sameStop(p.name, to));
  const segStart = startIdx >= 0 ? startIdx : 0;
  const segEnd = endIdx >= 0 ? Math.max(segStart, endIdx) : segStart;

  let lastLiveState: LiveMapDetail | null = liveEnabled ? window.__kuzeyLiveState ?? null : null;
  let liveMarker: L.Marker | null = null;
  let lastFocusKey = '';
  const legLayers: Array<{ shadow: L.Polyline; line: L.Polyline; leg: Leg; index: number }> = [];
  const progressLayers: L.Polyline[] = [];

  const activeLiveLegIndex = (): number | null => {
    if (!lastLiveState?.routeStarted) return null;
    const targetName = lastLiveState.activeRouteStop || lastLiveState.nextStop;
    if (!targetName) return null;
    const targetIdx = valid.findIndex((p) => sameStop(p.name, targetName));
    return targetIdx > 0 ? targetIdx - 1 : null;
  };

  const activeTargetLatLng = (): L.LatLng | null => {
    const targetName = lastLiveState?.activeRouteStop || lastLiveState?.nextStop;
    if (!targetName) return null;
    const target = valid.find((p) => sameStop(p.name, targetName));
    return target ? L.latLng(target.lat, target.lng) : null;
  };

  const markerRotation = (latlng: L.LatLng): number => {
    const target = activeTargetLatLng();
    return target ? bearing(latlng, target) - 270 : 0;
  };

  const clearProgressLayers = () => {
    while (progressLayers.length) {
      const layer = progressLayers.pop();
      if (layer) layer.remove();
    }
  };

  const addProgressLayer = (coords: [number, number][]) => {
    if (coords.length < 2) return;
    const shadow = L.polyline(coords, {
      color: '#071425',
      weight: 8,
      opacity: 0.42,
      lineJoin: 'round',
      lineCap: 'round',
    }).addTo(map);
    const line = L.polyline(coords, {
      color: '#38e08a',
      weight: 4.5,
      opacity: 0.98,
      lineJoin: 'round',
      lineCap: 'round',
    }).addTo(map);
    progressLayers.push(shadow, line);
    bringToFrontSafely(shadow);
    bringToFrontSafely(line);
  };

  const styleLegs = () => {
    legLayers.forEach(({ shadow, line }) => {
      shadow.setStyle({ weight: 6, opacity: 0.22 });
      line.setStyle({
        color: '#8090a8',
        weight: 2.8,
        opacity: 0.58,
      });
    });
    clearProgressLayers();
    const liveIndex = activeLiveLegIndex();
    if (liveIndex != null) {
      legLayers
        .filter(({ index }) => index < liveIndex)
        .forEach(({ leg }) => addProgressLayer(leg.coords));

      const current = legLayers.find(({ index }) => index === liveIndex);
      if (current) addProgressLayer(coordsUpToProgress(current.leg.coords, normalizedProgress(lastLiveState?.legProgress)));
    }
    progressLayers.forEach(bringToFrontSafely);
    liveMarker?.setZIndexOffset(1000);
  };

  const updateLiveStatus = () => {
    if (!liveEnabled) return;
    if (!liveStatus || !lastLiveState) return;
    const target = lastLiveState.activeRouteStop || lastLiveState.nextStop;
    const parts = ['KUZEY'];
    if (lastLiveState.routeStarted && target) parts.push(target);
    else parts.push('rota başlamadı');
    const remaining = [fmtKm(lastLiveState.remainingKm), fmtMin(lastLiveState.remainingMin)].filter(Boolean).join(' · ');
    if (remaining) parts.push(remaining);
    liveStatus.textContent = parts.join(' · ');
    wrapper.classList.add('has-live');
  };

  const focusLiveRoute = (latlng: L.LatLng): boolean => {
    const liveIndex = activeLiveLegIndex();
    const activeLayer = liveIndex == null ? null : legLayers.find((item) => item.index === liveIndex)?.line;
    if (!activeLayer) return false;
    const bounds = activeLayer.getBounds().extend(latlng);
    if (!bounds.isValid()) return false;
    map.fitBounds(bounds, {
      padding: compact ? [14, 14] : [34, 34],
      maxZoom: compact ? 8 : 10,
    });
    return true;
  };

  const applyLiveState = () => {
    const latlng = liveLatLng(lastLiveState);
    if (!latlng) return;
    const moving = lastLiveState?.routeStarted === true && (lastLiveState.speedKmh ?? 0) > 2;
    const icon = rigIcon(markerRotation(latlng), moving);

    if (!liveMarker) {
      liveMarker = L.marker(latlng, { icon, keyboard: false, zIndexOffset: 1000 }).addTo(map);
    } else {
      liveMarker.setLatLng(latlng);
      liveMarker.setIcon(icon);
    }

    const target = lastLiveState?.activeRouteStop || lastLiveState?.nextStop;
    const detailParts = [
      lastLiveState?.city ? `Şu an: ${lastLiveState.city}` : null,
      target ? `Hedef: ${target}` : null,
      fmtKm(lastLiveState?.remainingKm),
      fmtMin(lastLiveState?.remainingMin),
    ].filter(Boolean);
    liveMarker.bindPopup(`<strong>Konum</strong><br>${detailParts.join(' · ')}`);

    styleLegs();
    updateLiveStatus();

    const focusKey = `${lastLiveState?.routeStarted === true}:${target || ''}`;
    if (focusKey !== lastFocusKey && focusLiveRoute(latlng)) lastFocusKey = focusKey;
  };

  valid.forEach((point, index) => {
    const inSegment = index >= segStart && index <= segEnd;
    L.circleMarker([point.lat, point.lng], {
      radius: inSegment ? 6 : 4.5,
      color: '#0b1a33',
      weight: 2,
      fillColor: inSegment ? '#a9b8ce' : '#7e8fa8',
      fillOpacity: inSegment ? 0.92 : 0.7,
    })
      .addTo(map)
      .bindPopup(`<strong>${point.name}</strong>`);
  });

  const straight = L.polyline(
    valid.map((p) => [p.lat, p.lng] as [number, number]),
    { color: '#67a6ff', weight: 3, opacity: 0.45, dashArray: '6 6' },
  ).addTo(map);

  let fitTarget: L.LatLngBounds = straight.getBounds();

  const refit = () => {
    map.invalidateSize({ animate: false });
    if (fitTarget.isValid()) {
      map.fitBounds(fitTarget, {
        padding: compact ? [12, 12] : [24, 24],
        ...(compact ? { maxZoom: 8 } : {}),
      });
    }
  };

  loadGeometry().then((geo) => {
    if (!geo?.legs?.length) {
      refit();
      applyLiveState();
      return;
    }
    straight.remove();

    const drawn: L.Polyline[] = [];
    selectGeometryLegs(geo, from, to, mode).forEach((leg, i) => {
      if (!leg.coords?.length) return;
      const shadow = L.polyline(leg.coords, { color: '#0b1a33', weight: 6, opacity: 0.22 }).addTo(map);
      const line = L.polyline(leg.coords, {
        color: '#8090a8',
        weight: 2.8,
        opacity: 0.58,
        lineJoin: 'round',
        lineCap: 'round',
      }).addTo(map);
      line.bindPopup(
        `<strong>${leg.from} -> ${leg.to}</strong><br>${Math.round(leg.distance / 1000)} km · ` +
          `${(leg.duration / 3600).toFixed(1)} sa`,
      );
      legLayers.push({ shadow, line, leg, index: i });
      drawn.push(line);
    });

    if (drawn.length) {
      let b = drawn[0].getBounds();
      drawn.slice(1).forEach((l) => { b = b.extend(l.getBounds()); });
      fitTarget = b;
    }
    refit();
    lastFocusKey = '';
    applyLiveState();
  });

  if (liveEnabled) {
    const onLiveLocation = (event: Event) => {
      const detail = (event as CustomEvent<LiveMapDetail>).detail;
      if (!detail) return;
      lastLiveState = detail;
      applyLiveState();
    };
    window.addEventListener('kuzey:live-location', onLiveLocation);
    window.addEventListener('pagehide', () => window.removeEventListener('kuzey:live-location', onLiveLocation), { once: true });
  }

  requestAnimationFrame(() => {
    refit();
    applyLiveState();
  });
  window.addEventListener('load', refit);
  window.addEventListener('resize', refit);

  if ('ResizeObserver' in window) {
    let last = 0;
    new ResizeObserver((entries) => {
      const w = entries[0]?.contentRect.width ?? 0;
      if (w > 0 && Math.abs(w - last) > 1) {
        last = w;
        refit();
      }
    }).observe(container);
  }

  if ('IntersectionObserver' in window) {
    const io = new IntersectionObserver((entries) => {
      if (entries.some((e) => e.isIntersecting)) {
        refit();
        io.disconnect();
      }
    }, { threshold: 0.05 });
    io.observe(container);
  }

}
