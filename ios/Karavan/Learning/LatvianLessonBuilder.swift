import Foundation

/// Bir ders hedefinin nereden geldiği. Kota denetimi ve hata ayıklama için.
enum LatvianLessonSource: String, Hashable, Sendable {
    /// Sahnenin henüz oturmamış kelimesi.
    case new
    /// Tekrar zamanı gelmiş kart.
    case review
    /// Son derslerde yanlış yapılan kelime.
    case mistake
    /// Defalarca unutulmuş, kalıcılığa bir türlü ulaşamamış kelime ("leech"):
    /// yeniden sınanmıyor, yeniden öğretiliyor.
    case leech
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
/// kadarı **hem tanıma hem üretim** kartında *kalıcı* olarak öğrenildiğinde tamamlanmış
/// sayılır. "N ders yaptın, geç" değil, "gerçekten biliyor musun".
///
/// Kalıcılık kartın **kararlılığından** okunuyor. Kararlılık FSRS'in tanımı gereği zaten
/// tam olarak aradığımız sayı: "kart görülmeden kaç gün geçerse hatırlanma olasılığı
/// %90'a iner". `stability >= masteryStabilityDays` demek, "öğrenci bu kelimeyi bu kadar
/// gün hiç görmese bile hatırlardı" demek. Yanına ikinci bir koşul konuyor —
/// `reviewCount >= minimumReviews` — çünkü tek bir cevaptan çıkarılan kalıcılık tesadüf
/// olabilir; kalıcılık ayrı ayrı karşılaşmalarda gösterilmeli.
///
/// **Neden anlık hatırlama olasılığı değil.** Önceki ölçüt
/// `retrievability(at: now + 3 gün) >= 0.9` idi; bu, `S >= (son tekrardan beri geçen gün) + 3`
/// demeye geliyordu. FSRS bir sonraki tekrarı tam olarak `geçen gün = S` anına koyduğundan
/// (hedef %90 hatırlama), vadesi geldiğinde çalışılan bir kart kapıya göre yapısal olarak
/// üç gün geride kalıyordu: kapı planlayıcının kendi tanımıyla dövüşüyordu. Ölçüldü —
/// dört soruda birini yanlış yapan öğrenci gerçek FSRS ile 400 oturumda bile birinci
/// sahneyi açamıyordu (bkz. `.superpowers/sdd/p2-task-7-report.md`). Kararlılık ölçütü
/// hem ufku hem eşiği içine aldığı için ikisi de kaldırıldı.
///
/// Ölçüt artık saati **okumuyor**: kararlılık kartın kendi durumunda duran, zamandan
/// bağımsız bir sayı. `now` imzalarda duruyor ki sahne sorguları ders kurgusuyla aynı
/// "şu an" etrafında toplansın; sonucu değiştirmediği testlerde ayrıca sınanıyor.
enum LatvianLessonBuilder {
    static let lessonLength = 16
    /// Kart taze mi: bu olasılığın üstündeki kart "az önce doğru cevaplandı" sayılıyor.
    /// Hakimiyet ölçütü değil, yeni malzeme süzgeci — bkz. `newPool`.
    static let freshnessThreshold = 0.9
    /// Sahneyi biliyor mu: kelimelerinin bu kadarı geçmeden sahne kapanmıyor.
    static let masteryCoverage = 0.8
    /// Kalıcı mı: kart bu kadar gün hiç görülmese bile hatırlanabilecek durumda olmalı.
    ///
    /// Değer taramayla seçildi (3/5/7/10/14/21 gün, iki planlayıcı, dört öğrenci profili;
    /// tablo `.superpowers/sdd/p2-task-7-report.md` içinde). Belirleyici olan yapısal
    /// sınır: gerçek FSRS'te zaman geçmeden yapılan tekrar kararlılığı büyütmüyor —
    /// hatırlanma tavandayken kazanç çarpanı sıfıra gidiyor — dolayısıyla tek oturumda
    /// ulaşılabilecek en yüksek kararlılık, ilk `easy` cevabın verdiği **5.8 gün**.
    /// Eşiği bunun üstüne koymak "tek oturumda sahne bitmez" güvencesini ders kurgusunun
    /// tesadüfüne değil algoritmanın kendisine bağlıyor; 7 gün, taramada bu şartı sağlayan
    /// en küçük değer. Daha küçük eşikler (3 gün) ise defalarca unutulmuş kartları —
    /// FSRS'in zorluğu 10'a dayanmış, kararlılığı 3-5 gün bandında takılı kalan kartlarını —
    /// hakim saydığı için ölçütü anlamsızlaştırıyordu.
    static let masteryStabilityDays = 7.0
    /// Tesadüf mü: bir kart bu kadar ayrı tekrar görmeden hakim sayılmıyor.
    static let minimumReviews = 2
    /// Takıldı mı: kart bu kadar kez unutulduğu hâlde hâlâ kalıcı olamadıysa "leech" sayılıyor.
    ///
    /// Soru "kaç kez yanlış yaptı" değil, "kaç kez yanlış yapmasına rağmen hiçbir yere
    /// varamadı". Bu yüzden ölçüt iki parçalı — sayaç **ve** kararlılık (bkz. `isLeech`):
    /// dört kez unutulup sonra oturmuş bir kelime takılmış değildir, tekrar kuyruğunun
    /// normal işidir. Dört, hem "iki kere şanssızlıktı" diyebilecek kadar büyük hem de
    /// bir kartın kurtarılamaz hale gelmesini beklemeyecek kadar küçük; Anki'nin sekizlik
    /// varsayılanından düşük tutuldu çünkü buradaki kurtarma kartı askıya almıyor,
    /// yalnızca daha kolay bir soruya indiriyor — yanlış teşhisin bedeli çok daha ucuz.
    static let leechLapseThreshold = 4

