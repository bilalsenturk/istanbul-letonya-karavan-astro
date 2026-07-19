import MapKit

// Gerçek sürüş rotası: Apple Haritalar (MKDirections) ile her ardışık durak
// arasındaki gerçek yol. Etaplar POZİSYONEL hizalı tutulur: legs[i] = stops[i]→stops[i+1]
// (bir etap başarısızsa nil) — böylece indeksler durak çiftleriyle bozulmadan eşleşir.
@MainActor
final class RouteStore: ObservableObject {
    @Published private(set) var legs: [MKRoute?] = []
    @Published private(set) var computing = false

    private var computedFor: [String] = []

    /// Haritada çizim için başarılı etaplar.
    var routes: [MKRoute] { legs.compactMap { $0 } }

    /// Duraklar için gerçek yolu hesapla. Yalnızca TAM başarıda önbelleğe alınır;
    /// kısmi/çevrimdışı başarısızlık önbelleği zehirlemez, sonraki çağrıda tekrar denenir.
    func computeIfNeeded(stops: [Stop]) async {
        let ids = stops.map(\.id)
        guard stops.count >= 2, ids != computedFor, !computing else { return }
        computing = true
        defer { computing = false }

        var built = [MKRoute?](repeating: nil, count: stops.count - 1)
        legs = built
        var allSucceeded = true
        for i in 0 ..< (stops.count - 1) {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: stops[i].coordinate))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: stops[i + 1].coordinate))
            request.transportType = .automobile
            if let response = try? await MKDirections(request: request).calculate(),
               let route = response.routes.first {
                built[i] = route
                legs = built            // artan çizim (yol yol belirir)
            } else {
                allSucceeded = false
            }
        }
        if allSucceeded { computedFor = ids }
    }

    /// Apple'ın hesapladığı gerçek toplam mesafe (km) — hesaplanan etaplar üzerinden.
    var totalDistanceKm: Int {
        Int((routes.reduce(0) { $0 + $1.distance } / 1000).rounded())
    }

    /// Apple'ın hesapladığı gerçek toplam sürüş süresi.
    var totalTravelTime: TimeInterval {
        routes.reduce(0) { $0 + $1.expectedTravelTime }
    }
}
