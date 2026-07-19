import ActivityKit
import WidgetKit
import Foundation

// Sürüş Live Activity yönetimi: sürüş başlayınca kilit ekranı/Dynamic Island'da
// canlı ETA; konum geldikçe güncellenir; varışta biter. Push gerekmez (yerel).
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private var activity: Activity<TripActivityAttributes>?
    private var lastWidgetReload: Date = .distantPast

    var isActive: Bool { activity != nil }

    private init() {}

    func startOrUpdate(nextStop: String, nextCode: String,
                       remainingKm: Int, remainingMin: Int,
                       speedKmh: Int, progress: Double) {
        let state = TripActivityAttributes.ContentState(
            remainingKm: remainingKm, remainingMin: remainingMin,
            speedKmh: speedKmh, progress: min(1, max(0, progress))
        )

        if let activity, activity.attributes.nextStop == nextStop {
            Task { await activity.update(ActivityContent(state: state, staleDate: .now.addingTimeInterval(30 * 60))) }
            return
        }

        // Yeni etap → eskiyi kapat, yenisini başlat
        endCurrent()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = TripActivityAttributes(nextStop: nextStop, nextCode: nextCode)
        activity = try? Activity.request(
            attributes: attrs,
            content: ActivityContent(state: state, staleDate: .now.addingTimeInterval(30 * 60))
        )
    }

    func endCurrent() {
        guard let a = activity else { return }
        activity = nil
        Task { await a.end(nil, dismissalPolicy: .immediate) }
    }

    /// Widget zaman çizelgelerini tazele (en fazla dakikada bir).
    func reloadWidgetsThrottled() {
        guard Date().timeIntervalSince(lastWidgetReload) > 60 else { return }
        lastWidgetReload = Date()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
