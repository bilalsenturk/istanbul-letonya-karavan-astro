import Foundation

/// Letonca hatırlatmalarının dört kutusu. Kimlikler ve bütçe eşlemesi bunun üstünden
/// kuruluyor; sistem tarafı (UserNotifications) bu dosyada YOK.
enum LatvianNotificationSlot: String, CaseIterable, Sendable {
    /// Öğrencinin kendi alışkanlık saatinde, her gün.
    case daily
    /// Seri gerçekten kopmak üzereyken, gün bitmeden.
    case streakRescue
    /// Bir kez geçilmiş sahne hakimiyetin altına düştüğünde.
    case decay
    /// 7 / 30 / 100 günlük seri.
    case milestone
}

/// Bir bildirimin ne zaman çalacağı — sistem tetikleyicisine çevrilmeden önceki hâli.
///
/// **Saat dilimi bilerek taşınmıyor.** Her iki durum da cihazın o andaki YEREL
/// takvimiyle yorumlanır. Bkz. `LatvianNotificationRules` başlığındaki saat dilimi notu.
enum LatvianNotificationTiming: Equatable, Sendable {
    /// Her gün, yerel saatle `hour:minute`.
    case everyDay(hour: Int, minute: Int)
    /// Tek sefer, yerel takvimde bu an.
    case once(year: Int, month: Int, day: Int, hour: Int, minute: Int)
}

/// Kurulacak tek bir bildirim. Saf karar katmanının çıktısı; sistem tarafı bunu
/// olduğu gibi `UNNotificationRequest`'e çeviriyor, başka karar vermiyor.
struct LatvianNotificationPlanItem: Equatable, Sendable {
    let slot: LatvianNotificationSlot
    let id: String
    let title: String
    let body: String
    let timing: LatvianNotificationTiming

    var hour: Int {
        switch timing {
        case .everyDay(let hour, _): return hour
        case .once(_, _, _, let hour, _): return hour
        }
    }
}

/// Letonca bildirimlerinin saf karar katmanı — cihazsız test edilebilir.
///
/// Burada `Date()` çağrılmıyor ve `Calendar.current` okunmuyor: zamana bakan her
/// fonksiyon hem `now` hem `calendar` alıyor. Motorun geri kalanındaki "gizli saat yok"
/// kuralının aynısı (bkz. `LatvianProgress`).
///
/// ## Saat dilimi kararı
///
/// Yolculuk İstanbul'dan Riga'ya birkaç saat dilimi geçiyor. Planlanan her bildirim
/// **cihazın o andaki yerel saatiyle** yorumlanıyor: `DateComponents` üzerine
/// `timeZone` yazılmıyor, dolayısıyla `UNCalendarNotificationTrigger` tetikleme anında
/// hangi dilimdeyse ona göre çalıyor.
///
/// Kasıtlı: alışkanlık mutlak bir ana değil, öğrencinin **gününe** bağlı — akşam molası
/// Varşova'da da Riga'da da akşam molası. Aynı seçim sessiz saatleri de kendiliğinden
/// koruyor: 23:00-08:00 penceresi yerel saatle tanımlı ve planlanan hiçbir saat bu
/// pencereye düşmüyor, dolayısıyla dilim değişse de öğrenci gece uyandırılmıyor.
/// (Alternatif — bileşenlere İstanbul dilimini sabitlemek — Varşova'da 08:00'lik bir
/// hatırlatmayı 07:00'ye, yani yerel sessiz saatin içine kaydırırdı.)
///
/// Bedeli açıkça kabul ediliyor: batıya doğru bir dilim geçişinde iki tetikleme arası
/// 25 saat, doğuya doğru 23 saat olabilir. Gün başına en fazla bir günlük hatırlatma
/// düştüğü için bu, fazladan bildirim üretmiyor.
enum LatvianNotificationRules {

    // MARK: - Sabitler

