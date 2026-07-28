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
    private var lastDeparture: Date?   // saat dilimi değişince hatırlatmaları yeniden kurmak için

    override init() {
        super.init()
        center.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(timeZoneChanged),
                                               name: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil)
        Task { await self.refreshAuthorization() }
    }

    /// Saat dilimi geçişinde kalkış hatırlatmalarını yeni yerel takvimle yeniden kur.
    @objc private nonisolated func timeZoneChanged() {
        Task { @MainActor in
            if let departure = self.lastDeparture {
                self.scheduleDepartureReminders(departure: departure)
            }
        }
    }

    func requestAuthorization() async {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        authorized = granted
    }

    /// İzin durumunu sistemden tazeler — kullanıcı Ayarlar'dan kapatabilir;
    /// `authorized` yalnızca istek anında güncellenirse bayat kalır.
    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        authorized = settings.authorizationStatus == .authorized
    }

    /// Gönderim sonucu `completion` ile bildirilir (hata = planlama başarısız).
    /// Bütçe (NotificationBudget) harcayan çağıranlar hata durumunda damgayı
    /// release ile iade edebilsin diye.
    func notify(title: String, body: String, id: String = UUID().uuidString,
                completion: (@Sendable (Error?) -> Void)? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        if let completion {
            center.add(request, withCompletionHandler: completion)
        } else {
            center.add(request)
        }
    }

    /// Kalkışa göre hatırlatmalar. Kalkış değişince eskiler İPTAL edilip yeniden kurulur.
    func scheduleDepartureReminders(departure: Date) {
        lastDeparture = departure
        let ids = (0 ..< 3).map { "departure-\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)

        let cal = Calendar.current
        let plan: [(String, String, Date?)] = [
            ("Yarın yola çıkıyoruz", "Kuzey · İstanbul → Riga. Son kontrol listesine göz at.",
             cal.date(byAdding: .day, value: -1, to: departure)),
            ("2 saate kalkış", "Karavan bağlantıları, lastik ve evrakları son kez kontrol et.",
             cal.date(byAdding: .hour, value: -2, to: departure)),
            ("Gitmeye hazır mısın?", "30 dakikaya yola çıkıyoruz. Kemerler, gaz, evraklar — hadi!",
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

    /// Her akşam "bugünü günlüğe yaz" hatırlatması. Tekrarlayan; bir kez kurulur.
    func scheduleDailyJournalReminder(hour: Int = 21) {
        let id = "journal-daily"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let content = UNMutableNotificationContent()
        content.title = "Bugünü yaz"
        content.body = "Bugün ne oldu? Bir iki cümle bile yeter — istersen sesli."
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = 0

        center.add(UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        ))
    }

    /// Sabah gün özeti. İçerik gönderim anında değil kurulum anında sabitlenir;
    /// canlı veri gerektiren kısımlar app açılınca güncellenir.
    func scheduleDailySummary(hour: Int = 8) {
        let id = "summary-daily"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let content = UNMutableNotificationContent()
        content.title = "Bugünün planı"
        content.body = "Kuzey'i aç: sıradaki durak, hava ve kalan mesafe seni bekliyor."
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = 0

        center.add(UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        ))
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    // Ön plandayken de banner göster.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Tek istisna: ders ekranı açıkken Letonca hatırlatması. "Ders vakti"
        // bildirimi tam dersin ortasında çalarsa sadece gürültü olur — üstelik
        // banner soruyu kapatıyor. Yolculuk bildirimleri (sınır, mola, pil)
        // burada BASTIRILMIYOR: ders çalışmak onları ertelemek için sebep değil.
        if notification.request.identifier.hasPrefix(LatvianNotificationRules.idPrefix),
           await LatvianNotificationScheduler.isLessonInProgress {
            return []
        }
        return [.banner, .sound]
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
        await checkWeather()
    }

    /// SLOC/geofence uyanışından çağrılır (LocationManager): son kontrolün
    /// üzerinden `maxAge` geçmediyse atla — sürüşte konum güncellemesi çok
    /// sık gelir, ağ isteği kontrol başına değil eşik başına atılmalı.
    @MainActor
    static func refreshIfStale(maxAge: TimeInterval = 45 * 60) async {
        let key = "bgWeatherLastCheck"
        let last = UserDefaults.standard.double(forKey: key)
        guard Date().timeIntervalSince1970 - last > maxAge else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
        await checkWeather()
    }

    @MainActor
    private static func checkWeather() async {
        guard let stops = TripStore.bundledTrip()?.stops else { return }
        let weather = WeatherService()
        weather.notifier = NotificationManager.shared
        // Ön plan WeatherService'i ile aynı "weatherSnapshot" üzerinde
        // oku-değiştir-yaz yapılıyor — kapıdan geçmezsek eşzamanlı iki
        // yenilemede eski veri yeniyi ezer, yağmur başla/dur bildirimi
        // yutulur ya da çift atılır.
        await WeatherRefreshGate.run {
            await weather.refresh(stops: stops)
        }
    }
}

/// Hava yenilemelerini (ön plan + arka plan) tek sıraya bağlar.
/// WeatherService.refresh çağıran herkes bu kapıdan geçmeli; aksi halde
/// iki eşzamanlı refresh aynı UserDefaults anlık görüntüsünü yarıştırır.
@MainActor
enum WeatherRefreshGate {
    private static var current: Task<Void, Never>?

    static func run(_ work: @MainActor @escaping () async -> Void) async {
        await current?.value
        let task = Task { @MainActor in await work() }
        current = task
        await task.value
    }
}
