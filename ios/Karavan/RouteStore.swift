import MapKit

// Bir etabın kalıcı özeti (offline yedek): seyreltilmiş rota noktaları + mesafe + süre.
struct LegSnapshot: Codable {
    let coords: [[Double]]        // [lat, lng] çiftleri (≤ ~400 nokta/etap)
    let distance: Double          // metre
    let time: Double              // saniye
}

// Gerçek sürüş rotası: Apple Haritalar (MKDirections). Etaplar POZİSYONEL hizalı:
// legs[i] = stops[i]→stops[i+1] (başarısızsa nil). Tam başarıda diske kaydedilir;
// sinyalsiz sınır bölgelerinde rota diskteki kopyadan çizilir (offline paket).
@MainActor
final class RouteStore: ObservableObject {
    @Published private(set) var legs: [MKRoute?] = []
    @Published private(set) var cached: [LegSnapshot]? = nil
    @Published private(set) var computing = false

    private var computedFor: [String] = []

    private static var cacheURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("route-cache.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.cacheURL),
           let decoded = try? JSONDecoder().decode([LegSnapshot].self, from: data) {
            cached = decoded
        }
    }

    /// Haritada çizim için etap koordinatları — canlı rota varsa o, yoksa disk kopyası.
    var displayCoords: [[CLLocationCoordinate2D]] {
        if legs.contains(where: { $0 != nil }) {
            return legs.compactMap { route in
                route.map { Self.decimated($0.polyline) }
            }
        }
        return (cached ?? []).map { leg in
            leg.coords.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
        }
    }

    /// Etap mesafe+süresi — canlı MKRoute > disk kopyası > nil.
    func legInfo(_ index: Int) -> (distance: Double, time: Double)? {
        if legs.indices.contains(index), let r = legs[index] {
            return (r.distance, r.expectedTravelTime)
        }
        if let c = cached, c.indices.contains(index) {
            return (c[index].distance, c[index].time)
        }
        return nil
    }

    var legCount: Int { max(legs.count, cached?.count ?? 0) }

    /// Duraklar için gerçek yolu hesapla. Yalnızca TAM başarıda önbellek + disk güncellenir.
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
        if allSucceeded {
            computedFor = ids
            persist(built.compactMap { $0 })
        }
    }

    private func persist(_ routes: [MKRoute]) {
        let snapshots = routes.map { route in
            LegSnapshot(
                coords: Self.decimated(route.polyline).map { [$0.latitude, $0.longitude] },
                distance: route.distance,
                time: route.expectedTravelTime
            )
        }
        cached = snapshots
        if let data = try? JSONEncoder().encode(snapshots) {
            try? data.write(to: Self.cacheURL, options: .atomic)
        }
    }

    /// Rota noktalarını ≤ ~400 noktaya seyrelt (çizim + disk için yeterli, hafif).
    private static func decimated(_ polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        let count = polyline.pointCount
        guard count > 0 else { return [] }
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: count)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))
        let step = max(1, count / 400)
        var out = stride(from: 0, to: count, by: step).map { coords[$0] }
        if let last = coords.last, out.last.map({ $0.latitude != last.latitude || $0.longitude != last.longitude }) ?? true {
            out.append(last)
        }
        return out
    }

    /// Apple'ın hesapladığı gerçek toplam mesafe (km) — canlı ya da disk.
    var totalDistanceKm: Int {
        var total = 0.0
        for i in 0 ..< legCount { total += legInfo(i)?.distance ?? 0 }
        return Int((total / 1000).rounded())
    }

    /// Gerçek toplam sürüş süresi — canlı ya da disk.
    var totalTravelTime: TimeInterval {
        var total = 0.0
        for i in 0 ..< legCount { total += legInfo(i)?.time ?? 0 }
        return total
    }

    var hasRoute: Bool { legCount > 0 && (legs.contains(where: { $0 != nil }) || cached != nil) }
}
