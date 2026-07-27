import Foundation

/// Bir ders hedefinin nereden geldiği. Kota denetimi ve hata ayıklama için.
enum LatvianLessonSource: String, Hashable, Sendable {
    /// Sahnenin henüz oturmamış kelimesi.
    case new
    /// Tekrar zamanı gelmiş kart.
    case review
    /// Son derslerde yanlış yapılan kelime.
    case mistake
    /// Kotalar tükendikten sonra sahne kelimeleriyle yapılan tamamlama.
    case filler
}

/// Derste sorulacak tek bir hedef: hangi kelime, hangi tarafından.
/// Hedef "kelime" değil "kelime + modalite": sahne kilidi tanıma ve üretim
/// taraflarını ayrı ayrı istediğinden, ders kurgusu da ikisini ayrı ayrı beslemeli.
struct LatvianLessonTarget: Hashable, Sendable {
    let wordId: String
    let modality: LatvianModality
    let source: LatvianLessonSource

    /// Tekilleştirme ve parmak izi için düz metin karşılık.
    var debugKey: String { "\(wordId)#\(modality.rawValue)#\(source.rawValue)" }

    fileprivate var pairKey: String { "\(wordId)#\(modality.rawValue)" }
}

/// Ders kurgusu ve sahne kilidi.
///
/// Sahne kilidi tek bir cümleyle: bir sahne, kelimelerinin en az `masteryCoverage`
/// kadarı **hem tanıma hem üretim** kartında `masteryThreshold` hatırlanma olasılığını
/// geçtiğinde tamamlanmış sayılır. "N ders yaptın, geç" değil, "gerçekten biliyor musun".
///
/// `LatvianDefaultScheduler` ile bu eşik tam olarak "kartın vadesi henüz gelmedi"
/// demek: planlayıcı bir sonraki tekrarı, hatırlanma olasılığının 0.9'a düştüğü ana
/// koyuyor. Yani hakimiyet, vadesi gelmemiş iki kartla eşdeğer.
enum LatvianLessonBuilder {
    static let lessonLength = 16
    /// Bir kartın öğrenilmiş sayılması için gereken hatırlama olasılığı.
    static let masteryThreshold = 0.9
    /// Sahnenin tamamlanması için bu orandaki kelime eşiği geçmeli.
    static let masteryCoverage = 0.8

    private static let newShare = 0.5
    private static let reviewShare = 0.3

    /// Yeni malzeme kotası (%50).
    static let newQuota = Int((Double(lessonLength) * newShare).rounded())
    /// Aralıklı tekrar kotası (%30).
    static let reviewQuota = Int((Double(lessonLength) * reviewShare).rounded())
    /// Son hatalar kotası (%20); kalanı alıyor ki üçü her zaman `lessonLength` etsin.
    static let mistakeQuota = max(0, lessonLength - newQuota - reviewQuota)

    private static let modalities: [LatvianModality] = [.recognition, .production]

    // MARK: - Hakimiyet

    /// Tek bir kartın eşiği geçip geçmediği. Kart hiç yoksa geçmemiş sayılır.
    static func isMastered(
        wordId: String,
        modality: LatvianModality,
        progress: LatvianProgress,
        now: Date
    ) -> Bool {
        guard let key = LatvianMemoryKey(wordId: wordId, modality: modality),
              let card = progress.card(for: key) else { return false }
        return card.retrievability(at: now) >= masteryThreshold
    }

    /// Kelimenin **iki** tarafı da eşiği geçti mi.
    static func isWordMastered(wordId: String, progress: LatvianProgress, now: Date) -> Bool {
        modalities.allSatisfy {
            isMastered(wordId: wordId, modality: $0, progress: progress, now: now)
        }
    }

    /// Sahnedeki kelimelerin kaçının hem tanıma hem üretim tarafında eşiği geçtiği.
    static func masteryRatio(scene: LatvianScene, progress: LatvianProgress, now: Date) -> Double {
        let words = distinctWordIds(in: scene)
        guard !words.isEmpty else { return 1 }
        let mastered = words.filter { isWordMastered(wordId: $0, progress: progress, now: now) }
        return Double(mastered.count) / Double(words.count)
    }

    static func isSceneMastered(scene: LatvianScene, progress: LatvianProgress, now: Date) -> Bool {
        masteryRatio(scene: scene, progress: progress, now: now) >= masteryCoverage
    }

