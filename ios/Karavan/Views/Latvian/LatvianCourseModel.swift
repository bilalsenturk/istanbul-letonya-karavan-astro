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

    init(clock: @escaping () -> Date = { Date() }) {
        self.clock = clock
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
            availableAudio: audio.downloadedAudioIds,
            seed: LatvianCourseRules.seed(now: now, counter: runCounter),
            now: now
        )
        guard !exercises.isEmpty else {
            actionNotice = "Bu durak için şu an soru hazırlanamadı."
            return
        }

        actionNotice = nil
        lesson = LatvianLessonRun(id: runCounter, sceneId: scene.id, exercises: exercises)
    }

    /// Dersin sonucunu hafızaya, XP'ye, seriye ve canlara işler; **kutlamadan
    /// önce** diske yazar. Uygulama kutlama ekranında öldürülse bile ders
    /// kaybolmuyor. İkinci çağrı hiçbir şey yapmıyor: `lesson` ilk turda düşüyor.
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
        if !outcome.isFailed { progress.registerLessonCompleted(now: now) }
        let streakExtended = progress.lastLessonDay != previousDay

        recordClearedScenes(now: now)
        persist()
        refreshDerived(now: now)

        lesson = nil
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
    }

    func dismissActionNotice() { actionNotice = nil }

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
            return
        }
        let computed = LatvianCourseRules.stops(pack: pack, progress: progress, now: now)
        if computed != stops { stops = computed }
        let current = LatvianCourseRules.currentStopId(in: computed)
        if current != currentStopId { currentStopId = current }
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
