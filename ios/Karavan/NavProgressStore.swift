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

    func update(location: CLLocation?, stops: [Stop], legs: [MKRoute]) async {
        guard let location, stops.count >= 2 else { return }

        // Kısıtla: yalnızca 700 m'den fazla hareket ya da 45 sn geçmişse yeniden hesapla.
        let now = Date()
        if let last = lastCoord {
            let moved = location.distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
            if moved < 700, now.timeIntervalSince(lastComputeAt) < 45 { return }
        }
        lastCoord = location.coordinate
        lastComputeAt = now

        // 1) Sıradaki durak: en yakın durak; ona çok yakınsak (ya da başlangıçtaysak) sıradaki.
        var nearest = 0
        var best = Double.infinity
        for (i, s) in stops.enumerated() {
            let d = meters(location, to: s)
            if d < best { best = d; nearest = i }
        }
        var idx = nearest
        if nearest == 0 || best < 12_000 { idx = min(nearest + 1, stops.count - 1) }
        let next = stops[idx]
        let prevIdx = max(0, idx - 1)
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
        if legs.indices.contains(prevIdx) {
            legTotal = legs[prevIdx].distance
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