    /// Sahne bir kez geçildi mi. Şu an hakim olmak ya da geçmişte tamamlamış olmak yeter.
    ///
    /// Tamamlanma kaydı olmadan yalnızca anlık hakimiyete bakmak, iki hafta ara veren
    /// öğrencinin ilerlediği sahneleri geri kilitlerdi. Unutulan malzeme zaten aralıklı
    /// tekrar kotasıyla derse geri geliyor; kilidi geri kapatmanın öğretici bir karşılığı yok.
    static func isSceneCleared(scene: LatvianScene, progress: LatvianProgress, now: Date) -> Bool {
        progress.hasCompleted(sceneId: scene.id)
            || isSceneMastered(scene: scene, progress: progress, now: now)
    }

    /// Bir sahne, kendisinden önceki tüm sahneler geçildiyse açılır.
    static func isSceneUnlocked(
        scene: LatvianScene,
        pack: LatvianPack,
        progress: LatvianProgress,
        now: Date
    ) -> Bool {
        pack.scenes
            .filter { $0.index < scene.index }
            .allSatisfy { isSceneCleared(scene: $0, progress: progress, now: now) }
    }

    // MARK: - Plan

    /// Dersin hedeflerini seçer: %50 yeni, %30 tekrar, %20 son hatalar.
    ///
    /// Havuzlardan biri boşsa kotası diğerlerine devrediliyor, en sonda da sahnenin
    /// kendi kelimeleriyle tamamlanıyor; ders her zaman `lessonLength` hedefe ulaşıyor.
    /// Sahnenin hiç kelimesi yoksa boş dönüyor.
    ///
    /// Kotalar sırayla değil, "önce yeni, sonra hata, sonra tekrar" sırasıyla dolduruluyor:
    /// son yapılan hatanın kartı zaten vadesi gelmiş olduğundan, tekrar havuzu önce
    /// çalıştırılsa hata kotası hep boş kalır ve kompozisyon sessizce %50/%50'ye kayardı.
    static func plan(
        scene: LatvianScene,
        pack: LatvianPack,
        progress: LatvianProgress,
        now: Date
    ) -> [LatvianLessonTarget] {
        let words = distinctWords(in: scene)
        guard !words.isEmpty else { return [] }

        let newPool = newPool(words: words, progress: progress, now: now)
        let mistakePool = mistakePool(pack: pack, progress: progress, now: now)
        let reviewPool = reviewPool(pack: pack, progress: progress, now: now)
        let scenePool = scenePool(words: words)

        var picks: [LatvianLessonTarget] = []
        // Yalnızca üyelik testi için; üzerinde gezilmiyor, dolayısıyla sırası çıktıyı etkilemiyor.
        var used: Set<String> = []

        func drain(_ pool: [(String, LatvianModality)], source: LatvianLessonSource, limit: Int) {
            var taken = 0
            for entry in pool {
                guard taken < limit, picks.count < lessonLength else { return }
                let target = LatvianLessonTarget(wordId: entry.0, modality: entry.1, source: source)
                guard used.insert(target.pairKey).inserted else { continue }
                picks.append(target)
                taken += 1
            }
        }

        drain(newPool, source: .new, limit: newQuota)
        drain(mistakePool, source: .mistake, limit: mistakeQuota)
        drain(reviewPool, source: .review, limit: reviewQuota)

        // Boş kalan kotalar devrediyor.
        drain(newPool, source: .new, limit: lessonLength)
        drain(reviewPool, source: .review, limit: lessonLength)
        drain(mistakePool, source: .mistake, limit: lessonLength)
        drain(scenePool, source: .filler, limit: lessonLength)

        // Sahne 16 ayrı kelime-modalite ikilisi çıkaramayacak kadar küçükse tekrara izin var.
        var cursor = 0
        while picks.count < lessonLength {
            let entry = scenePool[cursor % scenePool.count]
            picks.append(LatvianLessonTarget(wordId: entry.0, modality: entry.1, source: .filler))
            cursor += 1
        }

        return picks
    }

    // MARK: - Ders

