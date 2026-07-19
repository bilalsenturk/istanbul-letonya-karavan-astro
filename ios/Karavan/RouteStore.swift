import MapKit

// Gerçek sürüş rotası: Apple Haritalar (MKDirections) ile her ardışık durak
// arasındaki gerçek yol hesaplanır. Düz kırmızı çizgi yerine gerçek yollar çizilir.
@MainActor
final class RouteStore: ObservableObject {
    @Published private(set) var routes: [MKRoute] = []
    @Published private(set) var computing = false

    private var computedFor: [String] = []

    /// Duraklar için gerçek yolu hesapla (yalnızca bir kez; duraklar değişmedikçe tekrar etmez).
    func computeIfNeeded(stops: [Stop]) async {
        let ids = stops.map(\.id)
        guard stops.count >= 2, ids != computedFor else { return }
        computedFor = ids
        computing = true
        var collected: [MKRoute] = []
        for i in 0 ..< (stops.count - 1) {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: stops[i].coordinate))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: stops[i + 1].coordinate))
            request.transportType = .automobile
            if let response = try? await MKDirections(request: request).calculate(),
               let route = response.routes.first {
                collected.append(route)
                routes = collected            // artan şekilde çiz (yol yol belirir)
            }
        }
        computing = false
    }

    /// Apple'ın hesapladığı gerçek toplam mesafe (km).
    var totalDistanceKm: Int {
        Int((routes.reduce(0) { $0 + $1.distance } / 1000).rounded())
    }

    /// Apple'ın hesapladığı gerçek toplam sürüş süresi.
    var totalTravelTime: TimeInterval {
        routes.reduce(0) { $0 + $1.expectedTravelTime }
    }
}
