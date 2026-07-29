export type RouteMapImporter = () => Promise<{ initRouteMap(container: HTMLElement): void }>;

const importRouteMap: RouteMapImporter = () => import('./routeMap');

export function registerRouteMapFallbacks(root: ParentNode = document): void {
  const images = Array.from(root.querySelectorAll<HTMLImageElement>('.fallback-map-image'));

  images.forEach((image) => {
    const fallback = image.closest<HTMLElement>('.fallback-map');
    const markFailed = () => fallback?.classList.add('fallback-map--failed');

    if (image.dataset.fallbackBound !== 'true') {
      image.dataset.fallbackBound = 'true';
      image.addEventListener('error', markFailed, { once: true });
    }

    if (image.complete && image.naturalWidth === 0) markFailed();
  });
}

export function registerRouteMaps(
  root: ParentNode = document,
  importer: RouteMapImporter = importRouteMap,
): () => void {
  registerRouteMapFallbacks(root);
  const containers = Array.from(root.querySelectorAll<HTMLElement>('.route-map'));
  const initialize = (container: HTMLElement) => {
    if (container.dataset.mapInitialized === 'true') return;
    container.dataset.mapInitialized = 'true';
    importer().then(({ initRouteMap }) => initRouteMap(container)).catch(() => {
      container.dataset.mapInitialized = 'false';
    });
  };

  if (!('IntersectionObserver' in window)) {
    containers.forEach(initialize);
    return () => {};
  }

  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      observer.unobserve(entry.target);
      initialize(entry.target as HTMLElement);
    });
  }, { rootMargin: '300px 0px', threshold: 0.01 });

  containers.forEach((container) => {
    if (container.dataset.mapInitialized !== 'true') observer.observe(container);
  });
  return () => observer.disconnect();
}