    static func build(
        scene: LatvianScene,
        pack: LatvianPack,
        progress: LatvianProgress,
        factory: LatvianExerciseFactory,
        availableAudio: Set<String>,
        seed: UInt64,
        now: Date
    ) -> [LatvianExercise] {
        let targets = plan(scene: scene, pack: pack, progress: progress, now: now)
        guard !targets.isEmpty else { return [] }

        var generator = LatvianSeededGenerator(seed: seed)
        var slots: [Slot] = []
        slots.reserveCapacity(targets.count)
        for target in targets {
            let kinds = orderedKinds(
                for: target, factory: factory, availableAudio: availableAudio, using: &generator
            )
            if !kinds.isEmpty { slots.append(Slot(target: target, kinds: kinds)) }
        }

        var result: [LatvianExercise] = []
        var usedIds: Set<String> = []

        while result.count < lessonLength, !slots.isEmpty {
            guard let choice = select(from: slots, after: result.last) else { break }
            let slot = slots[choice.slot]
            let exerciseSeed = seed
                &+ UInt64(result.count) &* 7919
                &+ kindOffset(choice.kind)

            guard let exercise = factory.makeExercise(
                wordId: slot.target.wordId,
                kind: choice.kind,
                seed: exerciseSeed,
                availableAudio: availableAudio
            ), usedIds.insert(exercise.id).inserted else {
                // `supportedKinds` bu tipin üretilebilir olduğunu söylemişti; yine de
                // üretilemediyse tipi düşürüp devam ediyoruz. Her tur en az bir tip
                // eksiltiyor, dolayısıyla döngü sonlanıyor.
                slots[choice.slot].kinds.removeAll { $0 == choice.kind }
                if slots[choice.slot].kinds.isEmpty { slots.remove(at: choice.slot) }
                continue
            }

            result.append(exercise)
            slots.remove(at: choice.slot)
        }

        return result
    }

    // MARK: - Havuzlar

    private static func distinctWords(in scene: LatvianScene) -> [LatvianWord] {
        var seen: Set<String> = []
        var result: [LatvianWord] = []
        for word in scene.words where seen.insert(word.id).inserted { result.append(word) }
        return result
    }

    private static func distinctWordIds(in scene: LatvianScene) -> [String] {
        distinctWords(in: scene).map(\.id)
    }

    /// Sahnenin henüz oturmamış kelimeleri; her kelimenin eksik tarafları peş peşe.
    ///
    /// İki tuzak var, ikisi de sahneyi sonsuza dek kilitli bırakıyor:
    ///
    /// - **Yalnızca tanıma kartına bakmak.** Tanıma eşiği geçen kelime havuzdan düşer,
    ///   üretim kartı hiç açılmaz, sahne iki taraf birden istediği için asla tamamlanmaz.
    /// - **Önce tüm tanımaları, sonra tüm üretimleri sıralamak.** Bu, ilk dersi
    ///   on altı yeni kelimeye çeviriyor ve üretim tarafını sahnenin sonuna itiyor.
    ///
    /// Bunun yerine kelime kelime ilerleniyor: bir ders sekiz yeni kelime tanıtıyor ve
    /// her birini hem tanıma hem üretim tarafından soruyor.
    private static func newPool(
        words: [LatvianWord],
        progress: LatvianProgress,
        now: Date
    ) -> [(String, LatvianModality)] {
        // Sık kelime önce; `freqRank` paketin büyük kısmında 0 olduğundan eşitlik
        // sahnedeki sırayla bozuluyor (kararlı, belirlenimci sıra).
        let ordered = words.enumerated()
            .sorted { left, right in
                if left.element.freqRank != right.element.freqRank {
                    return left.element.freqRank < right.element.freqRank
                }
                return left.offset < right.offset
            }
            .map(\.element)

        var result: [(String, LatvianModality)] = []
        for word in ordered {
            for modality in modalities
            where !isMastered(wordId: word.id, modality: modality, progress: progress, now: now) {
                result.append((word.id, modality))
            }
        }
        return result
    }

    /// Tekrar zamanı gelmiş kartlar; sahne farketmeksizin, en zayıf hatırlanan başta.
    /// Paketten kalkmış kelimelerin eski kartları eleniyor.
    private static func reviewPool(
        pack: LatvianPack,
        progress: LatvianProgress,
        now: Date
    ) -> [(String, LatvianModality)] {
        progress.dueEntries(now: now)
            .filter { pack.word(id: $0.key.wordId) != nil }
            .map { ($0.key.wordId, $0.key.modality) }
    }

    /// Son derslerde yanlış yapılan kelimeler, en yenisi başta.
    /// Hata listesi modaliteyi tutmadığından kelimenin zayıf tarafı seçiliyor.
    private static func mistakePool(
        pack: LatvianPack,
        progress: LatvianProgress,
        now: Date
    ) -> [(String, LatvianModality)] {
        progress.recentMistakes.reversed()
            .filter { pack.word(id: $0) != nil }
            .map { ($0, weakestModality(wordId: $0, progress: progress, now: now)) }
    }

