import Foundation
import MapKit
import CoreLocation
import Combine
import WidgetKit

@MainActor
final class RouteSession: ObservableObject {
    static let shared = RouteSession()

    @Published private(set) var activeStopId: String?
    @Published private(set) var activeStopName: String?
    @Published private(set) var activeStopCode: String?
    @Published private(set) var activeTargetId: String?
    @Published private(set) var activeTargetName: String?
    @Published private(set) var activeTargetLatitude: Double?
    @Published private(set) var activeTargetLongitude: Double?
    @Published private(set) var startedAt: Date?
    @Published private(set) var completedStopIds: Set<String> = []

    private let defaults = UserDefaults.standard
    private let idKey = "active-route-stop-id"
    private let nameKey = "active-route-stop-name"
    private let codeKey = "active-route-stop-code"
    private let targetIdKey = "active-route-target-id"
    private let targetNameKey = "active-route-target-name"
    private let targetLatitudeKey = "active-route-target-latitude"
    private let targetLongitudeKey = "active-route-target-longitude"
    private let startedKey = "active-route-started-at"
    private let completedKey = "completed-route-stop-ids"
    private let maxAge: TimeInterval = 18 * 3600

    var isActive: Bool {
        guard let startedAt else { return false }
        return Date().timeIntervalSince(startedAt) <= maxAge
            && activeStopId != nil && activeTargetId != nil && activeTargetCoordinate != nil
    }