    private static let newShare = 0.5
    private static let reviewShare = 0.3

    /// Yeni malzeme kotası (%50).
    static let newQuota = Int((Double(lessonLength) * newShare).rounded())
    /// Aralıklı tekrar kotası (%30).
    static let reviewQuota = Int((Double(lessonLength) * reviewShare).rounded())
    /// Son hatalar kotası (%20); kalanı alıyor ki üçü her zaman `lessonLength` etsin.
    static let mistakeQuota = max(0, lessonLength - newQuota - reviewQuota)
    /// Kurtarma payı: takılan kelimelere ders başına ayrılan en fazla soru sayısı.
    ///
    /// Pay **yeni malzeme kotasından** kesiliyor, tekrar ya da hata kotasından değil:
    /// boğulmakta olan öğrenciye yeni kelime tanıtmak yanlış hamle, ama vadesi gelen
    /// kartı atlamak da öğrendiklerini kaybettirir. Takılan kelime yoksa kesinti sıfır
    /// ve kompozisyon bugünküyle birebir aynı kalıyor.
    ///
    /// Dört, on altı sorunun dörtte biri: ders başına bir soru "zaten olan ve işe
    /// yaramayan" durum (kelime normal tekrar kuyruğunda zaten o sıklıkta dönüyordu),
    /// yarım ders ise sahnede ilerlemeyi durdururdu.
    static let leechQuota = 4
    /// Kurtarma merdiveninin basamak sayısı: kart kalıcılığa yaklaştıkça soru zorlaşıyor.
    /// Kelimenin desteklediği tanıma tipi sayısı bundan azsa merdiven o kadar kısalıyor.
    private static let rescueSteps = 3

    private static let modalities: [LatvianModality] = [.recognition, .production]

    // MARK: - Hakimiyet

    /// Tek bir kartın kalıcı olarak öğrenilip öğrenilmediği. Kart hiç yoksa geçmemiş sayılır.
    ///
    /// İki koşul birden aranıyor: kartın kararlılığı `masteryStabilityDays` günü taşımalı
    /// **ve** kart en az `minimumReviews` kez tekrar edilmiş olmalı. Kararlılık tek başına
    /// yetmiyor, çünkü ilk cevabı `easy` verilen taze bir kart FSRS'te doğrudan yüksek bir
    /// kararlılıkla başlıyor; iki koşul birlikte "bir kez tutturmak" ile "biliyor olmak"
    /// arasındaki farkı koruyor.
    static func isMastered(
        wordId: String,
        modality: LatvianModality,
        progress: LatvianProgress,
        now: Date
    ) -> Bool {
        guard let key = LatvianMemoryKey(wordId: wordId, modality: modality),
              let card = progress.card(for: key),
              card.reviewCount >= minimumReviews else { return false }
        return card.stability >= masteryStabilityDays
    }