    /// Sahnenin tüm kelime-modalite ikilileri, tanıma/üretim dönüşümlü.
    private static func scenePool(words: [LatvianWord]) -> [(String, LatvianModality)] {
        var result: [(String, LatvianModality)] = []
        result.reserveCapacity(words.count * modalities.count)
        for word in words {
            for modality in modalities { result.append((word.id, modality)) }
        }
        return result
    }

    private static func weakestModality(
        wordId: String,
        progress: LatvianProgress,
        now: Date
    ) -> LatvianModality {
        let recognition = LatvianMemoryKey(wordId: wordId, modality: .recognition)
            .flatMap { progress.card(for: $0)?.retrievability(at: now) } ?? 0
        let production = LatvianMemoryKey(wordId: wordId, modality: .production)
            .flatMap { progress.card(for: $0)?.retrievability(at: now) } ?? 0
        return production < recognition ? .production : .recognition
    }

    // MARK: - Soru seçimi

    private struct Slot {
        let target: LatvianLessonTarget
        var kinds: [LatvianExerciseKind]
    }

    /// Hedefin modalitesine uyan tipler önce, kalanlar yedek olarak arkada.
    ///
    /// Yedekler duruyor çünkü bir kelime her modalitede soru üretemeyebilir (sesi
    /// inmemiş ve cümlesi olmayan bir kelimenin üretim tarafı yoktur); o durumda
    /// yuvayı boş bırakmaktansa diğer taraftan soru sormak daha iyi.
    private static func orderedKinds(
        for target: LatvianLessonTarget,
        factory: LatvianExerciseFactory,
        availableAudio: Set<String>,
        using generator: inout LatvianSeededGenerator
    ) -> [LatvianExerciseKind] {
        var kinds = factory.supportedKinds(forWordId: target.wordId, availableAudio: availableAudio)
        guard !kinds.isEmpty else { return [] }
        kinds.shuffle(using: &generator)
        // `filter` diziyi sırasıyla geziyor; sonuç karıştırmanın kararlı bir bölünmesi.
        return kinds.filter { $0.modality == target.modality }
            + kinds.filter { $0.modality != target.modality }
    }

    /// Sıradaki soruyu seçer: ardışık iki soru ne aynı tipte ne aynı kelime üzerine olmalı.
    ///
    /// Tercih sırası kademeli, çünkü küçük bir sahnede ikisini birden tutturmak
    /// imkânsız olabiliyor. Kelime tekrarı tip tekrarından daha kötü (öğrenci aynı
    /// kelimeyi arka arkaya görür), bu yüzden ikinci kademe kelimeyi ayırıyor.
    ///
    /// Yalnızca metaveriye bakıyor: soru üretmek pahalı, dört kademeyi soru üreterek
    /// taramak ders başına binlerce üretim demek olurdu.
    private static func select(
        from slots: [Slot],
        after previous: LatvianExercise?
    ) -> (slot: Int, kind: LatvianExerciseKind)? {
        guard let previous else {
            for (index, slot) in slots.enumerated() {
                if let kind = slot.kinds.first { return (index, kind) }
            }
            return nil
        }

        // 1. Hem kelime hem tip farklı.
        for (index, slot) in slots.enumerated() where slot.target.wordId != previous.targetWordId {
            if let kind = slot.kinds.first(where: { $0 != previous.kind }) { return (index, kind) }
        }
        // 2. En azından kelime farklı.
        for (index, slot) in slots.enumerated() where slot.target.wordId != previous.targetWordId {
            if let kind = slot.kinds.first { return (index, kind) }
        }
        // 3. En azından tip farklı.
        for (index, slot) in slots.enumerated() {
            if let kind = slot.kinds.first(where: { $0 != previous.kind }) { return (index, kind) }
        }
        // 4. Son çare: eldeki ilk soru.
        for (index, slot) in slots.enumerated() {
            if let kind = slot.kinds.first { return (index, kind) }
        }
        return nil
    }

    /// Aynı kelime ve tip derste iki kez çıkabildiğinden (küçük sahne), tohum soru
    /// sırasını da içeriyor; böylece iki soru aynı kimliğe düşmüyor.
    private static func kindOffset(_ kind: LatvianExerciseKind) -> UInt64 {
        UInt64((LatvianExerciseKind.allCases.firstIndex(of: kind) ?? 0) + 1) &* 31
    }
}
