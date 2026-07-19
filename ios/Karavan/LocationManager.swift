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

    private let manager = CLLocationManager()
    private var lastPostAt: Date = .distantPast

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 100
        manager.activityType = .automotiveNavigation
    }

    func request() {
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            manager.startUpdatingLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            self.status = s
            if s == .authorizedWhenInUse || s == .authorizedAlways {
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in
            self.location = last
            self.publishToWeb(last)
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
              Date().timeIntervalSince(lastPostAt) > 60
        else { return }
        lastPostAt = Date()

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Config.livePostSecret, forHTTPHeaderField: "x-live-secret")
        req.timeoutInterval = 10

        let payload: [String: Any] = [
            "lat": loc.coordinate.latitude,
            "lng": loc.coordinate.longitude,
            "speedKmh": max(0, Int((loc.speed * 3.6).rounded())),
            "ts": ISO8601DateFormatter().string(from: loc.timestamp),
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        Task {
            guard let (_, response) = try? await URLSession.shared.data(for: req),
                  let http = response as? HTTPURLResponse, http.statusCode == 200
            else { return }
            await MainActor.run { self.lastPublished = Date() }
        }
    }
}
