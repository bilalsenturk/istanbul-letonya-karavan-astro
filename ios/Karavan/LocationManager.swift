import Foundation
import CoreLocation

// Canlı konum: cihazın kendi GPS'i. Riga'ya kalan mesafe, hız, sıradaki durak
// cihazda hesaplanır; istenirse web'e de yayınlanır (bkz. publishToWeb).
@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var status: CLAuthorizationStatus = .notDetermined
    @Published var lastPublished: Date?
    @Published var publishEnabled = true
    @Published var powerSaving = false     // termal/düşük güçte GPS kısıldı mı

    // Web'e zengin canlı durum göndermek için (şehir, sıradaki hedef, kalan km/süre…)
    weak var nav: NavProgressStore?
    weak var trip: TripStore?
    weak var routeStore: RouteStore?

    private let manager = CLLocationManager()
    private var lastPostAt: Date = .distantPast
    private var monitoredStops: [Stop] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        applyPowerMode()
        NotificationCenter.default.addObserver(self, selector: #selector(powerChanged),
                                               name: .NSProcessInfoPowerStateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(powerChanged),
                                               name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
    }

    // MARK: - Termal / batarya uyumlu GPS
    // Telefon ısınınca, Düşük Güç modunda veya kritik ısıda GPS hassasiyetini kısar;
    // canlı paylaşımın kampa kadar dayanmasını sağlar.
    @objc private nonisolated func powerChanged() {
        Task { @MainActor in self.applyPowerMode() }
    }

    func applyPowerMode() {
        let info = ProcessInfo.processInfo
        let saving = info.isLowPowerModeEnabled
            || info.thermalState == .serious
            || info.thermalState == .critical
        powerSaving = saving
        manager.desiredAccuracy = saving ? kCLLocationAccuracyHundredMeters : kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = saving ? 400 : 100
    }

    func request() {
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()   // arka planda varış bildirimi için
        default:
            manager.startUpdatingLocation()
        }
    }

    /// Varış geofence'i: her durağın çevresinde çember; girince bildirim (app kapalıyken de).
    func startMonitoringStops(_ stops: [Stop]) {
        monitoredStops = stops
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        for region in manager.monitoredRegions { manager.stopMonitoring(for: region) }
        for stop in stops.prefix(20) {
            let region = CLCircularRegion(center: stop.coordinate, radius: 3000, identifier: stop.name)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            self.status = s
            if s == .authorizedWhenInUse || s == .authorizedAlways {
                self.manager.startUpdatingLocation()
                if !self.monitoredStops.isEmpty {
                    self.startMonitoringStops(self.monitoredStops)
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor in
            NotificationManager.shared.notify(
                title: "\(region.identifier) · vardınız!",
                body: "Kontrol: tüp gaz kapalı mı · elektrik/su · sınır belgeleri hazır mı?",
                id: "arrival-\(region.identifier)"
            )
            var rigaKm: Int?
            if let riga = self.trip?.trip?.stops.last, let km = self.distanceKm(to: riga) {
                rigaKm = Int(km.rounded())
            }
            AnnouncementService.shared.announceArrival(stopName: region.identifier, remainingToFinalKm: rigaKm)
            LiveActivityManager.shared.endCurrent()   // etap bitti → kilit ekranı kartını kapat
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in
            self.location = last
            // Konum geldikçe ilerlemeyi güncelle (view zamanlamasına bağlı kalmadan),
            // sonra web'e zengin durumu yayınla.
            if let stops = self.trip?.trip?.stops, stops.count >= 2 {
                await self.nav?.update(location: last, stops: stops, route: self.routeStore)
            }
            self.publishToWeb(last)
            // Her ~100 km / yaklaşınca sesli mesafe anonsu
            if let name = self.nav?.nextStop?.name, let km = self.nav?.remainingKm {
                AnnouncementService.shared.progressUpdate(nextStop: name, remainingKm: km)
            }
            self.updateSharedAndActivity()
            self.checkRouteDeviation(last)
        }
    }

    // MARK: - Rota-sapma uyarısı (SOS)
    // Plandaki yoldan 5+ km sapmış halde sürüş, 3 ardışık ölçümde teyit edilirse bildir.
    private var deviationStreak = 0
    private var lastDeviationAlert: Date = .distantPast

    private func checkRouteDeviation(_ current: CLLocation) {
        guard let legIdx = nav?.currentLegIndex,
              let coordsList = routeStore?.displayCoords,
              coordsList.indices.contains(legIdx),
              (speedKmh ?? 0) > 20
        else { deviationStreak = 0; return }

        let legCoords = coordsList[legIdx]
        guard legCoords.count > 1 else { return }
        var minDist = Double.infinity
        for c in stride(from: 0, to: legCoords.count, by: 4) {
            let d = current.distance(from: CLLocation(latitude: legCoords[c].latitude, longitude: legCoords[c].longitude))
            if d < minDist { minDist = d }
            if minDist < 5000 { break }
        }

        if minDist >= 5000 {
            deviationStreak += 1
            if deviationStreak >= 3, Date().timeIntervalSince(lastDeviationAlert) > 900 {
                lastDeviationAlert = Date()
                AnnouncementService.shared.say(AnnouncementCatalog.deviation)
                NotificationManager.shared.notify(
                    title: "Rotadan saptın",
                    body: "Planlanan yoldan \(Int(minDist / 1000)) km uzaktasın. Bilerek mi? Araçlar'dan konumunu paylaşabilirsin.",
                    id: "route-deviation"
                )
            }
        } else {
            deviationStreak = 0
        }
    }

    /// Widget + Live Activity beslemesi: App Group snapshot'ı yaz, sürüşteyse aktiviteyi güncelle.
    private func updateSharedAndActivity() {
        guard let nav else { return }
        var values: [String: Any] = [:]
        if let city = nav.currentCity { values[SharedSnapshot.Key.currentCity] = city }
        if let next = nav.nextStop {
            values[SharedSnapshot.Key.nextStop] = next.name
            values[SharedSnapshot.Key.nextCode] = next.code
        }
        if let km = nav.remainingKm { values[SharedSnapshot.Key.remainingKm] = km }
        if let m = nav.remainingMinutes { values[SharedSnapshot.Key.remainingMin] = m }
        values[SharedSnapshot.Key.legProgress] = Int((nav.legProgress * 100).rounded())
        SharedSnapshot.write(values)
        LiveActivityManager.shared.reloadWidgetsThrottled()

        // Sürüş algısı: 25 km/s üstü → Live Activity başlat/güncelle
        if let next = nav.nextStop, let km = nav.remainingKm, let m = nav.remainingMinutes {
            let speed = speedKmh ?? 0
            if speed > 25 || LiveActivityManager.shared.isActive {
                LiveActivityManager.shared.startOrUpdate(
                    nextStop: next.name, nextCode: next.code,
                    remainingKm: km, remainingMin: m,
                    speedKmh: speed, progress: nav.legProgress
                )
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    // MARK: - Ölçümler

    /// km/s cinsinden anlık hız (GPS'ten)
    var speedKmh: Int? {
        guard let s = location?.speed, s >= 0 else { return nil }
        return Int((s * 3.6).rounded())
    }

    func distanceKm(to stop: Stop) -> Double? {
        guard let location else { return nil }
        return location.distance(from: CLLocation(latitude: stop.lat, longitude: stop.lng)) / 1000
    }

    func nearestStop(in stops: [Stop]) -> (stop: Stop, km: Double)? {
        guard location != nil else { return nil }
        var best: (Stop, Double)?
        for stop in stops {
            if let d = distanceKm(to: stop), d < (best?.1 ?? .infinity) {
                best = (stop, d)
            }
        }
        return best
    }

    // MARK: - Web'e yayın

    /// Konumu siteye gönderir (en fazla 60 sn'de bir). Site yoksa sessizce geçer.
    private func publishToWeb(_ loc: CLLocation) {
        guard publishEnabled,
              let url = Config.livePostURL,
              Date().timeIntervalSince(lastPostAt) > 30
        else { return }
        lastPostAt = Date()

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Config.livePostSecret, forHTTPHeaderField: "x-live-secret")
        req.timeoutInterval = 10

        var payload: [String: Any] = [
            "lat": loc.coordinate.latitude,
            "lng": loc.coordinate.longitude,
            "speedKmh": max(0, Int((loc.speed * 3.6).rounded())),
            "ts": ISO8601DateFormatter().string(from: loc.timestamp),
        ]
        // App'in canlı durumunu web'e birebir yansıt (dinamik site).
        if let nav {
            if let city = nav.currentCity { payload["city"] = city }
            if let next = nav.nextStop {
                payload["nextStop"] = next.name
                payload["nextFlag"] = next.flag
            }
            if let km = nav.remainingKm { payload["remainingKm"] = km }
            if let minutes = nav.remainingMinutes { payload["remainingMin"] = minutes }
            if let traveled = nav.traveledKm { payload["traveledKm"] = traveled }
            payload["legProgress"] = Int((nav.legProgress * 100).rounded())
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        Task {
            guard let (_, response) = try? await URLSession.shared.data(for: req),
                  let http = response as? HTTPURLResponse, http.statusCode == 200
            else { return }
            await MainActor.run { self.lastPublished = Date() }
        }
    }
}