    /// Kelimenin **iki** tarafı da kalıcı olarak öğrenildi mi.
    static func isWordMastered(wordId: String, progress: LatvianProgress, now: Date) -> Bool {
        modalities.allSatisfy {
            isMastered(wordId: wordId, modality: $0, progress: progress, now: now)
        }
    }

    /// Sahnedeki kelimelerin kaçının hem tanıma hem üretim tarafında kalıcı olarak öğrenildiği.
    static func masteryRatio(scene: LatvianScene, progress: LatvianProgress, now: Date) -> Double {
        let words = distinctWordIds(in: scene)
        guard !words.isEmpty else { return 1 }
        let mastered = words.filter { isWordMastered(wordId: $0, progress: progress, now: now) }
        return Double(mastered.count) / Double(words.count)
    }

    static func isSceneMastered(scene: LatvianScene, progress: LatvianProgress, now: Date) -> Bool {
        masteryRatio(scene: scene, progress: progress, now: now) >= masteryCoverage
    }

    // MARK: - Takılan kelime

    /// Kart takıldı mı: defalarca unutulmuş **ve** buna rağmen kalıcılığa ulaşamamış.
    ///
    /// Teşhis kartın kendi durumundan okunuyor, elle tutulan bir listeden değil; kart
    /// toparlanıp kararlılığı eşiği geçtiği anda teşhis kendiliğinden kalkıyor. İki koşul
    /// da şart: sayaç tek başına "zorlandı ama sonunda öğrendi"yi de yakalardı, kararlılık
    /// tek başına henüz yeni tanışılmış her kelimeyi yakalardı.
    ///
    /// Gerçek FSRS'te bu durumun imzası nettir: zorluk 10'a dayanır, `(11 − D)` çarpanı 1'e
    /// iner ve kart her doğru cevapla biraz büyüyüp her yanlışta 2-4 güne düşerek orada kalır.
    /// Ölçüldü: sabit %25 hata altında sahnenin 23 kelimesinden 7-8'i buraya düşüyor ve
    /// hakimiyet kapsaması 0.61'de tıkanıyor (bkz. `.superpowers/sdd/p2-task-7-report.md`).
    /// Saat okunmuyor — iki alan da kartın üstünde duran, zamandan bağımsız sayılar.
    static func isLeech(card: LatvianMemoryCard) -> Bool {
        card.lapseCount >= leechLapseThreshold && card.stability < masteryStabilityDays
    }

    /// Kelimenin herhangi bir tarafı takıldıysa kelime takılmış sayılıyor.
    /// Kurtarma kelime bazında çalışıyor: takılan üretim kartının çaresi, kelimenin
    /// çağrışımını tanıma tarafından yeniden kurmak.
    static func isLeech(wordId: String, progress: LatvianProgress) -> Bool {
        modalities.contains { modality in
            LatvianMemoryKey(wordId: wordId, modality: modality)
                .flatMap { progress.card(for: $0) }
                .map { isLeech(card: $0) } ?? false
        }
    }

