import Foundation

/// Letonca kursunun durumu: paket, ilerleme, rota durakları ve ders akışı.
///
/// **Saat burada okunuyor, başka hiçbir yerde.** Motorun tamamı `now`'ı
/// parametre olarak alıyor ve hiçbir yerde `Date()` çağırmıyor; gerçek zaman
/// uygulamaya buradaki `clock` üzerinden giriyor. Görünümler de saate bakmıyor:
/// gösterecekleri her türetilmiş değer burada hazırlanıyor.
///
/// **Rota durakları önbellekli.** `masteryRatio` sahnenin bütün kelimelerini
/// geziyor; on iki sahne için gövde değerlendirmesi başına yapılamaz. Hesap
/// yalnızca ilerleme değiştiğinde (`refreshDerived`) bir kez yapılıyor.
@MainActor
final class LatvianCourseModel: ObservableObject {
    @Published private(set) var progress = LatvianProgress.new()
    @Published private(set) var stops: [LatvianRouteStop] = []
    @Published private(set) var currentStopId: String?
    @Published private(set) var isDailyGoalDone = false
    /// Canlar eksikken bir sonraki canın geleceği an; doluyken `nil`.
    @Published private(set) var nextHeartAt: Date?
    @Published private(set) var storage: LatvianStorageState = .ok
    /// Paket hiç açılamadı: ekranın tamamı bunun yerine hata gösteriyor.
    @Published private(set) var loadError: String?
    /// Bir dokunuşa verilen geçici Türkçe cevap (kilitli durak, can bitti…).
    @Published private(set) var actionNotice: String?
    /// Şu anki durakta "öğrenildi ama daha oturmadı" durumunun cümlesi; yoksa `nil`.
    /// Halkanın neden beklediğini söyleyen tek yer (bkz. `LatvianCourseRules.restNotice`).
    @Published private(set) var restNotice: String?
    /// Letonca hatırlatmaları açık mı — tek anahtar, dört bildirimi birden yönetiyor.
    @Published private(set) var notificationsEnabled: Bool

    @Published private(set) var lesson: LatvianLessonRun?
    @Published private(set) var celebration: LatvianCelebration?

    /// Ders akışı (soru ekranı **ya da** kutlama) açık mı. Tek bir tam ekran
    /// kapak kullanılıyor: iki ayrı kapağı aynı karede biri kapanıp öbürü
    /// açılacak şekilde tetiklemek SwiftUI'da ikincisini sessizce düşürüyor.
    var isLessonFlowPresented: Bool { lesson != nil || celebration != nil }

    private let scheduler: LatvianScheduler = LatvianFSRSScheduler()
    private let clock: () -> Date
    private var pack: LatvianPack?
    private var factory: LatvianExerciseFactory?
    private var didLoad = false
    /// Her ders koşusuna tekil kimlik ve tekil tohum veriyor.
    private var runCounter = 0
    /// Son bildirim yenilemesi. Yenileri bunun arkasına diziliyor (bkz. `syncNotifications`).
    private var notificationTask: Task<Void, Never>?

    /// Bildirim tercihleri `UserDefaults`'ta: ilerleme dosyasının aksine küçük,
    /// yedeklenmesi gerekmeyen ve ilerlemeden bağımsız değerler.
    ///
    /// `@AppStorage` kullanılmadı — `DynamicProperty` olduğu için görünüm dışında
    /// güncellenmiyor (aynı gerekçe: `LatvianFeedback`).
    private enum DefaultsKey {
        static let enabled = "letonca.bildirimAcik"
        static let lessonHours = "letonca.dersSaatleri"
        static let reminderHour = "letonca.hatirlatmaSaati"
        static let decayNoticeAt = "letonca.unutmaUyarisiAni"
    }

    init(clock: @escaping () -> Date = { Date() }) {
        self.clock = clock
        // Varsayılan AÇIK: hatırlatma bu kursun yarısı. Kapatması tek dokunuş,
        // ve kapatınca kurulu olanlar da gerçekten siliniyor.
        let defaults = UserDefaults.standard
        notificationsEnabled = defaults.object(forKey: DefaultsKey.enabled) as? Bool ?? true
    }

