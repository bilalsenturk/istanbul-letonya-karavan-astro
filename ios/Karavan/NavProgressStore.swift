import MapKit
import CoreLocation

// Canlı yolculuk ilerlemesi: sıradaki hedef, kalan km + SÜRE (Apple Maps ETA),
// gidilen yol ve anlık şehir. Konum değiştikçe (kısıtlı) güncellenir.
@MainActor
final class NavProgressStore: ObservableObject {
    @Published var nextStop: Stop?
    @Published var remainingKm: Int?
    @Published var remainingMinutes: Int?
    @Published var traveledKm: Int?
    @Published var legProgress: Double = 0     // 0…1
    @Published var currentCity: String?

    private var lastComputeAt: Date = .distantPast
    private var lastCoord: CLLocationCoordinate2D?
    private let geocoder = CLGeocoder()

    private func meters(_ location: CLLocation, to stop: Stop) -> Double {
        location.distance(from: CLLocation(latitude: stop.lat, longitude: stop.lng))
    }

    /// Noktanın [a,b] segmentine yaklaşık (dik) uzaklığı — hangi etapta olduğunu bulmak için.
    private func distanceToSegment(_ p: CLLocation, from a: Stop, to b: Stop) -> Double {
        let ca = CLLocation(latitude: a.lat, longitude: a.lng)
        let cb = CLLocation(latitude: b.lat, longitude: b.lng)
        let ab = ca.distance(from: cb)
        guard ab > 1 else { return p.distance(from: ca) }
        let ap = p.distance(from: ca)
        let bp = p.distance(from: cb)
        let t = max(0, min(1, (ap * ap - bp * bp + ab * ab) / (2 * ab * ab)))
        let along = t * ab
        let perpSq = max(0, ap * ap - along * along)
        return perpSq.squareRoot()
    }

    func update(location: CLLocation?, stops: [Stop], legs: [MKRoute?]) async {
        guard let location, stops.count >= 2 else { return }

        // Kısıtla: yalnızca 700 m'den fazla hareket ya da 45 sn geçmişse yeniden hesapla.
        let now = Date()
        if let last = lastCoord {
            let moved = location.distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
            if moved < 700, now.timeIntervalSince(lastComputeAt) < 45 { return }
        }
        lastCoord = location.coordinate
        lastComputeAt = now

        // 1) Bulunduğun ETABI (segment) bul; sıradaki durak o etabın bitişidir.
        //    "En yakın durak" heuristiği etabın ilk yarısında ayrıldığın şehri
        //    "sıradaki" gösterip kalan km'yi geriye hesaplıyordu — segment bunu çözer.
        var bestLeg = 0
        var bestSeg = Double.infinity
        for k in 0 ..< (stops.count - 1) {
            let d = distanceToSegment(location, from: stops[k], to: stops[k + 1])
            if d < bestSeg { bestSeg = d; bestLeg = k }
        }
        let idx = bestLeg + 1
        let prevIdx = bestLeg
        let next = stops[idx]
        nextStop = next

        // 2) Kalan km + SÜRE — Apple Maps (MKDirections) ile gerçek sürüş.
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: next.coordinate))
        request.transportType = .automobile

        let remainingMeters: Double
        if let response = try? await MKDirections(request: request).calculate(), let route = response.routes.first {
            remainingMeters = route.distance
            remainingKm = Int((route.distance / 1000).rounded())
            remainingMinutes = Int((route.expectedTravelTime / 60).rounded())
        } else {
            remainingMeters = meters(location, to: next)
            remainingKm = Int((remainingMeters / 1000).rounded())
            remainingMinutes = Int((remainingMeters / 1000) / 80 * 60) // ~80 km/s tahmini
        }

        // 3) Gidilen yol + ilerleme (etabın toplamından).
        let legTotal: Double
        if legs.indices.contains(prevIdx), let leg = legs[prevIdx] {
            legTotal = leg.distance
        } else {
            legTotal = CLLocation(latitude: stops[prevIdx].lat, longitude: stops[prevIdx].lng)
                .distance(from: CLLocation(latitude: next.lat, longitude: next.lng))
        }
        let traveled = max(0, legTotal - remainingMeters)
        traveledKm = Int((traveled / 1000).rounded())
        legProgress = legTotal > 0 ? min(1, max(0, traveled / legTotal)) : 0

        // 4) Anlık şehir (ters coğrafi kodlama, best-effort).
        if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
            currentCity = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea
        }
    }

    var remainingTimeText: String {
        guard let m = remainingMinutes else { return "—" }
        if m >= 60 { return "\(m / 60) sa \(m % 60) dk" }
        return "\(m) dk"
    }
}