    /// Sessiz saat penceresinin başı (dahil): 23:00.
    static let quietStartHour = 23
    /// Sessiz saat penceresinin sonu (hariç): 08:00.
    static let quietEndHour = 8
    /// Alışkanlık öğrenilene kadarki hatırlatma saati.
    static let defaultHour = 20
    /// Seri kurtarma anı — gün bitmeden, ama sessiz saatten önce.
    static let streakRescueHour = 21
    static let streakRescueMinute = 30
    /// İki unutma uyarısı arasındaki en kısa süre.
    static let decayCooldown: TimeInterval = 7 * 86_400
    /// Unutma uyarısı en erken bu kadar gün sonrasına kurulur.
    ///
    /// İki gün, "günde en fazla iki bildirim" sınırını hesap yapmadan güvenceye alıyor:
    /// seri kurtarma yalnızca bugüne ya da yarına düşebiliyor, dolayısıyla iki gün
    /// ötedeki bir uyarı taze bir planda onunla asla aynı güne gelmiyor.
    static let decayLeadDays = 2
    /// Dönüm noktası bildirimi ders bittikten bu kadar sonra çalar — kutlama ekranının
    /// üstüne banner atmamak için.
    static let milestoneDelay: TimeInterval = 30 * 60
    static let milestones: [Int] = [7, 30, 100]

    /// Alışkanlık saati kaç derse bakarak öğreniliyor.
    static let historyWindow = 7
    /// Bu kadar ders görülmeden alışkanlık saati değiştirilmiyor: iki veri noktası
    /// "alışkanlık" değil, tesadüf.
    static let minimumHistory = 4
    /// Seçilen saatin çevresindeki (±1 saat) ders sayısı bunun altındaysa alışkanlık
    /// yeterince belirgin sayılmıyor ve varsayılana dönülüyor.
    static let minimumClusterWeight = 3
    /// Yeni aday, mevcut saati ancak bu kadar fark atarsa yerine geçer. Histerezis
    /// olmadan 7 derslik pencere her ders sonunda saati bir ileri bir geri oynatırdı.
    static let hysteresisMargin = 2

    // MARK: - Kimlikler

    /// Bütün Letonca bildirimlerinin ortak öneki. `NotificationManager` ön plan
    /// bastırmasında da bunu kullanıyor.
    static let idPrefix = "letonca."

    static func identifier(for slot: LatvianNotificationSlot) -> String {
        "\(idPrefix)\(slot.rawValue)"
    }

    static func milestoneIdentifier(_ streakDays: Int) -> String {
        "\(idPrefix)\(LatvianNotificationSlot.milestone.rawValue).\(streakDays)"
    }

    /// `plan(...)` tarafından kurulan kutular. Planda yer almayan bir kimlik artık
    /// geçersizdir ve koşulsuz silinir.
    ///
    /// Dönüm noktası bilerek dışarıda: ders sonunda tek başına kuruluyor ve plan
    /// yenilenirken silinmemeli — yoksa yedinci günü kutlayan bildirim, öğrenci
    /// uygulamayı bir kez daha açtığı anda kaybolurdu.
    static var plannedIdentifiers: [String] {
        [
            identifier(for: .daily),
            identifier(for: .streakRescue),
            identifier(for: .decay),
        ]
    }

    /// Bu modülün sahiplendiği bütün kimlikler. Kapatma **yalnızca** bunlara dokunuyor:
    /// sınır geçişi ya da günlük hatırlatması gibi başka bildirimler asla silinmiyor.
    /// Liste sabit ve sonlu olduğundan bekleyen istek sayısı da büyümüyor — iOS'un
    /// 64 istek sınırında başka bildirimlerin yerini yemiyor.
    static var managedIdentifiers: [String] {
        plannedIdentifiers + milestones.map(milestoneIdentifier)
    }

    // MARK: - Sessiz saatler

    static func isQuietHour(_ hour: Int) -> Bool {
        hour >= quietStartHour || hour < quietEndHour
    }

