import Foundation
import CoreLocation
import UIKit

// Canlı konum: cihazın kendi GPS'i. Riga'ya kalan mesafe, hız, sıradaki durak
// cihazda hesaplanır; istenirse web'e de yayınlanır (bkz. publishToWeb).
@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var status: CLAuthorizationStatus = .notDetermined
    @Published var lastPublished: Date?
    @Published var publishEnabled = true
    @Published var powerSaving = false     // termal/düşük güçte GPS kısıldı mı
    var publishedTripScope: PublishedTripScope?

    // Web'e zengin canlı durum göndermek için (şehir, sıradaki hedef, kalan km/süre…)
    weak var nav: NavProgressStore?
    weak var trip: TripStore?
    weak var routeStore: RouteStore?
    weak var altimeter: AltimeterService?

    private let manager = CLLocationManager()
    private var lastPostAt: Date = .distantPast
    private var monitoredStops: [Stop] = []
    /// UI'siz arka plan uyanışında (SLOC/geofence) nav/trip yedeği — weak
    /// referanslar view .task'ından gelir; orası çalışmadıysa bunlar devreye girer.
    private var backgroundNav: NavProgressStore?
    private var backgroundTrip: TripStore?

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        // Arka plan teslimatı: uygulama arkadayken/ekran kapalıyken de sürüş
        // güncellemeleri gelsin (varış yaklaşımı, sürüş molası, pil uyarıları).
        // Always izni yoksa sistem bu bayrağı yok sayar. Otomatik duraklatma
        // kapalı: sürüş uygulamasında akışın kesilmesi bildirim hattını öldürür.
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
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
    /// Bölge kimliği olarak durağın KARARLI id'si kullanılır — web verisinde durak
    /// yeniden adlandırılsa bile eşleşme bozulmaz.
    func startMonitoringStops(_ stops: [Stop]) {
        monitoredStops = stops
        monitoredKey = Self.stopsKey(stops)
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        for region in manager.monitoredRegions { manager.stopMonitoring(for: region) }
        for stop in stops.prefix(20) {
            let region = CLCircularRegion(center: stop.coordinate, radius: 3000, identifier: stop.id)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }
    }

    private var monitoredKey = ""

    private static func stopsKey(_ stops: [Stop]) -> String {
        stops.map { "\($0.id):\($0.name):\($0.lat),\($0.lng)" }.joined(separator: "|")
    }

    /// Web yolculuk verisi yenilenip duraklar değişince KaravanApp çağırır —
    /// çemberler güncel listeyle yeniden kaydedilir. Liste aynıysa hiçbir şey yapmaz.
    func refreshMonitoredStops(_ stops: [Stop]) {
        guard Self.stopsKey(stops) != monitoredKey else { return }
        startMonitoringStops(stops)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            self.status = s
            if s == .authorizedWhenInUse {
                // Geofence/SLOC ile app KAPALIYKEN uyanmak Always ister — WhenInUse
                // verilir verilmez yükselt. Yalnızca bir kez dene: reddedildiyse
                // her açılışta yeniden sormak iOS'ta sessizce yutulur ama temiz olsun.
                let askedKey = "alwaysUpgradeRequested"
                if !UserDefaults.standard.bool(forKey: askedKey) {
                    UserDefaults.standard.set(true, forKey: askedKey)
                    self.manager.requestAlwaysAuthorization()
                }
            }
            if s == .authorizedWhenInUse || s == .authorizedAlways {
                self.manager.startUpdatingLocation()
                if !self.monitoredStops.isEmpty {
                    self.startMonitoringStops(self.monitoredStops)
                }
            }
            if s == .authorizedAlways {
                // Önemli konum değişimi: uygulama tamamen kapalıyken bile sistemi
                // uyandırıp süreci başlatır; neredeyse bedava (hücre bazlı). Arka
                // planda yağmur/sınır kontrollerinin ana uyanma kanalı.
                self.manager.startMonitoringSignificantLocationChanges()
            }
        }
    }

    /// Durak başına son varış bildirimi — tüm varış hattı (bildirim + anons +
    /// Live Activity kapanışı) yaklaşım başına YALNIZCA BİR KEZ çalışır.
    private var lastArrivalAt: [String: Date] = [:]
    /// Az önce varılan durak — nav ilerleyene kadar Live Activity yeniden başlatılmaz.
    private var arrivedStopId: String?

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        // Şehir merkezi geofence'i rota varışı değildir. Kesin hedef varışı,
        // didUpdateLocations içinde hedef koordinatı ve GPS doğruluğuyla ölçülür.
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in
            self.location = last
            let arrivedStopId = RouteSession.shared.activeStopId
            let arrivedTargetName = RouteSession.shared.activeTargetName
            if RouteSession.shared.finishIfArrived(location: last),
               let arrivedStopId,
               let stop = (self.trip?.trip?.stops ?? TripStore.bundledTrip()?.stops ?? [])
                .first(where: { $0.id == arrivedStopId }) {
                self.arrivedStopId = stop.id
                NotificationManager.shared.notify(
                    title: "\(arrivedTargetName ?? stop.name) · vardınız!",
                    body: "Konaklama ve araç kontrollerini tamamlayın.",
                    id: "arrival-\(stop.id)"
                )
                AnnouncementService.shared.announceArrival(
                    stopName: arrivedTargetName ?? stop.name,
                    remainingToFinalKm: self.nav?.remainingToFinalKm
                )
                LiveActivityManager.shared.endCurrent()
            }
            // UI'siz arka plan uyanışı (SLOC/geofence): nav/trip view .task'ından
            // bağlanır; orası çalışmadıysa gömülü gezi verisiyle yedek depo kur
            // ki bildirim hattı (nav, TripNotifier) ölü kalmasın.
            if self.nav == nil || self.trip == nil {
                if self.backgroundTrip == nil { self.backgroundTrip = TripStore() }
                if self.backgroundNav == nil { self.backgroundNav = NavProgressStore() }
                self.trip = self.trip ?? self.backgroundTrip
                self.nav = self.nav ?? self.backgroundNav
            }
            // Konum geldikçe ilerlemeyi güncelle (view zamanlamasına bağlı kalmadan),
            // sonra web'e zengin durumu yayınla.
            if let stops = self.trip?.trip?.stops, stops.count >= 2 {
                await self.nav?.update(location: last, stops: stops, route: self.routeStore)
            }
            await MainActor.run {
                let routeStarted = RouteSession.shared.isActive
                let routeProgressAllowed = RouteAnnouncementPolicy.allowsRouteProgressAnnouncement(
                    routeStarted: routeStarted,
                    activeStopId: RouteSession.shared.activeStopId,
                    nextStopId: self.nav?.nextStop?.id
                )
                TripNotifier.shared.onLocation(
                    remainingKm: routeProgressAllowed ? self.nav?.remainingKm : nil,
                    nextStopName: routeProgressAllowed ? self.nav?.nextStop?.name : nil,
                    speedKmh: self.speedKmh,
                    currentCountry: self.currentStop()?.country,
                    nextCountry: self.nav?.nextStop?.country,
                    currentCode: self.currentStop()?.code,
                    nextCountryCode: self.nav?.nextStop?.code,
                    routeStarted: routeStarted
                )
                // "nextStop != nil" sekiz günlük yolculuğun neredeyse tamamında doğrudur
                // (mola/kamp/gece dahil) — gerçek "navigasyondayım" sinyali değil.
                // LiveActivityManager.shared.isActive, hız eşiğine (25 km/s) dayanan
                // gerçek sürüş durumunu yansıtır; düşük pil uyarısını bu sinyale bağla.
                TripNotifier.shared.checkBattery(navigating: LiveActivityManager.shared.isActive)
            }
            self.publishToWeb(last)
            // Her ~100 km / yaklaşınca sesli mesafe anonsu
            if RouteAnnouncementPolicy.allowsRouteProgressAnnouncement(
                routeStarted: RouteSession.shared.isActive,
                activeStopId: RouteSession.shared.activeStopId,
                nextStopId: self.nav?.nextStop?.id
            ), let name = self.nav?.nextStop?.name, let km = self.nav?.remainingKm {
                AnnouncementService.shared.progressUpdate(nextStop: name, remainingKm: km)
            }
            self.updateSharedAndActivity()
            self.checkRouteDeviation(last)
            // Arka plandayken (SLOC/geofence uyanışı) hava kontrolünü buradan
            // yürüt: view .task'ı UI'siz çalışmaz. refreshIfStale'in 45 dk
            // eşiği sayesinde sık konum güncellemesi maliyetsizdir.
            if UIApplication.shared.applicationState != .active {
                await BackgroundWeather.refreshIfStale()
            }
        }
    }

    // MARK: - Rota-sapma uyarısı (SOS)
    // Plandaki yoldan 5+ km sapmış halde sürüş, 3 ardışık ölçümde teyit edilirse bildir.
    private var deviationStreak = 0
    private var lastDeviationAlert: Date = .distantPast

    private func checkRouteDeviation(_ current: CLLocation) {
        guard let legIdx = nav?.currentLegIndex,
              let coordsList = routeStore?.displayCoords,
              coordsList.indices.contains(legIdx)
        else { deviationStreak = 0; return }

        let legCoords = coordsList[legIdx]
        guard RouteAnnouncementPolicy.allowsDeviationAnnouncement(
            routeStarted: RouteSession.shared.isActive,
            activeStopId: RouteSession.shared.activeStopId,
            nextStopId: nav?.nextStop?.id,
            currentLegIndex: legIdx,
            speedKmh: speedKmh,
            hasLegGeometry: legCoords.count > 1
        ) else { deviationStreak = 0; return }

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
                AnnouncementService.shared.announce(AnnouncementCatalog.Category.deviation)
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
        let routeStarted = RouteSession.shared.isActive
        var values: [String: Any] = [:]
        if let city = nav.currentCity { values[SharedSnapshot.Key.currentCity] = city }
        if let next = nav.nextStop {
            values[SharedSnapshot.Key.nextStop] = next.name
            values[SharedSnapshot.Key.nextCode] = next.code
        }
        if let km = nav.remainingKm { values[SharedSnapshot.Key.remainingKm] = km }
        if let m = nav.remainingMinutes { values[SharedSnapshot.Key.remainingMin] = m }
        values[SharedSnapshot.Key.legProgress] = routeStarted ? Int((nav.legProgress * 100).rounded()) : 0
        SharedSnapshot.write(values)
        RouteSession.shared.writeSnapshot()
        LiveActivityManager.shared.reloadWidgetsThrottled()

        // Live Activity yalnız kullanıcı Rotalar > Buraya git ile başlattıysa güncellenir.
        guard routeStarted else {
            if LiveActivityManager.shared.isActive {
                LiveActivityManager.shared.endCurrent()
            }
            return
        }

        if let next = nav.nextStop, let km = nav.remainingKm, let m = nav.remainingMinutes {
            // Varıştan hemen sonra nav henüz ilerlemediyse (nextStop hâlâ varılan
            // durak) yeni kart AÇMA — durak değişinceye kadar bekle.
            if arrivedStopId == next.id {
                // varış kartı zaten kapatıldı; nav'in ilerlemesi bekleniyor
            } else {
                arrivedStopId = nil
                let metrics = RouteStartMetrics(remainingKm: km, remainingMinutes: m)
                if RouteSession.shared.activeStopId == next.id,
                   let payload = metrics.liveActivityPayload {
                    LiveActivityManager.shared.startOrUpdate(
                        nextStop: next.name, nextCode: next.code,
                        remainingKm: payload.remainingKm,
                        remainingMin: payload.remainingMin,
                        speedKmh: speedKmh ?? 0,
                        progress: nav.legProgress
                    )
                }
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

    /// Bulunduğun etabın BAŞLANGIÇ durağı — sınır geçişi ve yakıt karşılaştırması için.
    func currentStop() -> Stop? {
        guard let stops = trip?.trip?.stops, let leg = nav?.currentLegIndex,
              stops.indices.contains(leg) else { return nil }
        return stops[leg]
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
              publishedTripScope != nil,
              Date().timeIntervalSince(lastPostAt) > 60
        else { return }
        lastPostAt = Date()

        let routeStarted = RouteSession.shared.isActive
        var payload: [String: Any] = [
            "lat": loc.coordinate.latitude,
            "lng": loc.coordinate.longitude,
            "speedKmh": max(0, Int((loc.speed * 3.6).rounded())),
            "ts": ISO8601DateFormatter().string(from: loc.timestamp),
            "journeyStarted": routeStarted,
        ]
        if routeStarted {
            if let stop = RouteSession.shared.activeStopName { payload["activeRouteStop"] = stop }
            if let code = RouteSession.shared.activeStopCode { payload["activeRouteCode"] = code }
            if let startedAt = RouteSession.shared.startedAt {
                payload["activeRouteStartedAt"] = ISO8601DateFormatter().string(from: startedAt)
            }
        }
        // App'in canlı durumunu web'e birebir yansıt (dinamik site).
        if let nav {
            if let city = nav.currentCity { payload["city"] = city }
            if let next = nav.nextStop {
                payload["nextStop"] = next.name
                payload["nextFlag"] = next.flag
            }
            if let km = nav.remainingKm { payload["remainingKm"] = km }
            if let km = nav.remainingToFinalKm { payload["remainingToFinalKm"] = km }
            if let minutes = nav.remainingMinutes { payload["remainingMin"] = minutes }
            if routeStarted {
                if let traveled = nav.traveledKm { payload["traveledKm"] = traveled }
                payload["legProgress"] = Int((nav.legProgress * 100).rounded())
            } else {
                payload["traveledKm"] = 0
                payload["legProgress"] = 0
            }
        }
        if let altimeter {
            payload["altitudeAvailable"] = altimeter.available
            if let absolute = altimeter.absoluteAltitude {
                payload["altitudeMeters"] = absolute
                payload["altitudeKind"] = "absolute"
                payload["altitudeSource"] = "barometer"
            } else if let relative = altimeter.relativeAltitude {
                payload["altitudeMeters"] = relative
                payload["altitudeKind"] = "relative"
                payload["altitudeSource"] = "barometer"
            }
            if let pressure = altimeter.pressureHpa {
                payload["pressureHpa"] = (pressure * 10).rounded() / 10
            }
        } else if loc.verticalAccuracy >= 0 {
            payload["altitudeAvailable"] = true
            payload["altitudeMeters"] = loc.altitude
            payload["altitudeKind"] = "absolute"
            payload["altitudeSource"] = "gps"
        }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        PublishOutbox.shared.enqueue(resource: .liveLocation, body: body) { [weak self] in
            self?.lastPublished = Date()
        }
    }
}
