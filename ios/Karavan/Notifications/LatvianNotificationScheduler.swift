import Foundation
import OSLog
import UserNotifications

/// `LatvianNotificationScheduler.reschedule` sonucu.
///
/// `applied` yalnızca gerçekten kurulan kutuları içeriyor: bütçe reddettiyse ya da
/// sistem isteği kabul etmediyse o kutu listede yok. Çağıran kalıcı durumunu
/// (unutma uyarısının anı) buna göre yazıyor, planlanana göre değil.
enum LatvianScheduleOutcome: Equatable, Sendable {
    /// Anahtar kapalı ya da bildirim izni yok — kurulu her şey silindi.
    case off
    case scheduled(applied: [LatvianNotificationPlanItem], reminderHour: Int)
}

/// Saf kararları (`LatvianNotificationRules`) sisteme bağlayan katman.
///
/// Burada karar YOK: plan hazır geliyor, bu tip yalnızca "sil / kur / bütçeye sor"
/// yapıyor. Ayrı dosyada durmasının sebebi `ios/Tests/run-latvian-check.sh`:
/// saf kurallar bare `swiftc` ile derlenip cihazsız sınanıyor, bu dosya o listede yok.
/// (`#if canImport(UserNotifications)` bu ayrımı **yapmaz** — UserNotifications
/// macOS'ta da var, dolayısıyla koşul test derlemesinde de doğru çıkar.)
@MainActor
enum LatvianNotificationScheduler {
    private static var budget = NotificationBudget()
    private static let log = Logger(subsystem: "com.bilalsenturk.kuzey", category: "letonca-bildirim")

    /// Ders ekranı açık mı. Açıkken Letonca bildirimleri ön planda gösterilmiyor:
    /// öğrenci zaten dersin içindeyken "ders vakti" demek gürültü.
    /// `NotificationManager.userNotificationCenter(_:willPresent:)` buna bakıyor.
    static var isLessonInProgress = false

    private static var center: UNUserNotificationCenter { .current() }

    // MARK: - Kurulum

