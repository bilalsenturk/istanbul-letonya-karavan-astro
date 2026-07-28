import MapKit
import CoreLocation

// Bir durağa tahmini varış (zincirleme ETA için).
struct StopArrival: Identifiable {
    let id: String
    let name: String
    let code: String
    let eta: Date
}

// Canlı yolculuk ilerlemesi: sıradaki hedef, kalan km + SÜRE (Apple Maps ETA),
// gidilen yol, anlık şehir ve kalan tüm duraklara zincirleme varış tahmini.
@MainActor
final class NavProgressStore: ObservableObject {
    @Published var nextStop: Stop?
    @Published var remainingKm: Int?
    /// Riga'ya kalan GERÇEK yol: sıradaki durağa sürüş + kalan etapların rota mesafeleri.
    /// Kuş uçuşu DEĞİL — düz çizgi İstanbul→Riga ~1800 km, yol ise ~3300 km.
    @Published var remainingToFinalKm: Int?
    @Published var remainingMinutes: Int?
    @Published var traveledKm: Int?
    @Published var legProgress: Double = 0     // 0…1
    @Published var currentCity: String?
    @Published var arrivals: [StopArrival] = []
    @Published var currentLegIndex: Int?       // rota-sapma (SOS) kontrolü için

    private var lastComputeAt: Date = .distantPast
    private var lastCoord: CLLocationCoordinate2D?
    private let geocoder = CLGeocoder()
    /// Nesil sayacı: yavaş ağda eski MKDirections yanıtı geç dönerse daha YENİ
    /// hesaplamanın üzerine yazmasın — yalnızca en son sonuç uygulanır.
    private var computeGeneration = 0

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

    func update(location: CLLocation?, stops: [Stop], route: RouteStore?) async {
        guard let location, stops.count >= 2 else { return }

        // Kısıtla: yalnızca 700 m'den fazla hareket ya da 45 sn geçmişse yeniden hesapla.
        let now = Date()
        if let last = lastCoord {
            let moved = location.distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
            if moved < 700, now.timeIntervalSince(lastComputeAt) < 45 { return }
        }
        lastCoord = location.coordinate
        lastComputeAt = now
        computeGeneration += 1
        let generation = computeGeneration

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

        // 2) Kuş uçuşu yedeğini ÖNCE uygula: MKDirections yavaşsa/başarısızsa bile
        //    en son neslin nextStop + kalan km + ETA'sı birlikte yayınlanmış olur
        //    (yavaş ağda eski nesil beklenirken "açlık" olmaz). Gerçek rota dönünce
        //    aynı blok değerleri günceller.
        let straight = meters(location, to: next)
        commit(next: next, idx: idx, prevIdx: prevIdx, stops: stops, route: route,
               remainingMeters: straight, travelTime: nil, generation: generation)

        // 3) Kalan km + SÜRE — Apple Maps (MKDirections) ile gerçek sürüş.
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: next.coordinate))
        request.transportType = .automobile

        if let driving = try? await MKDirections(request: request).calculate().routes.first {
            commit(next: next, idx: idx, prevIdx: prevIdx, stops: stops, route: route,
                   remainingMeters: driving.distance, travelTime: driving.expectedTravelTime,
                   generation: generation)
        }

        // 5) Anlık şehir (ters coğrafi kodlama, best-effort).
        if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
            guard generation == computeGeneration else { return }
            currentCity = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea
        }
    }

    /// İlerleme değerlerini TEK BLOKTA yayınla: nextStop, kalan km ve ETA her zaman
    /// aynı nesilden gelir; eski neslin geç dönen sonucu hiçbir alanı ezmez.
    private func commit(next: Stop, idx: Int, prevIdx: Int, stops: [Stop],
                        route: RouteStore?, remainingMeters: Double,
                        travelTime: TimeInterval?, generation: Int) {
        guard generation == computeGeneration else { return }   // daha yeni hesaplama başladı
        nextStop = next
        currentLegIndex = prevIdx
        remainingKm = Int((remainingMeters / 1000).rounded())
        if let travelTime {
            remainingMinutes = Int((travelTime / 60).rounded())
        } else {
            // ~80 km/s tahmini; kısa mesafede "0 dk" görünmesin → en az 1 dk.
            remainingMinutes = max(1, Int((remainingMeters / 1000) / 80 * 60))
        }

        // 2b) Riga'ya kalan: sıradaki durağa sürüş + aradaki etapların rota mesafeleri.
        // Etap bilgisi yoksa kuş uçuşu × 1.25 (Avrupa karayolu sapma payı) ile tahmin edilir.
        var toFinal = remainingMeters
        if idx < stops.count - 1 {
            for k in idx ..< (stops.count - 1) {
                if let info = route?.legInfo(k) {
                    toFinal += info.distance
                } else {
                    let straight = CLLocation(latitude: stops[k].lat, longitude: stops[k].lng)
                        .distance(from: CLLocation(latitude: stops[k + 1].lat, longitude: stops[k + 1].lng))
                    toFinal += straight * 1.25
                }
            }
        }
        remainingToFinalKm = Int((toFinal / 1000).rounded())

        // 3) Gidilen yol + ilerleme (etabın toplamından).
        let legTotal: Double
        if let info = route?.legInfo(prevIdx) {
            legTotal = info.distance
        } else {
            legTotal = CLLocation(latitude: stops[prevIdx].lat, longitude: stops[prevIdx].lng)
                .distance(from: CLLocation(latitude: next.lat, longitude: next.lng))
        }
        let traveled = max(0, legTotal - remainingMeters)
        traveledKm = Int((traveled / 1000).rounded())
        legProgress = legTotal > 0 ? min(1, max(0, traveled / legTotal)) : 0

        // 4) Zincirleme varış tahminleri: sıradaki durak → Riga (kalan süre + sonraki etaplar).
        var arr: [StopArrival] = []
        let base = Date()
        var cum = TimeInterval((remainingMinutes ?? 0) * 60)
        for k in idx ..< stops.count {
            if k > idx {
                if let info = route?.legInfo(k - 1) {
                    cum += info.time
                } else {
                    let d = CLLocation(latitude: stops[k - 1].lat, longitude: stops[k - 1].lng)
                        .distance(from: CLLocation(latitude: stops[k].lat, longitude: stops[k].lng))
                    cum += d / (80_000.0 / 3600.0)
                }
            }
            let s = stops[k]
            arr.append(StopArrival(id: s.id, name: s.name, code: s.code, eta: base.addingTimeInterval(cum)))
        }
        arrivals = arr
    }

    var remainingTimeText: String {
        guard let m = remainingMinutes else { return "—" }
        if m >= 60 { return "\(m / 60) sa \(m % 60) dk" }
        return "\(m) dk"
    }
}