    /// Sessizlik **yerel** saatle ölçülüyor: takvimin dilimi kararı belirliyor.
    /// Aynı an İstanbul'da 23:30, Varşova'da 22:30 — ilki sessiz, ikincisi değil.
    static func isQuietHour(_ date: Date, calendar: Calendar) -> Bool {
        isQuietHour(calendar.component(.hour, from: date))
    }

    /// Hatırlatma için kullanılabilir bir saat mi (geçerli aralık + sessiz saat dışı).
    static func validReminderHour(_ hour: Int) -> Int? {
        guard (0...23).contains(hour), !isQuietHour(hour) else { return nil }
        return hour
    }

    // MARK: - Alışkanlık saati

    /// Öğrencinin gerçekten ders yaptığı saat.
    ///
    /// Üç koruma var:
    ///
    /// 1. **Yeterli geçmiş.** `minimumHistory`'den az ders varsa hiçbir şey öğrenilmiş
    ///    sayılmıyor; iki veri noktası varsayılanı (ya da mevcut saati) değiştiremez.
    /// 2. **Kümeleme.** Sayım saat başına değil, ±1 saatlik pencereyle yapılıyor:
    ///    19:55 ve 21:05'te çalışan biri "tek tepe" olarak görülüyor, aksi halde hiçbir
    ///    saat çoğunluğa ulaşamazdı.
    /// 3. **Histerezis.** Yeni aday, mevcut saatin ağırlığını `hysteresisMargin` kadar
    ///    geçmeden değişiklik yapılmıyor. Kayan pencerenin her ders sonunda saati
    ///    oynatmasını bu engelliyor.
    ///
    /// Sessiz saatte yoğunlaşan alışkanlık (gece 02:00) bilerek takip edilmiyor:
    /// aday saatler yalnızca 08:00-22:00 arasından seçiliyor.
    ///
    /// - Parameter current: Şu an kurulu olan hatırlatma saati; ilk kez kuruluyorsa `nil`.
    static func preferredHour(recentLessonHours: [Int], current: Int?) -> Int {
        let fallback = current.flatMap(validReminderHour) ?? defaultHour
        let hours = recentLessonHours.suffix(historyWindow).filter { (0...23).contains($0) }
        guard hours.count >= minimumHistory else { return fallback }

        var counts = [Int](repeating: 0, count: 24)
        for hour in hours { counts[hour] += 1 }

        func weight(_ hour: Int) -> Int {
            counts[(hour + 23) % 24] + counts[hour] + counts[(hour + 1) % 24]
        }

        // Eşit ağırlıkta KENDİ sayımı yüksek olan saat kazanıyor: 09:00'da dört ders
        // yapan öğrencide 08:00 de aynı pencere ağırlığını taşıyor, ama dersin
        // gerçekten yapıldığı saat 09:00. Sonuç sabit bir taramaya bağlı — sözlük ya da
        // küme sırasına değil — dolayısıyla süreçten sürece aynı.
        var best = fallback
        var bestWeight = -1
        var bestCount = -1
        for hour in 0..<24 where !isQuietHour(hour) {
            let candidate = weight(hour)
            guard candidate > bestWeight || (candidate == bestWeight && counts[hour] > bestCount)
            else { continue }
            bestWeight = candidate
            bestCount = counts[hour]
            best = hour
        }

        guard bestWeight >= minimumClusterWeight else { return fallback }
        guard let current, let currentHour = validReminderHour(current) else { return best }
        return bestWeight >= weight(currentHour) + hysteresisMargin ? best : currentHour
    }

    // MARK: - Seri