    // MARK: - Yükleme

    /// Paketi ve ilerlemeyi okur, canları tazeler, sonra eksik sesleri indirir.
    ///
    /// Ses indirmesi **en sonda**: rota haritası 412 klibin inmesini beklemeden
    /// çiziliyor ve öğrenci beklemeden derse girebiliyor.
    ///
    /// Bir kez çalışıyor. Ekran görünüp kaybolduğunda `.task` yeniden koşuyor;
    /// ikinci bir yükleme bellekteki ilerlemeyi diskteki eski kopyayla ezerdi.
    func load(audio: LatvianAudioStore) async {
        guard !didLoad else {
            refreshHearts()
            return
        }
        didLoad = true
        let now = clock()

        do {
            let pack = try LatvianPack.loadBundled()
            self.pack = pack
            factory = LatvianExerciseFactory(pack: pack)
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription
                ?? "Letonca paketi açılamadı."
            return
        }

        let loaded = LatvianProgress.load()
        progress = loaded.progress
        switch loaded.outcome {
        case .fresh, .loaded: storage = .ok
        case .recovered: storage = .recovered
        case .reset: storage = .reset
        }

        // Aradan geçen gerçek süre kadar can geri geliyor: dört saat sonra
        // dönen öğrenci ekranı açtığı anda dolumu görüyor.
        refillHearts(now: now)
        refreshDerived(now: now)

        // İzin BURADA istenmiyor: ilk ders bitmeden bildirim izni sormak, henüz
        // hiçbir şey görmemiş öğrenciye sorulmuş olurdu. Kurulum yalnızca izin
        // zaten varsa yapılıyor; yoksa ilk dersten sonra isteniyor (bkz. `finish`).
        syncNotifications(force: false, requestPermission: false)

        guard let pack else { return }
        await audio.syncMissing(pack: pack)
    }

    /// Geçen süreye göre canları tazeler. Ekran öne geldiğinde ve dakikada bir
    /// çağrılıyor; hiçbir şey değişmediyse diske dokunmuyor.
    func refreshHearts() {
        refillHearts(now: clock())
    }

    private func refillHearts(now: Date) {
        let before = progress.hearts
        progress.refillHearts(now: now)
        if progress.hearts != before {
            persist()
            // Dolum geldiyse ekranda duran "canların bitti" uyarısı artık yanlış.
            if progress.hearts > 0 { actionNotice = nil }
        }
        // Can değişmese de çağrılıyor: gece yarısını ekran açıkken geçen öğrencide
        // günlük hedef halkası yoksa sıfırlanmadan kalırdı.
        refreshDerived(now: now)
    }

    // MARK: - Ders

    func startLesson(sceneId: String, audio: LatvianAudioStore) {
        guard !isLessonFlowPresented, let pack, let factory,
              let scene = pack.scene(id: sceneId) else { return }

        let now = clock()
        refillHearts(now: now)

        guard stops.first(where: { $0.id == sceneId })?.isUnlocked == true else {
            actionNotice = "Bu durak henüz kilitli. Önce önceki durakları bitir."
            return
        }
        guard progress.hearts > 0 else {
            actionNotice = LatvianCourseRules.outOfHeartsNotice(at: nextHeartAt)
            return
        }

        runCounter += 1
        let exercises = LatvianLessonBuilder.build(
            scene: scene,
            pack: pack,
            progress: progress,
            factory: factory,
            // `downloadedAudioIds` değil: telaffuz sesi kapalıyken bu küme boş
            // geliyor ve sese bağlı soru tipleri hiç üretilmiyor. Aksi halde
            // "Duyduğun kelimeyi seç" sorusu sessiz bir düğmeyle cevapsız kalırdı.
            availableAudio: audio.availableAudioIds,
            seed: LatvianCourseRules.seed(now: now, counter: runCounter),
            now: now,
            // Apple'ın konuşma tanıması Letoncayı içermiyor, dolayısıyla bu bugün her
            // cihazda `[.speak]`. Kapalı bir mikrofonla soru sormak yerine soruyu hiç
            // sormuyoruz; hakimiyet kapısı yine kapanıyor, bkz. `LatvianSpeechAvailability`.
            excludedKinds: LatvianSpeechAvailability.hasLatvian ? [] : [.speak]
        )
        guard !exercises.isEmpty else {
            actionNotice = "Bu durak için şu an soru hazırlanamadı."
            return
        }

        actionNotice = nil
        lesson = LatvianLessonRun(id: runCounter, sceneId: scene.id, exercises: exercises)
        // Ders ekranı açıkken "ders vakti" bildirimi gürültü — bkz. NotificationManager.
        LatvianNotificationScheduler.isLessonInProgress = true
    }