    var activeTargetCoordinate: CLLocationCoordinate2D? {
        guard let latitude = activeTargetLatitude, let longitude = activeTargetLongitude,
              abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private init() {
        completedStopIds = Set(defaults.stringArray(forKey: completedKey) ?? [])
        let started = defaults.object(forKey: startedKey) as? Date
        if let started, Date().timeIntervalSince(started) <= maxAge {
            activeStopId = defaults.string(forKey: idKey)
            activeStopName = defaults.string(forKey: nameKey)
            activeStopCode = defaults.string(forKey: codeKey)
            activeTargetId = defaults.string(forKey: targetIdKey)
            activeTargetName = defaults.string(forKey: targetNameKey)
            activeTargetLatitude = defaults.object(forKey: targetLatitudeKey) as? Double
            activeTargetLongitude = defaults.object(forKey: targetLongitudeKey) as? Double
            startedAt = started
            if !isActive { clearActive() }
        } else {
            clearActive()
        }
    }

    func state(for stop: Stop, stops: [Stop]) -> RouteStepState {
        RouteStepPolicy.state(
            for: stop.id,
            orderedStopIds: stops.map(\.id),
            completedStopIds: completedStopIds,
            activeStopId: isActive ? activeStopId : nil
        )
    }

    func nextStartableStopId(stops: [Stop]) -> String? {
        RouteStepPolicy.nextStartableStopId(
            orderedStopIds: stops.map(\.id),
            completedStopIds: completedStopIds
        )
    }

    func canStart(stop: Stop, stops: [Stop]) -> Bool {
        RouteStepPolicy.isStartable(
            stopId: stop.id,
            orderedStopIds: stops.map(\.id),
            completedStopIds: completedStopIds,
            activeStopId: isActive ? activeStopId : nil
        )
    }

    @discardableResult
    func start(stop: Stop, target: ArrivalTarget, stops: [Stop]) -> Bool {
        guard canStart(stop: stop, stops: stops), target.hasValidCoordinate else { return false }
        activeStopId = stop.id
        activeStopName = stop.name
        activeStopCode = stop.code
        activeTargetId = target.id
        activeTargetName = target.name
        activeTargetLatitude = target.latitude
        activeTargetLongitude = target.longitude
        startedAt = Date()
        persist()
        writeSnapshot()
        return true
    }

    @discardableResult
    func finishIfArrived(location: CLLocation) -> Bool {
        guard isActive, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100,
              let stopId = activeStopId, let coordinate = activeTargetCoordinate else { return false }
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard location.distance(from: target) <= 250 else { return false }
        completedStopIds.insert(stopId)
        persistCompleted()
        clearActive()
        return true
    }

    func clear() {
        clearActive()
    }

    func resetProgress() {
        completedStopIds = []
        persistCompleted()
        clearActive()
    }

    func reconcile(stops: [Stop]) {
        let validIds = Set(stops.map(\.id))
        let cleaned = completedStopIds.intersection(validIds)
        if cleaned != completedStopIds {
            completedStopIds = cleaned
            persistCompleted()
        }
        if let activeStopId, !validIds.contains(activeStopId) {
            clearActive()
        }
    }

    private func clearActive() {
        activeStopId = nil
        activeStopName = nil
        activeStopCode = nil
        activeTargetId = nil
        activeTargetName = nil
        activeTargetLatitude = nil
        activeTargetLongitude = nil
        startedAt = nil
        defaults.removeObject(forKey: idKey)
        defaults.removeObject(forKey: nameKey)
        defaults.removeObject(forKey: codeKey)
        defaults.removeObject(forKey: targetIdKey)
        defaults.removeObject(forKey: targetNameKey)
        defaults.removeObject(forKey: targetLatitudeKey)
        defaults.removeObject(forKey: targetLongitudeKey)
        defaults.removeObject(forKey: startedKey)
        writeSnapshot()
    }

    private func persist() {
        defaults.set(activeStopId, forKey: idKey)
        defaults.set(activeStopName, forKey: nameKey)
        defaults.set(activeStopCode, forKey: codeKey)
        defaults.set(activeTargetId, forKey: targetIdKey)
        defaults.set(activeTargetName, forKey: targetNameKey)
        defaults.set(activeTargetLatitude, forKey: targetLatitudeKey)
        defaults.set(activeTargetLongitude, forKey: targetLongitudeKey)
        defaults.set(startedAt, forKey: startedKey)
        persistCompleted()
    }

    private func persistCompleted() {
        defaults.set(Array(completedStopIds), forKey: completedKey)
    }

    func writeSnapshot() {
        var values: [String: Any] = [:]
        if isActive, let activeTargetName, let activeStopCode, let startedAt {
            values[SharedSnapshot.Key.activeRouteStop] = activeTargetName
            values[SharedSnapshot.Key.activeRouteCode] = activeStopCode
            values[SharedSnapshot.Key.activeRouteStartedAt] = startedAt.timeIntervalSince1970
        } else {
            SharedSnapshot.defaults?.removeObject(forKey: SharedSnapshot.Key.activeRouteStop)
            SharedSnapshot.defaults?.removeObject(forKey: SharedSnapshot.Key.activeRouteCode)
            SharedSnapshot.defaults?.removeObject(forKey: SharedSnapshot.Key.activeRouteStartedAt)
        }
        SharedSnapshot.write(values)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// "Sonraki rotayı başlat" — tek yerden: kaptan anonsu + kilit ekranı kartı (Live
// Activity) + Apple Haritalar'da sürüş. Hem haritadaki düğme hem kalkış saati
// modalı burayı çağırır ki davranış her yerde aynı olsun.
@MainActor
enum LegLauncher {
    /// Etabı başlat. `openMaps: false` ise yalnızca anons + Live Activity başlar
    /// (kullanıcı navigasyonu kendi açmak isterse).
    @discardableResult
    static func start(stop: Stop, target: ArrivalTarget, stops: [Stop], nav: NavProgressStore, location: CLLocation?,
                      speedKmh: Int?, openMaps: Bool = true) async -> Bool {
        // Navigasyonu yalnızca SÜRÜCÜ başlatır — tek kontrol noktası: mevcut ve
        // gelecekteki tüm çağıranlar (harita düğmesi, kalkış modalı, …) buradan geçer.
        guard RoleStore.shared.isDriver else { return false }
        guard let location, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 500 else { return false }
        guard RouteSession.shared.start(stop: stop, target: target, stops: stops) else { return false }

        AnnouncementService.shared.announceDeparture(nextStop: target.name)

        let metrics = await metricsForStart(stop: stop, target: target, nav: nav, location: location)
        if let payload = metrics.liveActivityPayload {
            LiveActivityManager.shared.startOrUpdate(
                nextStop: target.name,
                nextCode: stop.code,
                remainingKm: payload.remainingKm,
                remainingMin: payload.remainingMin,
                speedKmh: speedKmh ?? 0,
                progress: nav.nextStop?.id == stop.id ? nav.legProgress : 0
            )
        }

        if openMaps {
            NavApp.openAppleMaps(
                toCoordinate: CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude),
                name: target.name
            )
        }
        return true
    }

    private static func metricsForStart(stop: Stop, target: ArrivalTarget, nav: NavProgressStore,
                                        location: CLLocation) async -> RouteStartMetrics {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: target.latitude, longitude: target.longitude
        )))
        request.transportType = .automobile

        if let route = try? await MKDirections(request: request).calculate().routes.first {
            return RouteStartMetrics(
                remainingKm: Int((route.distance / 1000).rounded()),
                remainingMinutes: Int((route.expectedTravelTime / 60).rounded())
            )
        }

        let straightKm = location.distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude)) / 1000
        return RouteStartMetrics(
            remainingKm: Int(straightKm.rounded()),
            remainingMinutes: max(1, Int((straightKm / 80 * 60).rounded()))
        )
    }
}