    /// Seri şu anda gerçekten tehlikede mi: bugün ders yok, son ders **dün**, seri canlı.
    ///
    /// "Son ders dün" koşulu şart: `streakDays` sıfırlanması bir sonraki derse kadar
    /// beklediğinden, üç gün önce kopmuş bir seride de `streakDays > 0` görünür.
    /// O seriyi "kurtarmak" diye bir şey yok — kurtarma bildirimi yalan söylerdi.
    static func isStreakAtRisk(progress: LatvianProgress, now: Date, calendar: Calendar) -> Bool {
        guard progress.streakDays > 0, let last = progress.lastLessonDay else { return false }
        let today = LatvianProgress.dayKey(now, calendar: calendar)
        guard last != today else { return false }
        guard let yesterday = calendar.date(
            byAdding: .day, value: -1, to: calendar.startOfDay(for: now)
        ) else { return false }
        return last == LatvianProgress.dayKey(yesterday, calendar: calendar)
    }

    /// Kurtarma bildirimi **şu anda** gönderilmeli mi: seri tehlikede ve kurtarma saati
    /// gelmiş, ama sessiz saate girilmemiş.
    static func needsStreakRescue(progress: LatvianProgress, now: Date, calendar: Calendar) -> Bool {
        guard isStreakAtRisk(progress: progress, now: now, calendar: calendar) else { return false }
        let hour = calendar.component(.hour, from: now)
        return hour >= streakRescueHour && !isQuietHour(hour)
    }

    /// Serinin tehlikeye gireceği ilk kurtarma anı; yoksa `nil`.
    ///
    /// Bugün ders yapıldıysa risk günü **yarın**; dün yapıldıysa **bugün**. İkisi de
    /// değilse seri zaten kopmuş, kurulacak bir şey yok. Geçmiş bir an döndürülmüyor:
    /// `UNCalendarNotificationTrigger` geçmiş bir tarihte hiç çalmaz.
    static func nextStreakRescueMoment(
        progress: LatvianProgress,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        guard progress.streakDays > 0, let last = progress.lastLessonDay else { return nil }
        let today = calendar.startOfDay(for: now)
        let riskDay: Date
        if last == LatvianProgress.dayKey(now, calendar: calendar) {
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
            riskDay = tomorrow
        } else if isStreakAtRisk(progress: progress, now: now, calendar: calendar) {
            riskDay = today
        } else {
            return nil
        }
        guard let moment = calendar.date(
            bySettingHour: streakRescueHour, minute: streakRescueMinute, second: 0, of: riskDay
        ) else { return nil }
        return moment > now ? moment : nil
    }

    // MARK: - Dönüm noktası

    static func isMilestone(_ streakDays: Int) -> Bool {
        milestones.contains(streakDays)
    }

    /// Dönüm noktası bildiriminin çalacağı an; dönüm noktası değilse ya da şu an
    /// sessiz saatteysek `nil`.
    ///
    /// Ders biter bitmez çalmıyor: kutlama ekranı zaten ekranda, üstüne banner atmak
    /// aynı şeyi iki kez söylemek olurdu. Gecikme sessiz saate taşarsa an, sessizliğin
    /// hemen öncesine çekiliyor — ertesi güne itilseydi o günün bildirim bütçesini
    /// (günlük hatırlatma + olası seri kurtarma) üçe çıkarabilirdi.
    static func milestoneMoment(streakDays: Int, now: Date, calendar: Calendar) -> Date? {
        guard isMilestone(streakDays), !isQuietHour(now, calendar: calendar) else { return nil }
        let target = now.addingTimeInterval(milestoneDelay)
        guard let quietStart = calendar.date(
            bySettingHour: quietStartHour, minute: 0, second: 0, of: calendar.startOfDay(for: now)
        ) else { return target }
        return min(target, quietStart.addingTimeInterval(-60))
    }

    // MARK: - Unutma uyarısı

    static func canSendDecayNotice(lastDecayNotice: Date?, now: Date) -> Bool {
        guard let lastDecayNotice else { return true }
        return now.timeIntervalSince(lastDecayNotice) >= decayCooldown
    }