    /// Planı hesaplar ve sisteme uygular.
    ///
    /// Sıra kasıtlı: **önce kur, sonra artıkları sil.** Tersi (önce hepsini iptal et,
    /// sonra bütçeye sor) bütçe reddettiğinde bildirimi tamamen kaybederdi — bu tam
    /// olarak `NotificationBudget`'ta uyarılan tuzağın planlama tarafındaki karşılığı.
    /// Aynı kimlikle eklenen istek var olanın üstüne yazıldığından tekrar kurmak
    /// çoğaltmıyor; kimlikler sabit olduğu için de kayma olmuyor.
    ///
    /// - Parameter force: Kullanıcının doğrudan eylemi (anahtarı açmak). Bütçe atlanır.
    static func reschedule(
        enabled: Bool,
        progress: LatvianProgress,
        pack: LatvianPack?,
        recentLessonHours: [Int],
        currentReminderHour: Int?,
        scheduledDecayAt: Date?,
        force: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async -> LatvianScheduleOutcome {
        guard enabled, await isAuthorized() else {
            cancelAll()
            return .off
        }

        let items = LatvianNotificationRules.plan(
            progress: progress,
            pack: pack,
            recentLessonHours: recentLessonHours,
            currentReminderHour: currentReminderHour,
            scheduledDecayAt: scheduledDecayAt,
            now: now,
            calendar: calendar
        )
        let reminderHour = items.first { $0.slot == .daily }?.hour
            ?? LatvianNotificationRules.defaultHour

        var applied: [LatvianNotificationPlanItem] = []
        for item in items {
            let kind = notifKind(for: item.slot)
            // Bütçe reddederse ÖNCEKİ istek olduğu gibi kalıyor: ders üstüne ders
            // bitiren öğrencide planı dakikada bir söküp yeniden kurmuyoruz.
            guard force || budget.allow(kind, now: now) else { continue }
            do {
                try await center.add(request(for: item))
                applied.append(item)
            } catch {
                // Kurulum başarısız: bütçe damgası iade ediliyor, yoksa bu kutunun
                // 45 dakikalık hakkı hiçbir şey kurulmadan yanardı.
                if !force { budget.release(kind) }
                log.error("Letonca bildirimi kurulamadı (\(item.id, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            }
        }

        // Planda yer almayan kutular geçersiz — silmek gönderim değil, bütçeye sorulmaz.
        let planned = Set(items.map(\.id))
        let stale = LatvianNotificationRules.plannedIdentifiers.filter { !planned.contains($0) }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }

        return .scheduled(applied: applied, reminderHour: reminderHour)
    }

    /// Dönüm noktası kutlaması. Ders biter bitmez değil, `milestoneDelay` sonra çalıyor —
    /// kutlama ekranı zaten ekranda.
    @discardableResult
    static func celebrateMilestone(
        streakDays: Int,
        enabled: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async -> Bool {
        guard enabled,
              let moment = LatvianNotificationRules.milestoneMoment(
                  streakDays: streakDays, now: now, calendar: calendar
              ),
              await isAuthorized()
        else { return false }

        guard budget.allow(.latvianMilestone, now: now) else { return false }

        let content = UNMutableNotificationContent()
        content.title = "\(streakDays) gün oldu"
        content.body = "Letoncan artık kendi başına duruyor. Seninle gurur duyuyorum."
        content.sound = .default
        content.threadIdentifier = LatvianNotificationRules.idPrefix

        do {
            try await center.add(
                UNNotificationRequest(
                    identifier: LatvianNotificationRules.milestoneIdentifier(streakDays),
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(
                        timeInterval: max(5, moment.timeIntervalSince(now)),
                        repeats: false
                    )
                )
            )
            return true
        } catch {
            budget.release(.latvianMilestone)
            log.error("Dönüm noktası bildirimi kurulamadı: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// İzin durumu her seferinde sistemden okunuyor: kullanıcı Ayarlar'dan kapatabilir,
    /// önbelleklenmiş bir bayrak bayat kalır ve hiç çalmayacak bildirimler kurulurdu.
    private static func isAuthorized() async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// Anahtar kapatıldığında çağrılıyor: kurulu **ve** teslim edilmiş her şey gidiyor.
    /// Yalnızca `managedIdentifiers` siliniyor; başka bildirimlere dokunulmuyor.
    static func cancelAll() {
        let ids = LatvianNotificationRules.managedIdentifiers
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    // MARK: - Döküm

    /// Bekleyen Letonca isteklerinin okunabilir dökümü. Simülatörde doğrulama için;
    /// `logPending()` bunu sistem günlüğüne yazıyor.
    static func pendingDescriptions() async -> [String] {
        await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(LatvianNotificationRules.idPrefix) }
            .sorted { $0.identifier < $1.identifier }
            .map { request in
                "\(request.identifier) | \(describe(request.trigger))"
                    + " | \(request.content.title) — \(request.content.body)"
            }
    }

    static func logPending(_ label: String) async {
        let lines = await pendingDescriptions()
        log.notice("LETONCA-PENDING \(label, privacy: .public) sayı=\(lines.count, privacy: .public)")
        for line in lines {
            log.notice("LETONCA-PENDING \(line, privacy: .public)")
        }
    }

    // MARK: - Ayrıntılar

    private static func notifKind(for slot: LatvianNotificationSlot) -> NotifKind {
        switch slot {
        case .daily: return .latvianDaily
        case .streakRescue: return .latvianStreakRescue
        case .decay: return .latvianDecay
        case .milestone: return .latvianMilestone
        }
    }

    /// Plandaki zamanlamayı sistem tetikleyicisine çevirir.
    ///
    /// `components.timeZone` bilerek **atanmıyor**: bileşenler tetikleme anındaki yerel
    /// takvimle yorumlanır, dolayısıyla İstanbul'da kurulan 20:00'lik hatırlatma
    /// Varşova'da da 20:00'de çalar. Gerekçesi `LatvianNotificationRules` başlığında.
    private static func request(for item: LatvianNotificationPlanItem) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        content.threadIdentifier = LatvianNotificationRules.idPrefix

        var components = DateComponents()
        var repeats = false
        switch item.timing {
        case .everyDay(let hour, let minute):
            components.hour = hour
            components.minute = minute
            repeats = true
        case .once(let year, let month, let day, let hour, let minute):
            components.year = year
            components.month = month
            components.day = day
            components.hour = hour
            components.minute = minute
        }

        return UNNotificationRequest(
            identifier: item.id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
        )
    }

    private static func describe(_ trigger: UNNotificationTrigger?) -> String {
        switch trigger {
        case let calendarTrigger as UNCalendarNotificationTrigger:
            let next = calendarTrigger.nextTriggerDate().map { "\($0)" } ?? "-"
            return "takvim \(calendarTrigger.dateComponents) tekrar=\(calendarTrigger.repeats) sonraki=\(next)"
        case let interval as UNTimeIntervalNotificationTrigger:
            let next = interval.nextTriggerDate().map { "\($0)" } ?? "-"
            return "aralık +\(Int(interval.timeInterval))sn sonraki=\(next)"
        default:
            return "-"
        }
    }
}
