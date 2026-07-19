import Foundation
import CoreLocation

// Canlı konum: sunucu yok, AirTag yok — cihazın kendi GPS'i.
// Riga'ya kalan mesafe, sıradaki durak ve rota ilerlemesi cihazda hesaplanır.
@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var status: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 200
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
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    // MARK: - Hesaplamalar

    func distanceKm(to stop: Stop) -> Double? {
        guard let location else { return nil }
        let target = CLLocation(latitude: stop.lat, longitude: stop.lng)
        return location.distance(from: target) / 1000
    }

    /// En yakın durak (rota üzerinde neredeyiz)
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

    /// Rota ilerlemesi: geçilen durakların oranı (en yakın durağın indeksi üzerinden)
    func progress(in stops: [Stop]) -> Double? {
        guard let nearest = nearestStop(in: stops),
              let idx = stops.firstIndex(where: { $0.id == nearest.stop.id }),
              stops.count > 1
        else { return nil }
        return Double(idx) / Double(stops.count - 1)
    }
}