    /// Hakimiyetin altına düşmüş, daha önce geçilmiş sahnelerden **en çok soluğanı**.
    ///
    /// Soğuma burada bakılmıyor (bkz. `decayMoment`): bu fonksiyon yalnızca "hangi sahne
    /// unutuluyor" sorusuna cevap veriyor. En düşük hakimiyet oranı kazanıyor, eşitlikte
    /// sahne sırası — sonuç sözlük sırasına bağlı değil.
    static func decayingScene(pack: LatvianPack, progress: LatvianProgress, now: Date) -> LatvianScene? {
        var weakest: LatvianScene?
        var weakestRatio = Double.infinity
        for scene in pack.scenes where progress.hasCompleted(sceneId: scene.id) {
            let ratio = LatvianLessonBuilder.masteryRatio(scene: scene, progress: progress, now: now)
            guard ratio < LatvianLessonBuilder.masteryCoverage else { continue }
            // Kesin `<`: eşitlikte ilk sahne (paket sırası) kalıyor, dolayısıyla
            // sonuç sözlük/küme sırasına değil sabit bir taramaya bağlı.
            if ratio < weakestRatio {
                weakestRatio = ratio
                weakest = scene
            }
        }
        return weakest
    }

    /// Unutma uyarısının çalacağı an.
    ///
    /// `scheduledAt` **kurulu** uyarının anı: ileri tarihliyse aynen korunuyor. Her ders
    /// sonunda yeni bir an hesaplansaydı uyarı sonsuza kadar ötelenir ve hiç çalmazdı.
    /// Geçmişte kalmışsa (çalmış sayılır) yenisi ancak `decayCooldown` dolduktan sonra
    /// kuruluyor.
    ///
    /// Kurulu an seri kurtarmayla aynı güne düşerse — arada geçen günlerde seri kurtarma
    /// yeni bir güne kaymış olabilir — uyarı bir gün öteleniyor; günde iki bildirim
    /// sınırı her durumda korunuyor.
    static func decayMoment(
        scheduledAt: Date?,
        rescueAt: Date?,
        reminderHour: Int,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let hour = decayHour(reminderHour: reminderHour)
        let firstOffset: Int

        if let scheduledAt, scheduledAt > now {
            guard let rescueAt, calendar.isDate(rescueAt, inSameDayAs: scheduledAt) else {
                return scheduledAt
            }
            firstOffset = max(decayLeadDays, dayOffset(from: now, to: scheduledAt, calendar: calendar) + 1)
        } else {
            guard canSendDecayNotice(lastDecayNotice: scheduledAt, now: now) else { return nil }
            firstOffset = decayLeadDays
        }

        for offset in firstOffset...(firstOffset + 2) {
            guard let day = calendar.date(
                      byAdding: .day, value: offset, to: calendar.startOfDay(for: now)
                  ),
                  let moment = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                  moment > now else { continue }
            if let rescueAt, calendar.isDate(rescueAt, inSameDayAs: moment) { continue }
            return moment
        }
        return nil
    }

    /// Unutma uyarısı günlük hatırlatmayla aynı saate düşmemeli — ikisi aynı dakikada
    /// çalarsa öğrenci tek bildirim görür, biri boşa gider. Basit ve belirlenimci:
    /// hatırlatma öğleden sonraysa uyarı öğlene, sabahsa akşam üstüne.
    static func decayHour(reminderHour: Int) -> Int {
        reminderHour >= 14 ? 12 : 17
    }

    // MARK: - Plan