    /// Sahne bir kez geçildi mi. Şu an hakim olmak ya da geçmişte tamamlamış olmak yeter.
    ///
    /// Tamamlanma kaydı hâlâ gerekli: kararlılık zamanla düşmüyor ama **yanlış cevapla
    /// çöküyor**. Aradan sonra dönen öğrenci birkaç kelimeyi unutup yanlış cevaplarsa
    /// hakimiyet oranı eşiğin altına inebilir; kayıt olmadan bu, geçilmiş sahnelerin geri
    /// kilitlenmesi demek olurdu. Unutulan malzeme zaten aralıklı tekrar kotasıyla derse
    /// geri geliyor; kilidi geri kapatmanın öğretici bir karşılığı yok.
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
    ///
    /// Bunların önünde bir kota daha var: **kurtarma**. Takılan kelime (bkz. `isLeech`)
    /// olağan sıraya bırakılırsa on beş sorunun arasında bir kez daha görünür, bir kez daha
    /// yanlış cevaplanır ve bir kez daha çöker — yani hâlihazırda çalışmayan durum. Bu
    /// yüzden kurtarma hem ilk sırada hem kendi payıyla dolduruluyor; pay yeni malzeme
    /// kotasından kesiliyor. Takılan kelime yoksa kesinti sıfır: kompozisyon aynen kalıyor.
    static func plan(
        scene: LatvianScene,
        pack: LatvianPack,
        progress: LatvianProgress,
        now: Date
    ) -> [LatvianLessonTarget] {
        let words = distinctWords(in: scene)
        guard !words.isEmpty else { return [] }

        // Hafıza ders başına bir kez geziliyor: hem kurtarma havuzu hem tekrar kuyruğu
        // aynı listeden besleniyor (`allCards()` her anahtarı dizeden geri çözüyor).
        let entries = progress.allCards()
        let leechPool = leechPool(pack: pack, entries: entries)
        // Yalnızca üyelik testi için; üzerinde gezilmiyor.
        let leechWords = Set(leechPool.map(\.0))
        let newPool = newPool(words: words, progress: progress, leeches: leechWords, now: now)
        let mistakePool = mistakePool(pack: pack, progress: progress, now: now)
        let reviewPool = reviewPool(pack: pack, entries: entries, now: now)
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

        drain(leechPool, source: .leech, limit: leechQuota)
        // Kesinti havuzun boyundan değil gerçekten alınan yerden hesaplanıyor: tekilleştirme
        // yüzünden kurtarma payı tam dolmayabilir, o zaman yeni malzeme yerini korumalı.
        let rescued = picks.count
        drain(newPool, source: .new, limit: max(0, newQuota - rescued))
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
                for: target, factory: factory, availableAudio: availableAudio,
                progress: progress, using: &generator
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
    ///
    /// Süzgeç hakimiyet değil **tazelik** ölçüyor: taze kart aralıklı tekrar kotasına
    /// bırakılıyor, yeni malzeme kotası ilerlemeye harcanıyor. Hakimiyet süzgeci burada
    /// kullanılsaydı ders hep aynı ilk kelimelere dönerdi ve öğrenci aynı oturumda arka
    /// arkaya ders yaparak sahneyi bitirebilirdi — kapının kapattığı boşluk geri açılırdı.
    private static func newPool(
        words: [LatvianWord],
        progress: LatvianProgress,
        leeches: Set<String>,
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
        for word in ordered where !leeches.contains(word.id) {
            for modality in modalities
            where !isFresh(wordId: word.id, modality: modality, progress: progress, now: now) {
                result.append((word.id, modality))
            }
        }
        return result
    }

    /// Kartın **şu anda** taze olup olmadığı: az önce doğru cevaplanmış kart taze sayılıyor.
    /// Hakimiyetten farkı bilinçli — bkz. `newPool`.
    private static func isFresh(
        wordId: String,
        modality: LatvianModality,
        progress: LatvianProgress,
        now: Date
    ) -> Bool {
        guard let key = LatvianMemoryKey(wordId: wordId, modality: modality),
              let card = progress.card(for: key) else { return false }
        return card.retrievability(at: now) >= freshnessThreshold
    }

    /// Tekrar zamanı gelmiş kartlar; sahne farketmeksizin, en zayıf hatırlanan başta.
    /// Paketten kalkmış kelimelerin eski kartları eleniyor.
    ///
    /// **Takılan kart burada elenmiyor** — Anki'nin "leech'i askıya al" davranışı denendi
    /// ve ölçüldü: kötüleşti. Sebep, hakimiyet kapsamasının o kelimeleri de istemesi;
    /// kuyruktan çıkarmak onlara ders başına düşen soruyu azaltıyor. Askıya alma ölçümü
    /// gerçekçi öğrenciyi yer tutucuda 44 → 77 oturuma, gerçek FSRS'te en yüksek
    /// kapsamayı 0.65 → 0.57'ye götürdü. Kurtarma payı bu kartlara **ek** süre veriyor,
    /// var olan süreyi başka yere taşımıyor.
    private static func reviewPool(
        pack: LatvianPack,
        entries: [LatvianMemoryEntry],
        now: Date
    ) -> [(String, LatvianModality)] {
        LatvianProgress.dueEntries(from: entries, now: now)
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

    /// Takılan kelimeler, en çaresizi (kararlılığı en düşük kartı olan) başta.
    ///
    /// Hedefin modalitesi her zaman **tanıma**: kurtarma yeniden sınamak değil yeniden
    /// öğretmek, dolayısıyla kelime üretim tarafında takılmış olsa bile derse tanıma
    /// tarafından dönüyor (soru tipi seçimi için bkz. `rescueKinds`).
    ///
    /// Paketten kalkmış kelimelerin eski kartları eleniyor. Sıra belirlenimci: `allCards()`
    /// zaten `storageKey`'e göre sıralı geldiğinden ilk görülme sırası kararlı, sözlük
    /// yalnızca en küçük kararlılığı biriktirmek için kullanılıyor, üzerinde gezilmiyor.
    private static func leechPool(
        pack: LatvianPack,
        entries: [LatvianMemoryEntry]
    ) -> [(String, LatvianModality)] {
        var weakest: [String: Double] = [:]
        var order: [String] = []
        for entry in entries
        where isLeech(card: entry.card) && pack.word(id: entry.key.wordId) != nil {
            let wordId = entry.key.wordId
            if weakest[wordId] == nil {
                order.append(wordId)
                weakest[wordId] = entry.card.stability
            } else {
                weakest[wordId] = min(weakest[wordId] ?? 0, entry.card.stability)
            }
        }
        return order.enumerated()
            .sorted { left, right in
                let leftStability = weakest[left.element] ?? 0
                let rightStability = weakest[right.element] ?? 0
                if leftStability != rightStability { return leftStability < rightStability }
                return left.offset < right.offset
            }
            .map { ($0.element, LatvianModality.recognition) }
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
        progress: LatvianProgress,
        using generator: inout LatvianSeededGenerator
    ) -> [LatvianExerciseKind] {
        var kinds = factory.supportedKinds(forWordId: target.wordId, availableAudio: availableAudio)
        guard !kinds.isEmpty else { return [] }
        // Kurtarma karıştırılmıyor: tipin hangi sırayla geleceği tesadüfe değil kartın
        // durumuna bağlı olmalı.
        if target.source == .leech {
            return rescueKinds(wordId: target.wordId, supported: kinds, progress: progress)
        }
        kinds.shuffle(using: &generator)
        // `filter` diziyi sırasıyla geziyor; sonuç karıştırmanın kararlı bir bölünmesi.
        return kinds.filter { $0.modality == target.modality }
            + kinds.filter { $0.modality != target.modality }
    }

    /// Kurtarma merdiveni: takılan kelimenin hangi soruyla geri geleceği.
    ///
    /// Kelimenin desteklediği **tanıma** tipleri kolaydan zora diziliyor ve kart bu
    /// merdivenin bir basamağından derse dönüyor. Basamak kartın kendi kararlılığından
    /// okunuyor: dibe vurmuş kart en kolay sorudan (görselden/sesten dört seçenek)
    /// başlıyor, toparlandıkça bir üst basamağa çıkıyor, kararlılık `masteryStabilityDays`
    /// eşiğini geçtiğinde zaten takılmış sayılmadığı için olağan sıraya dönüyor. Yani
    /// mezuniyet ayrı bir kural değil, teşhisin kalkmasının doğal sonucu.
    ///
    /// Basamağın üstündeki tipler yedek olarak arkada duruyor — merdiven bir tercih sırası,
    /// bir yasak değil; `select` ardışık tekrarı kırmak için listede aşağı inebilmeli.
    /// Üretim tipleri en sona konuyor: kurtarma tam olarak onlardan kaçınmak için var,
    /// ama kelimenin hiç tanıma sorusu yoksa yuvayı boş bırakmaktansa onlar sorulur.
    private static func rescueKinds(
        wordId: String,
        supported: [LatvianExerciseKind],
        progress: LatvianProgress
    ) -> [LatvianExerciseKind] {
        let ladder = supported
            .filter { $0.modality == .recognition }
            .sorted { $0.difficultyRank < $1.difficultyRank }
        let harder = supported
            .filter { $0.modality != .recognition }
            .sorted { $0.difficultyRank < $1.difficultyRank }
        guard !ladder.isEmpty else { return harder }

        let stability = LatvianMemoryKey(wordId: wordId, modality: .recognition)
            .flatMap { progress.card(for: $0)?.stability } ?? 0
        // Oran `Int`'e çevrilmeden önce [0, 1] aralığına kırpılıyor. Kelime yalnızca üretim
        // tarafından takılmış olabilir; o zaman buradaki tanıma kartının kararlılığı çok
        // büyük olabilir (yer tutucu planlayıcıda 10^19 güne çıkabiliyor) ve kırpma olmadan
        // `Int(...)` taşıp süreci düşürürdü. `max(0, ...)` ayrıca NaN'ı sıfıra çekiyor.
        let reached = min(1, max(0, stability) / masteryStabilityDays)
        let step = min(Int(reached * Double(rescueSteps)), ladder.count - 1)
        return Array(ladder[step...]) + Array(ladder[..<step]) + harder
    }

    /// Sıradaki soruyu seçer: ardışık iki soru ne aynı tipte ne aynı kelime üzerine olmalı.
    ///
    /// Tercih sırası kademeli, çünkü küçük bir sahnede ikisini birden tutturmak
    /// imkânsız olabiliyor. Kelime tekrarı tip tekrarından daha kötü (öğrenci aynı
    /// kelimeyi arka arkaya görür), bu yüzden ikinci kademe kelimeyi ayırıyor.
    ///
    /// Yalnızca metaveriye bakıyor: soru üretmek pahalı, dört kademeyi soru üreterek
    /// taramak ders başına binlerce üretim demek olurdu.
    ///
    /// Bir kelimenin derste birden çok yuvası olabiliyor: yeni malzeme kotası bir kelimeyi
    /// iki modaliteden birden öğretiyor, tekrar kuyruğu da aynı kelimenin iki kartını yan
    /// yana verebiliyor. Açgözlü seçim "kelimesi farklı olan"ı her zaman tercih ettiğinden
    /// bu yuvalar dersin sonuna itiliyor; sonda başka kelime kalmayınca iki soru zorunlu
    /// olarak yan yana düşüyor. Kurtarma kotası eklendikten sonra ölçülen arıza tam olarak
    /// buydu (20 derslik izde bir çakışma).
    ///
    /// Çare, kalabalık kelimeyi **kısıt bağlamadan önce** araya sokmak. `k` yuvalı bir
    /// kelime `n` yuvanın içinde ancak `2k <= n` iken ayrık yerleştirilebilir; eşitlikte
    /// tek tek atlamalı diziliş kalır. O eşiğe gelindiğinde en kalabalık kelime öne
    /// alınıyor, öncesinde eski davranış aynen sürüyor — 16 yuvalı olağan bir derste koşul
    /// ancak son üç dört yuvada bağladığından sıralamanın tamamı bozulmuyor. (Bu ölçüldü:
    /// koşulsuz "önce kalabalık" sıralaması hata deseni konumsal olan benzetimlerde
    /// gereksiz oynamaya yol açıyordu.)
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

        // Kelime başına kalan yuva sayısı. Sözlük yalnızca sayaç; üzerinde gezilmiyor
        // (en büyük değer sayarken tutuluyor), dolayısıyla sırası çıktıya sızmıyor.
        var load: [String: Int] = [:]
        var crowdedLoad = 0
        for slot in slots {
            let count = (load[slot.target.wordId] ?? 0) + 1
            load[slot.target.wordId] = count
            crowdedLoad = max(crowdedLoad, count)
        }
        let mustSpread = crowdedLoad * 2 >= slots.count

        /// Kelimesi farklı ilk uygun yuva; kısıt bağlıyorsa aralarından en kalabalığı
        /// (eşitlikte yine en küçük dizinli).
        func pick(
            _ candidate: (Slot) -> LatvianExerciseKind?
        ) -> (slot: Int, kind: LatvianExerciseKind)? {
            var best: (slot: Int, kind: LatvianExerciseKind, load: Int)?
            for (index, slot) in slots.enumerated() where slot.target.wordId != previous.targetWordId {
                guard let kind = candidate(slot) else { continue }
                guard mustSpread else { return (index, kind) }
                let weight = load[slot.target.wordId] ?? 1
                if best == nil || weight > best!.load { best = (index, kind, weight) }
            }
            return best.map { ($0.slot, $0.kind) }
        }

        // 1. Hem kelime hem tip farklı.
        if let choice = pick({ $0.kinds.first(where: { $0 != previous.kind }) }) { return choice }
        // 2. En azından kelime farklı.
        if let choice = pick({ $0.kinds.first }) { return choice }
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
