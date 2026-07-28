import MapKit

// Bir etabın kalıcı özeti (offline yedek): seyreltilmiş rota noktaları + mesafe + süre.
struct LegSnapshot: Codable {
    let coords: [[Double]]        // [lat, lng] çiftleri (≤ ~400 nokta/etap)
    let distance: Double          // metre
    let time: Double              // saniye
}

// Disk önbelleği zarfı: durak imzası + etaplar. Duraklar değiştiyse eski
// mesafe/ETA'nın sessizce kullanılmasını engeller (imza uyuşmazlığı → yok say).
// Eski formattaki (imzasız) route-cache.json bu yapıya çözülemez → otomatik geçersiz.
private struct RouteCache: Codable {
    let signature: String
    let legs: [LegSnapshot]
}

// Gerçek sürüş rotası: Apple Haritalar (MKDirections). Etaplar POZİSYONEL hizalı:
// legs[i] = stops[i]→stops[i+1] (başarısızsa nil). Tam başarıda diske kaydedilir;
// sinyalsiz sınır bölgelerinde rota diskteki kopyadan çizilir (offline paket).
@MainActor
final class RouteStore: ObservableObject {
    @Published private(set) var legs: [MKRoute?] = []
    @Published private(set) var cached: [LegSnapshot]? = nil
    @Published private(set) var computing = false

    /// Mevcut `legs` dizisinin hesaplandığı durak imzası — yalnızca imza aynıysa
    /// önceki başarılı etaplar yeni hesaplamaya taşınır.
    private var legsFor: String?
    private var computedFor: String?
    private var cachedSignature: String?
    /// Diskten okunan ama imzası henüz doğrulanmamış önbellek — doğrulanmadan servis edilmez.
    private var unvalidated: (signature: String, legs: [LegSnapshot])?