    /// Kurulacak bildirimlerin tamamı. Sistem tarafı bunu olduğu gibi uyguluyor.
    ///
    /// Günde en fazla iki bildirim: her güne bir günlük hatırlatma düşüyor, tek seferlik
    /// kutulardan (seri kurtarma, unutma uyarısı) aynı güne en fazla biri geliyor.
    /// `dailyLoad(_:)` bunu ölçüyor ve test bunu sınıyor.
    static func plan(
        progress: LatvianProgress,
        pack: LatvianPack?,
        recentLessonHours: [Int],
        currentReminderHour: Int?,
        scheduledDecayAt: Date?,
        now: Date,
        calendar: Calendar
    ) -> [LatvianNotificationPlanItem] {
        var items: [LatvianNotificationPlanItem] = []

        let hour = preferredHour(recentLessonHours: recentLessonHours, current: currentReminderHour)
        items.append(
            LatvianNotificationPlanItem(
                slot: .daily,
                id: identifier(for: .daily),
                title: "Letonca vakti",
                body: "Bugünün dersi hazır. Üç dakika yeter.",
                timing: .everyDay(hour: hour, minute: 0)
            )
        )

        let rescueAt = nextStreakRescueMoment(progress: progress, now: now, calendar: calendar)
        if let rescueAt {
            items.append(
                LatvianNotificationPlanItem(
                    slot: .streakRescue,
                    id: identifier(for: .streakRescue),
                    title: "\(progress.streakDays) günlük serin duruyor",
                    body: "Bir ders yeter, seri devam eder. Acelesi yok, ben buradayım.",
                    timing: timing(for: rescueAt, calendar: calendar)
                )
            )
        }

        if let pack,
           let scene = decayingScene(pack: pack, progress: progress, now: now),
           let decayAt = decayMoment(
               scheduledAt: scheduledDecayAt,
               rescueAt: rescueAt,
               reminderHour: hour,
               now: now,
               calendar: calendar
           ) {
            items.append(
                LatvianNotificationPlanItem(
                    slot: .decay,
                    id: identifier(for: .decay),
                    title: "\(scene.title) soluyor",
                    body: "Birkaç kelime unutulmaya başladı. Kısa bir tekrar yeter.",
                    timing: timing(for: decayAt, calendar: calendar)
                )
            )
        }

        // Son savunma: hesapta bir yanlışlık olsa bile sessiz saatte bildirim kurulmuyor.
        return items.filter { !isQuietHour($0.hour) }
    }

    /// Planın bir güne bindirdiği en yüksek bildirim sayısı. İki'yi geçmemeli.
    static func dailyLoad(_ items: [LatvianNotificationPlanItem]) -> Int {
        let repeating = items.contains {
            if case .everyDay = $0.timing { return true }
            return false
        }
        var perDay: [String: Int] = [:]
        for item in items {
            guard case .once(let year, let month, let day, _, _) = item.timing else { continue }
            perDay[String(format: "%04d-%02d-%02d", year, month, day), default: 0] += 1
        }
        return (repeating ? 1 : 0) + (perDay.values.max() ?? 0)
    }

    // MARK: - Zaman dönüşümleri

    static func timing(for date: Date, calendar: Calendar) -> LatvianNotificationTiming {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return .once(
            year: parts.year ?? 0,
            month: parts.month ?? 0,
            day: parts.day ?? 0,
            hour: parts.hour ?? 0,
            minute: parts.minute ?? 0
        )
    }

    /// Tek seferlik bir zamanlamanın karşılık geldiği an. Tekrarlayan zamanlamada `nil`.
    static func date(from timing: LatvianNotificationTiming, calendar: Calendar) -> Date? {
        guard case .once(let year, let month, let day, let hour, let minute) = timing else { return nil }
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        )
    }

    /// Geçmiş bir dersin kaydedilecek saati. Alışkanlık öğrenmesi bunu besliyor.
    static func lessonHour(_ date: Date, calendar: Calendar) -> Int {
        calendar.component(.hour, from: date)
    }

    /// Yeni dersi geçmişe ekler ve pencereyi `historyWindow` ile sınırlar.
    static func appendLessonHour(_ hour: Int, to history: [Int]) -> [Int] {
        guard (0...23).contains(hour) else { return Array(history.suffix(historyWindow)) }
        return Array((history + [hour]).suffix(historyWindow))
    }

    private static func dayOffset(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)
        ).day ?? 0
    }
}