    /// Dersin sonucunu hafızaya, XP'ye, seriye ve canlara işler; **kutlamadan
    /// önce** diske yazar. Uygulama kutlama ekranında öldürülse bile ders
    /// kaybolmuyor. İkinci çağrı hiçbir şey yapmıyor: `lesson` ilk turda düşüyor.
    ///
    /// ## Yarıda bırakılan ders (`wasAbandoned`)
    ///
    /// Muhasebenin tamamı yine işliyor: verilen her cevap FSRS'e yazılıyor, XP
    /// veriliyor, kaybedilen canlar düşüyor, sonuç diske yazılıyor. Yalnızca iki
    /// şey değişiyor — seri defteri (`registerLessonCompleted`, `recordLessonHour`)
    /// ilerlemiyor ve kutlama açılmıyor.
    ///
    /// Çıkışın bedavaya alınmaması bilinçli: yarıda bırakmak canları geri
    /// verseydi ya da cevapları çöpe atsaydı, can ekonomisinin tamamı isteğe
    /// bağlı hâle gelirdi — sıkışan öğrenci hiçbir maliyet ödemeden çıkıp
    /// yeniden girerdi. Kutlamanın açılmaması da aynı derde bakıyor ama ters
    /// yönden: üç soruda çıkan öğrenciye "Ders tamam!" ve konfeti göstermek,
    /// yapılmamış bir işi kutlamak olurdu.
    func finish(_ outcome: LatvianLessonOutcome) {
        guard let run = lesson else { return }
        let now = clock()

        // `registerAnswer` doğru cevap başına taban XP'yi kendisi ekliyor;
        // oturumun kombo ikramiyesini bilmiyor. Farkı ekleyerek toplam XP'ye
        // eklenen miktarı kutlamada gösterilen sayıyla birebir eşitliyoruz —
        // ikisini ayrı ayrı eklemek her doğru cevabı iki kez ödüllendirirdi.
        var base = 0
        for answer in outcome.answers {
            let written = progress.registerAnswer(
                wordId: answer.wordId,
                modality: answer.modality,
                rating: answer.rating,
                scheduler: scheduler,
                now: now
            )
            guard written else { continue }
            if answer.rating == .again {
                progress.loseHeart(now: now)
            } else {
                base += LatvianProgress.xpPerCorrectAnswer
            }
        }
        progress.awardXP(max(0, outcome.xp - base))

        let previousDay = progress.lastLessonDay
        // Seri defteri yalnızca gerçekten bitirilen derste ilerliyor: canı biten
        // de yarıda bırakan da günlük hedefi doldurmuş sayılmıyor.
        if !outcome.isFailed, !outcome.wasAbandoned {
            progress.registerLessonCompleted(now: now)
            // Alışkanlık saati buradan öğreniliyor: gerçekten ders yapılan saat,
            // cihazın o andaki YEREL takvimiyle (bkz. LatvianNotificationRules).
            recordLessonHour(now)
        }
        let streakExtended = progress.lastLessonDay != previousDay

        recordClearedScenes(now: now)
        persist()
        refreshDerived(now: now)

        LatvianNotificationScheduler.isLessonInProgress = false
        if streakExtended, LatvianNotificationRules.isMilestone(progress.streakDays) {
            let streakDays = progress.streakDays
            let enabled = notificationsEnabled
            Task {
                await LatvianNotificationScheduler.celebrateMilestone(
                    streakDays: streakDays, enabled: enabled, now: now
                )
            }
        }
        syncNotifications(force: false, requestPermission: true)

        lesson = nil
        // Yarıda bırakılanda kutlama kurulmuyor; `lesson` ve `celebration`'ın
        // ikisi de boş kalınca `isLessonFlowPresented` düşüyor ve tam ekran kapak
        // kendiliğinden kapanıyor — öğrenci doğrudan haritada buluyor kendini.
        guard !outcome.wasAbandoned else { return }
        celebration = LatvianCelebration(
            id: run.id,
            xp: outcome.xp,
            accuracy: outcome.accuracy,
            streakDays: progress.streakDays,
            streakExtended: streakExtended,
            isFailed: outcome.isFailed
        )
    }

