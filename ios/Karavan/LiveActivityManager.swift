import ActivityKit
import WidgetKit
import Foundation

// Sürüş Live Activity yönetimi: sürüş başlayınca kilit ekranı/Dynamic Island'da
// canlı ETA; konum geldikçe güncellenir; varışta biter. Push gerekmez (yerel).
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private var activity: Activity<TripActivityAttributes>?
    private var stateWatch: Task<Void, Never>?
    private var lastWidgetReload: Date = .distantPast
    /// Kullanıcının kilit ekranından sildiği kartın durağı — bir sonraki etaba
    /// kadar o etap için yeni kart otomatik açılmaz (sürüşte silinemez kart olmasın).
    private var dismissedStop: String?
    private let activityIdKey = "live-activity-id"

    var isActive: Bool { activity?.activityState == .active }

    private init() {
        // Uygulama yeniden başladıysa hâlâ canlı aktiviteyi sahiplen — yoksa
        // startOrUpdate kilit ekranında İKİNCİ bir kart açardı.
        let active = Activity<TripActivityAttributes>.activities.filter { $0.activityState == .active }
        let savedId = UserDefaults.standard.string(forKey: activityIdKey)
        if let existing = active.first(where: { $0.id == savedId })
            ?? active.sorted(by: { $0.id < $1.id }).last {
            activity = existing
            watchState(of: existing)
            for extra in active where extra.id != existing.id {
                Task { await extra.end(nil, dismissalPolicy: .immediate) }
            }
        }
    }

    func startOrUpdate(nextStop: String, nextCode: String,
                       remainingKm: Int, remainingMin: Int,
                       speedKmh: Int, progress: Double) {
        // Kullanıcı kartı kilit ekranından sildiyse referans dolu kalır; temizle
        // ki güncellemeler boşa gitmesin ve gerektiğinde yeni kart açılabilsin.
        if let activity, activity.activityState != .active {
            if activity.activityState == .dismissed { dismissedStop = activity.attributes.nextStop }
            self.activity = nil
        }

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
        // Kullanıcı bu etabın kartını sildiyse durak değişene kadar yeniden açma.
        guard dismissedStop != nextStop else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = TripActivityAttributes(nextStop: nextStop, nextCode: nextCode)
        activity = try? Activity.request(
            attributes: attrs,
            content: ActivityContent(state: state, staleDate: .now.addingTimeInterval(30 * 60))
        )
        if let activity {
            UserDefaults.standard.set(activity.id, forKey: activityIdKey)
            dismissedStop = nil   // yeni etap kartı açıldı → eski silme kaydı geçersiz
            watchState(of: activity)
        }
    }

    func endCurrent() {
        stateWatch?.cancel()
        stateWatch = nil
        guard let a = activity else { return }
        activity = nil
        UserDefaults.standard.removeObject(forKey: activityIdKey)
        Task { await a.end(nil, dismissalPolicy: .immediate) }
    }

    /// Kart silinir/kapanırsa referansı bırak (isActive yeniden doğru olur).
    private func watchState(of a: Activity<TripActivityAttributes>) {
        stateWatch?.cancel()
        stateWatch = Task { [weak self] in
            for await s in a.activityStateUpdates {
                guard s == .dismissed || s == .ended else { continue }
                if self?.activity?.id == a.id {
                    if s == .dismissed { self?.dismissedStop = a.attributes.nextStop }
                    self?.activity = nil
                    if let key = self?.activityIdKey {
                        UserDefaults.standard.removeObject(forKey: key)
                    }
                }
                return
            }
        }
    }

    /// Widget zaman çizelgelerini tazele (en fazla dakikada bir).
    func reloadWidgetsThrottled() {
        guard Date().timeIntervalSince(lastWidgetReload) > 60 else { return }
        lastWidgetReload = Date()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