    private static var cacheURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("route-cache.json")
    }

    /// Durak kimliği + koordinatlarından imza — yolculuk değişirse önbellek geçersiz.
    private static func signature(for stops: [Stop]) -> String {
        stops.map { "\($0.id):\($0.lat),\($0.lng)" }.joined(separator: "|")
    }

    init() {
        if let data = try? Data(contentsOf: Self.cacheURL),
           let decoded = try? JSONDecoder().decode(RouteCache.self, from: data) {
            // İmza, durak listesiyle computeIfNeeded'da doğrulanana kadar beklemede —
            // bayat disk önbelleği bu yolculuğa ait değilse hiç servis edilmez.
            unvalidated = (decoded.signature, decoded.legs)
        }
    }

    /// Haritada çizim için etap koordinatları — ETAP HİZALI: sonuç[i] = i. etap
    /// (başarısız etap boş dizi; indeks kayması olmaz). Canlı rota varsa o, yoksa disk kopyası.
    var displayCoords: [[CLLocationCoordinate2D]] {
        if legs.contains(where: { $0 != nil }) {
            return legs.indices.map { i in
                if let route = legs[i] { return Self.decimated(route.polyline) }
                // Tek etap başarısızsa çizimde kalıcı delik olmasın: imza uyuşuyorsa
                // o etabın disk kopyasındaki koordinatlarına düş.
                if legsFor == cachedSignature, let cached, cached.indices.contains(i) {
                    return Self.coords(from: cached[i])
                }
                return []
            }
        }
        return (cached ?? []).map { Self.coords(from: $0) }
    }

    /// Disk kopyasındaki [lat, lng] çiftlerini koordinata çevir — bozuk çift
    /// (2 elemanlı değil) atlanır, çökme olmaz.
    private static func coords(from leg: LegSnapshot) -> [CLLocationCoordinate2D] {
        leg.coords.compactMap { pair in
            guard pair.count == 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
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

    /// Duraklar için gerçek yolu hesapla. Önceki BAŞARILI etaplar korunur; yalnızca
    /// eksik/başarısız etaplar yeniden denenir. Yalnızca TAM başarıda disk güncellenir.
    func computeIfNeeded(stops: [Stop]) async {
        let sig = Self.signature(for: stops)
        // Disk önbelleğini ilk kullanımdan ÖNCE doğrula: imza bu yolculuğa ait
        // değilse bayat rota hiç servis edilmez.
        if let u = unvalidated {
            unvalidated = nil
            if u.signature == sig {
                cached = u.legs
                cachedSignature = u.signature
            }
        }
        // Duraklar değiştiyse diskteki eski rota artık bu yolculuğa ait değil.
        if cachedSignature != nil, cachedSignature != sig {
            cached = nil
            cachedSignature = nil
        }
        // İş gerekli mi? Yalnızca id değil İMZA karşılaştırılır: koordinatı değişen
        // durak (id aynı kalsa bile) yeniden hesabı tetikler. İmza aynı ama bazı
        // etaplar eksikse yalnızca o etaplar yeniden denenir (tam kaskad değil).
        let hasMissing = legsFor != sig || legs.count != stops.count - 1 || legs.contains(where: { $0 == nil })
        guard stops.count >= 2, !computing, sig != computedFor || hasMissing else { return }
        computing = true
        defer { computing = false }

        // Aynı imzaysa önceki başarılı etapları taşı — kısmi başarısızlıkta iyi
        // çizgiler silinmez; yalnızca eksik etaplar MKDirections'a gider.
        var built = [MKRoute?](repeating: nil, count: stops.count - 1)
        if legsFor == sig {
            for i in built.indices where legs.indices.contains(i) { built[i] = legs[i] }
        }
        legs = built
        legsFor = sig
        var anySucceeded = built.contains(where: { $0 != nil })
        for i in 0 ..< (stops.count - 1) where built[i] == nil {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: stops[i].coordinate))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: stops[i + 1].coordinate))
            request.transportType = .automobile
            if let response = try? await MKDirections(request: request).calculate(),
               let route = response.routes.first {
                built[i] = route
                legs = built            // artan çizim (yol yol belirir)
                anySucceeded = true
            }
        }
        if anySucceeded {
            // Kısmi başarıda bile işaretle: .task her seferinde TAM MKDirections
            // kaskadını ateşlemez; eksik etaplar sonraki çağrılarda tek tek denenir.
            computedFor = sig
        }
        if built.allSatisfy({ $0 != nil }) {
            persist(built.compactMap { $0 }, signature: sig)
        }
    }

    private func persist(_ routes: [MKRoute], signature: String) {
        let snapshots = routes.map { route in
            LegSnapshot(
                coords: Self.decimated(route.polyline).map { [$0.latitude, $0.longitude] },
                distance: route.distance,
                time: route.expectedTravelTime
            )
        }
        cached = snapshots
        cachedSignature = signature
        let cache = RouteCache(signature: signature, legs: snapshots)
        if let data = try? JSONEncoder().encode(cache) {
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

    /// Haritada yeşil çizilecek bölüm: yalnızca kullanıcı Rotalar > Buraya git ile
    /// rota başlattıysa ve mevcut etap ilerlediyse döner. Gidilmemiş rota nötr kalır.
    func traveledDisplayCoords(stops: [Stop],
                               routeStarted: Bool,
                               activeStopId: String?,
                               currentLegIndex: Int?,
                               legProgress: Double) -> [[CLLocationCoordinate2D]] {
        guard routeStarted, stops.count >= 2 else { return [] }

        let targetLegIndex: Int? = activeStopId
            .flatMap { id in stops.firstIndex(where: { $0.id == id }) }
            .map { max(0, $0 - 1) }
        let current = currentLegIndex ?? targetLegIndex
        guard let current else { return [] }
        let activeLeg = min(max(0, current), targetLegIndex ?? current, stops.count - 2)
        let progress = Self.normalizedProgress(legProgress)

        let legs = displayCoords
        var traveled: [[CLLocationCoordinate2D]] = []

        for index in 0 ..< activeLeg {
            let coords = coordsForLeg(index, stops: stops, displayCoords: legs)
            if coords.count > 1 { traveled.append(coords) }
        }

        let currentCoords = coordsForLeg(activeLeg, stops: stops, displayCoords: legs)
        let partial = Self.prefix(currentCoords, progress: progress)
        if partial.count > 1 { traveled.append(partial) }
        return traveled
    }

    private func coordsForLeg(_ index: Int, stops: [Stop], displayCoords: [[CLLocationCoordinate2D]]) -> [CLLocationCoordinate2D] {
        if displayCoords.indices.contains(index), displayCoords[index].count > 1 {
            return displayCoords[index]
        }
        guard stops.indices.contains(index), stops.indices.contains(index + 1) else { return [] }
        return [stops[index].coordinate, stops[index + 1].coordinate]
    }

    private static func normalizedProgress(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let normalized = value > 1 ? value / 100 : value
        return min(1, max(0, normalized))
    }

    private static func prefix(_ coords: [CLLocationCoordinate2D], progress: Double) -> [CLLocationCoordinate2D] {
        guard coords.count > 1, progress > 0 else { return [] }
        if progress >= 1 { return coords }

        let distances = coords.indices.dropFirst().map { index in
            CLLocation(latitude: coords[index - 1].latitude, longitude: coords[index - 1].longitude)
                .distance(from: CLLocation(latitude: coords[index].latitude, longitude: coords[index].longitude))
        }
        let total = distances.reduce(0, +)
        guard total > 0 else { return Array(coords.prefix(2)) }

        let target = total * progress
        var covered = 0.0
        var out = [coords[0]]

        for index in 1 ..< coords.count {
            let segment = distances[index - 1]
            if covered + segment < target {
                out.append(coords[index])
                covered += segment
                continue
            }

            let ratio = segment > 0 ? (target - covered) / segment : 0
            let previous = coords[index - 1]
            let next = coords[index]
            out.append(CLLocationCoordinate2D(
                latitude: previous.latitude + (next.latitude - previous.latitude) * ratio,
                longitude: previous.longitude + (next.longitude - previous.longitude) * ratio
            ))
            break
        }
        return out.count > 1 ? out : []
    }
}
