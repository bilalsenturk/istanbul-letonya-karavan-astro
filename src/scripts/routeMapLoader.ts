export type RouteMapImporter = () => Promise<{ initRouteMap(container: HTMLElement): void }>;

const importRouteMap: RouteMapImporter = () => import('./routeMap');

export function registerRouteMaps(
  root: ParentNode = document,
  importer: RouteMapImporter = importRouteMap,
): () => void {
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
