import Foundation
import UserNotifications
import BackgroundTasks

// Yerel bildirimler — sunucusuz. Hava değişimleri + kalkış hatırlatmaları.
// Ön planda anında; arka planda BGAppRefreshTask ile "best-effort" (iOS zamanlar).
@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    @Published var authorized = false
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        authorized = granted
    }

    func notify(title: String, body: String, id: String = UUID().uuidString) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    /// Kalkışa göre hatırlatmalar (1 gün ve 2 saat kala).
    func scheduleDepartureReminders(departure: Date) {
        let cal = Calendar.current
        let plan: [(String, String, Date?)] = [
            ("Yarın yola çıkıyoruz 🚐", "Kuzey · İstanbul → Riga. Son kontrol listesine göz at.",
             cal.date(byAdding: .day, value: -1, to: departure)),
            ("2 saate kalkış ⏱️", "Karavan bağlantıları, lastik ve evrakları son kez kontrol et.",
             cal.date(byAdding: .hour, value: -2, to: departure)),
            ("Gitmeye hazır mısın? 🚐", "30 dakikaya yola çıkıyoruz. Kemerler, gaz, evraklar — hadi!",
             cal.date(byAdding: .minute, value: -30, to: departure)),
        ]
        for (i, item) in plan.enumerated() {
            guard let fireDate = item.2, fireDate > Date() else { continue }
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let content = UNMutableNotificationContent()
            content.title = item.0
            content.body = item.1
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: "departure-\(i)", content: content, trigger: trigger))
        }
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    // Ön plandayken de banner göster.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

// Arka planda periyodik hava kontrolü (best-effort).
enum BackgroundWeather {
    static let taskId = "com.bilalsenturk.kuzey.weather"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 3600) // ~2 saat sonra
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func run() async {
        schedule() // bir sonrakini planla
        guard let stops = TripStore.bundledTrip()?.stops else { return }
        let weather = WeatherService()
        weather.notifier = NotificationManager.shared
        await weather.refresh(stops: stops)
    }
}