    /// Kutlama kapandı: tam ekran kapak da kapanıyor.
    func dismissFlow() {
        lesson = nil
        celebration = nil
        LatvianNotificationScheduler.isLessonInProgress = false
    }

    func dismissActionNotice() { actionNotice = nil }

    // MARK: - Bildirimler

    /// Tek anahtar: dört bildirimi birden açıp kapatıyor. Kapatmak kurulu olanları
    /// gerçekten siliyor — "bir daha kurma" değil, "şu an bekleyenleri de kaldır".
    func setNotificationsEnabled(_ enabled: Bool) {
        guard enabled != notificationsEnabled else { return }
        notificationsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.enabled)
        // Kullanıcının doğrudan eylemi: bütçe soğuması atlanıyor, yoksa anahtarı
        // kapatıp hemen açan kullanıcı 45 dakika bildirimsiz kalırdı.
        syncNotifications(force: true, requestPermission: enabled)
    }

    /// Planı hesaplayıp sisteme uygular ve dönen sonucu kalıcı duruma yazar.
    ///
    /// Ders sonunda, ekran açıldığında ve anahtar değiştiğinde çağrılıyor. Kimlikler
    /// sabit olduğu için tekrar çağrılması kopya üretmiyor; bütçe de aynı kutunun
    /// 45 dakikada birden sık yeniden kurulmasını engelliyor.
    /// İki kural birden geçerli:
    ///
    /// 1. **Sıraya giriyor.** Yeni çağrı öncekinin bitmesini bekliyor. Aksi halde iki
    ///    yeniden kurma iç içe geçebiliyor ve planda olmayan kutuları temizleyen adım
    ///    (bkz. `LatvianNotificationScheduler.reschedule`) daha yeni bir planı silebiliyor.
    /// 2. **Durumu çalışma anında okuyor.** Çağrı anında fotoğraf çekilseydi sıradaki
    ///    iş bayat bir ilerlemeyle koşardı: ekran açılışında kuyruğa giren yenileme,
    ///    ders bitiminden SONRA çalışıp seriyi hiç görmemiş gibi davranırdı — gerçekten
    ///    yaşandı, simülatörde seri kurtarma bildirimi bu yüzden kurulmuyordu.
    private func syncNotifications(force: Bool, requestPermission: Bool) {
        let previous = notificationTask
        notificationTask = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }

            let enabled = self.notificationsEnabled
            if enabled, requestPermission, !NotificationManager.shared.authorized {
                await NotificationManager.shared.requestAuthorization()
            }
            let calendar = Calendar.current
            let outcome = await LatvianNotificationScheduler.reschedule(
                enabled: enabled,
                progress: self.progress,
                pack: self.pack,
                recentLessonHours: self.recentLessonHours,
                currentReminderHour: self.storedReminderHour,
                scheduledDecayAt: self.storedDecayNoticeAt,
                force: force,
                now: self.clock(),
                calendar: calendar
            )
            self.absorb(outcome, calendar: calendar)
            #if DEBUG
            await LatvianNotificationScheduler.logPending(force ? "anahtar" : "yenileme")
            #endif
        }
    }

    /// Kurulan planın kalıcı izleri: öğrenilen saat (histerezisin dayanağı) ve kurulu
    /// unutma uyarısının anı (soğumanın dayanağı). Yalnızca GERÇEKTEN kurulanlar
    /// yazılıyor — bütçe reddettiyse eski değer duruyor, aksi halde kayıt sistemdeki
    /// istekle uyumsuz kalırdı.
    private func absorb(_ outcome: LatvianScheduleOutcome, calendar: Calendar) {
        guard case .scheduled(let applied, let reminderHour) = outcome else { return }
        UserDefaults.standard.set(reminderHour, forKey: DefaultsKey.reminderHour)
        if let decay = applied.first(where: { $0.slot == .decay }),
           let moment = LatvianNotificationRules.date(from: decay.timing, calendar: calendar) {
            UserDefaults.standard.set(moment.timeIntervalSince1970, forKey: DefaultsKey.decayNoticeAt)
        }
    }

    private var recentLessonHours: [Int] {
        UserDefaults.standard.array(forKey: DefaultsKey.lessonHours) as? [Int] ?? []
    }

    private var storedReminderHour: Int? {
        UserDefaults.standard.object(forKey: DefaultsKey.reminderHour) as? Int
    }

    private var storedDecayNoticeAt: Date? {
        let stamp = UserDefaults.standard.double(forKey: DefaultsKey.decayNoticeAt)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    private func recordLessonHour(_ date: Date) {
        let calendar = Calendar.current
        let updated = LatvianNotificationRules.appendLessonHour(
            LatvianNotificationRules.lessonHour(date, calendar: calendar),
            to: recentLessonHours
        )
        UserDefaults.standard.set(updated, forKey: DefaultsKey.lessonHours)
    }

    // MARK: - Türetilenler

    /// Hakim olunan her sahnenin ilk tamamlanma anını kaydeder.
    ///
    /// Kayıt olmadan kilit **geri kapanabilir**: kararlılık yanlış cevapla
    /// çöküyor, dolayısıyla aradan sonra dönüp birkaç kelimeyi unutan öğrenci
    /// geçtiği durağı kilitli bulurdu (bkz. `isSceneCleared`). Bütün sahneler
    /// taranıyor, yalnızca oynanan sahne değil: tekrar ve hata kotaları paketin
    /// her yerinden kelime çekiyor.
    private func recordClearedScenes(now: Date) {
        guard let pack else { return }
        for scene in pack.scenes
        where LatvianLessonBuilder.isSceneMastered(scene: scene, progress: progress, now: now) {
            progress.registerSceneCompletion(sceneId: scene.id, now: now)
        }
    }

    /// Dakikada bir de çağrıldığı için her alan **değiştiyse** yazılıyor:
    /// `@Published` eşitlik bakmadan yayın yapıyor, yani koşulsuz atama on iki
    /// duraklı haritayı boş yere yeniden çizdirirdi.
    private func refreshDerived(now: Date) {
        let goalDone = progress.lastLessonDay == LatvianProgress.dayKey(now)
        if goalDone != isDailyGoalDone { isDailyGoalDone = goalDone }
        let heartAt = LatvianCourseRules.nextHeartAt(progress: progress)
        if heartAt != nextHeartAt { nextHeartAt = heartAt }

        guard let pack else {
            if !stops.isEmpty { stops = [] }
            if currentStopId != nil { currentStopId = nil }
            if restNotice != nil { restNotice = nil }
            return
        }
        let computed = LatvianCourseRules.stops(pack: pack, progress: progress, now: now)
        if computed != stops { stops = computed }
        let current = LatvianCourseRules.currentStopId(in: computed)
        if current != currentStopId { currentStopId = current }

        // Yalnızca öğrencinin üstünde durduğu, henüz geçilmemiş durak için: geçilmiş
        // durakta "demleniyor" demenin bir karşılığı yok, kilitli durağa da öğrenci
        // giremiyor.
        let notice = computed.first { $0.id == current && !$0.isCleared }
            .flatMap { pack.scene(id: $0.id) }
            .flatMap { scene in
                LatvianCourseRules.restNotice(
                    LatvianLessonBuilder.rest(scene: scene, progress: progress, now: now),
                    now: now
                )
            }
        if notice != restNotice { restNotice = notice }
    }

    private func persist() {
        do {
            try progress.save()
            storage = .ok
        } catch {
            storage = .saveFailed
        }
    }
}
