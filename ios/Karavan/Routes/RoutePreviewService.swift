import MapKit

@MainActor
final class RoutePreviewService: ObservableObject {
    @Published private(set) var coordinates: [CLLocationCoordinate2D] = []
    @Published private(set) var distanceKm: Int?
    @Published private(set) var durationMinutes: Int?
    @Published private(set) var isLoading = false

    private var task: Task<Void, Never>?

    func update(stops: [RouteDraftStop], mode: RouteTransportMode) {
        task?.cancel()
        guard stops.count >= 2 else {
            coordinates = stops.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
            distanceKm = nil
            durationMinutes = nil
            return
        }
        task = Task {
            isLoading = true
            defer { isLoading = false }
            if mode == .flight {
                let points = stops.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
                let meters = zip(points, points.dropFirst()).reduce(0.0) { total, pair in
                    total + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                        .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
                }
                guard !Task.isCancelled else { return }
                coordinates = points
                distanceKm = Int((meters / 1000).rounded())
                let flightMinutes = meters / 1000 / 800 * 60
                durationMinutes = max(60, Int(flightMinutes.rounded()) + ((stops.count - 1) * 120))
                return
            }
            var routeCoordinates: [CLLocationCoordinate2D] = []
            var meters: CLLocationDistance = 0
            var seconds: TimeInterval = 0
            for pair in zip(stops, stops.dropFirst()) {
                guard !Task.isCancelled else { return }
                let request = MKDirections.Request()
                request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: pair.0.lat, longitude: pair.0.lng)))
                request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: pair.1.lat, longitude: pair.1.lng)))
                request.transportType = mode == .walking ? .walking : .automobile
                do {
                    guard let route = try await MKDirections(request: request).calculate().routes.first else { continue }
                    var segment = route.polyline.coordinates
                    if !routeCoordinates.isEmpty && !segment.isEmpty { segment.removeFirst() }
                    routeCoordinates.append(contentsOf: segment)
                    meters += route.distance
                    seconds += route.expectedTravelTime
                } catch {
                    let directMeters = CLLocation(latitude: pair.0.lat, longitude: pair.0.lng)
                        .distance(from: CLLocation(latitude: pair.1.lat, longitude: pair.1.lng))
                    meters += directMeters
                    let fallbackSpeed = mode == .walking ? 5.0 : 70.0
                    seconds += directMeters / 1000 / fallbackSpeed * 3600
                    routeCoordinates.append(contentsOf: [
                        CLLocationCoordinate2D(latitude: pair.0.lat, longitude: pair.0.lng),
                        CLLocationCoordinate2D(latitude: pair.1.lat, longitude: pair.1.lng)
                    ])
                }
            }
            guard !Task.isCancelled else { return }
            coordinates = routeCoordinates
            distanceKm = meters > 0 ? Int((meters / 1000).rounded()) : nil
            durationMinutes = seconds > 0 ? Int((seconds / 60).rounded()) : nil
        }
    }
}

private extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var values = [CLLocationCoordinate2D](repeating: .init(), count: pointCount)
        getCoordinates(&values, range: NSRange(location: 0, length: pointCount))
        return values
    }
}
