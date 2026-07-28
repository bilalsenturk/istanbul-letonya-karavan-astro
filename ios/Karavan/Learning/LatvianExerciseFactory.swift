import Foundation

/// Tohumlanmış, taşınabilir rastgele sayı üreteci.
/// `SystemRandomNumberGenerator` kullanılmıyor çünkü aynı tohum aynı dersi vermeli.
struct LatvianSeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        if state == 0 { state = 0x9E3779B97F4A7C15 }
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

struct LatvianExerciseFactory {
    let pack: LatvianPack

    /// Ders kurulumu `supportedKinds`'ı her kelime için çağırıyor; bu listeler her
    /// erişimde yeniden kurulursa (eskiden `allWords` hesaplanan bir özellikti ve çağrı
    /// başına birkaç kez okunuyordu) 259 kelimede onlarca milisaniye ana iş parçacığına
    /// biniyordu. Hepsi `init`'te bir kez, O(n) kuruluyor; tip değer tipi kalıyor.
    private let allWords: [LatvianWord]
    /// Çeldirici havuzları: paketteki yüzey metinleri, sırası korunarak tekilleştirilmiş.
    /// Paket aynı kelimeyi birden çok sahnede tekrarladığından (örn. "paldies" 8 kez)
    /// tekilleştirme şart, yoksa seçeneklerde iki özdeş kart belirebilir.
    /// `Set` yalnızca üyelik testinde kullanılıyor — `Array(Set(...))` gibi kümeden diziye
    /// dönüşüm yok, çünkü Swift'te `Set` sırası kararlı değildir (aynı süreç içinde bile)
    /// ve bu, "aynı tohum aynı soru" garantisini kırardı.
    private let distinctSurfaces: [String]
    private let distinctIconSurfaces: [String]
    private let sentencesByWordId: [String: [LatvianSentence]]

    init(pack: LatvianPack) {
        self.pack = pack

        let words = pack.scenes.flatMap(\.words)
        allWords = words

        // İki havuz ayrı ayrı tekilleştiriliyor: aynı yüzey metni önce emojisiz, sonra
        // emojili bir kayıtta geçebiliyor; tek geçişte tekilleştirmek emojili olanı
        // emoji havuzundan düşürürdü.
        var seenSurface: Set<String> = []
        var surfaces: [String] = []
        for word in words where seenSurface.insert(word.lv).inserted {
            surfaces.append(word.lv)
        }
        var seenIconSurface: Set<String> = []
        var iconSurfaces: [String] = []
        for word in words where word.icon != nil {
            if seenIconSurface.insert(word.lv).inserted { iconSurfaces.append(word.lv) }
        }
        distinctSurfaces = surfaces
        distinctIconSurfaces = iconSurfaces

        var index: [String: [LatvianSentence]] = [:]
        for scene in pack.scenes {
            for sentence in scene.sentences {
                // Bir cümle aynı kelime kimliğini iki kez listelese bile listeye bir kez
                // giriyor; eski `filter { $0.wordIds.contains(wordId) }` de böyleydi.
                // Sahne ve cümle sırası korunuyor — soru seçimi bu sıraya tohumlanıyor.
                var seen: Set<String> = []
                for wordId in sentence.wordIds where seen.insert(wordId).inserted {
                    index[wordId, default: []].append(sentence)
                }
            }
        }
        sentencesByWordId = index
    }

    func supportedKinds(forWordId wordId: String, availableAudio: Set<String>) -> [LatvianExerciseKind] {
        guard let word = pack.word(id: wordId) else { return [] }
        let sentences = sentencesUsing(wordId: wordId)
        return LatvianExerciseKind.allCases.filter {
            supports(kind: $0, word: word, sentences: sentences, availableAudio: availableAudio)
        }
    }

    /// Tek bir soru tipinin bu kelime için üretilebilir olup olmadığı.
    /// Hem `supportedKinds` hem `makeExercise` yalnızca bunu çağırıyor, dolayısıyla
    /// "destekleniyor dedi ama üretemedi" ayrışması olamıyor. `makeExercise` eskiden
    /// tek bir tipi doğrulamak için on tipin tamamını hesaplatıyordu.
    private func supports(
        kind: LatvianExerciseKind,
        word: LatvianWord,
        sentences: [LatvianSentence],
        availableAudio: Set<String>
    ) -> Bool {
        switch kind {
        case .listenChoose:
            return availableAudio.contains(word.audioId)
                && hasDistractor(correct: word.lv, pool: distinctSurfaces)
        case .dictation, .speak:
            return availableAudio.contains(word.audioId)
        case .iconChoose:
            guard word.icon != nil else { return false }
            return hasDistractor(correct: word.lv, pool: distinctIconSurfaces)
        case .caseDrill:
            guard let caseForm = word.caseForm,
                  caseDrillStem(caseForm) != nil,
                  hasDistractorSuffix(caseForm) else { return false }
            return sentences.contains { $0.supports.contains(.caseDrill) }
        case .match:
            return hasMatchCandidates(excluding: word, atLeast: 3)
        case .fillBlank:
            return sentences.contains { sentence in
                sentence.supports.contains(kind) && blank(sentence.lv, hiding: word.lv) != nil
            } && hasDistractor(correct: word.lv, pool: distinctSurfaces)
        case .lvToTr, .trToLv, .order:
            return sentences.contains { $0.supports.contains(kind) }
        }
    }

    func makeExercise(
        wordId: String,
        kind: LatvianExerciseKind,
        seed: UInt64,
        availableAudio: Set<String>
    ) -> LatvianExercise? {
        guard let word = pack.word(id: wordId),
              supports(
                  kind: kind,
                  word: word,
                  sentences: sentencesUsing(wordId: wordId),
                  availableAudio: availableAudio
              ) else { return nil }

        var generator = LatvianSeededGenerator(seed: seed)
        let id = "\(wordId)-\(kind.rawValue)-\(seed)"

        switch kind {
        case .listenChoose:
            guard let options = choiceOptions(correct: word.lv, distinctPool: distinctSurfaces, using: &generator) else { return nil }
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "Duyduğun kelimeyi seç.",
                audioId: word.audioId,
                content: .choice(options: options.values, correctIndex: options.correctIndex),
                answerGlossTr: word.tr,
                answerAudioId: playable(word.audioId, in: availableAudio)
            )

        case .iconChoose:
            guard let options = choiceOptions(correct: word.lv, distinctPool: distinctIconSurfaces, using: &generator) else { return nil }
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "\(word.icon ?? "") için doğru kelimeyi seç.",
                content: .choice(options: options.values, correctIndex: options.correctIndex),
                answerGlossTr: word.tr,
                answerAudioId: playable(word.audioId, in: availableAudio)
            )

        case .lvToTr:
            guard let sentence = pickSentence(wordId: wordId, kind: kind, using: &generator) else { return nil }
            let answer = sentence.tr.split(separator: " ").map(String.init)
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "Türkçesini kur.",
                content: .wordBank(bank: shuffledBank(answer, using: &generator), answer: answer),
                carrier: sentence.lv,
                // Cevabın kendisi zaten Türkçe; altına bir kez daha yazmak
                // aynı satırı iki kez göstermek olurdu.
                answerGlossTr: nil,
                answerAudioId: playable(sentence.audioId, in: availableAudio)
            )

        case .trToLv:
            guard let sentence = pickSentence(wordId: wordId, kind: kind, using: &generator) else { return nil }
            let answer = sentence.lv.split(separator: " ").map(String.init)
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "Letoncasını kur.",
                content: .wordBank(bank: shuffledBank(answer, using: &generator), answer: answer),
                carrier: sentence.tr,
                answerGlossTr: sentence.tr,
                answerAudioId: playable(sentence.audioId, in: availableAudio)
            )

        case .order:
            guard let sentence = pickSentence(wordId: wordId, kind: kind, using: &generator) else { return nil }
            let answer = sentence.lv.split(separator: " ").map(String.init)
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "Kelimeleri doğru sıraya diz.",
                content: .wordBank(bank: shuffledBank(answer, using: &generator), answer: answer),
                carrier: sentence.tr,
                answerGlossTr: sentence.tr,
                answerAudioId: playable(sentence.audioId, in: availableAudio)
            )

        case .fillBlank:
            // supportedKinds zaten "en az bir aday cümlede word.lv harfiyen geçiyor" şartını
            // doğruladı; ama adaylar arasında word.lv'yi barındırmayan başka bir eşleşen
            // cümle de olabileceğinden (aynı kelime birden çok cümlede geçebilir, biri
            // çekimli biri değil), rastgele seçim burada da aynı süzgeci uygulamalı —
            // yoksa supportedKinds "evet" derken makeExercise nil dönebilir.
            let candidates = sentencesUsing(wordId: wordId)
                .filter { $0.supports.contains(kind) && blank($0.lv, hiding: word.lv) != nil }
            guard !candidates.isEmpty else { return nil }
            let sentence = candidates[Int.random(in: 0..<candidates.count, using: &generator)]
            guard let blanked = blank(sentence.lv, hiding: word.lv) else { return nil }
            guard let options = choiceOptions(correct: word.lv, distinctPool: distinctSurfaces, using: &generator) else { return nil }
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "Boşluğa gelen kelimeyi seç.",
                content: .choice(options: options.values, correctIndex: options.correctIndex),
                carrier: blanked,
                answerGlossTr: sentence.tr,
                // Cevap boşluğa giren **kelime**, cümlenin tamamı değil; okunması
                // gereken de o kelime.
                answerAudioId: playable(word.audioId, in: availableAudio)
            )

        case .caseDrill:
            guard let caseForm = word.caseForm, let stem = caseDrillStem(caseForm) else { return nil }
            var distractorSuffixes = distinctDistractorSuffixes(caseForm)
            guard !distractorSuffixes.isEmpty else { return nil }
            distractorSuffixes.shuffle(using: &generator)
            var suffixes = [caseForm.suffix] + distractorSuffixes.prefix(2)
            suffixes.shuffle(using: &generator)
            guard let correctIndex = suffixes.firstIndex(of: caseForm.suffix) else { return nil }
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "Doğru eki seç.",
                content: .choice(options: suffixes, correctIndex: correctIndex),
                carrier: "\(stem)___",
                // Cevap çıplak bir ek ("u"); tek başına ne anlama geldiğini
                // söylemiyor. Çekimli biçimin tamamı ve Türkçesi birlikte veriliyor.
                answerGlossTr: "\(caseForm.form) — \(word.tr)",
                // Klip kelimenin sözlük biçimini okuyor, çekimli biçimi değil:
                // "kafija" çalıp "kafiju" öğretmek telaffuzu yanlış öğretirdi.
                answerAudioId: nil
            )

        case .dictation:
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "Duyduğunu yaz.",
                audioId: word.audioId,
                content: .typing(accepted: [word.lv]),
                answerGlossTr: word.tr,
                answerAudioId: playable(word.audioId, in: availableAudio)
            )

        case .speak:
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "Dinle ve tekrar et.",
                audioId: word.audioId,
                content: .speaking(target: word.lv),
                answerGlossTr: word.tr,
                answerAudioId: playable(word.audioId, in: availableAudio)
            )

        case .match:
            var pool = matchCandidates(excluding: word)
            guard pool.count >= 3 else { return nil }
            pool.shuffle(using: &generator)
            var pairs = [LatvianMatchPair(lv: word.lv, tr: word.tr)]
            pairs.append(contentsOf: pool.prefix(3).map { LatvianMatchPair(lv: $0.lv, tr: $0.tr) })
            guard pairs.count == 4 else { return nil }
            pairs.shuffle(using: &generator)
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "Letonca kelimeleri Türkçeleriyle eşleştir.",
                content: .matching(pairs: pairs),
                // Dört çiftin Türkçesi zaten cevabın içinde ("lūdzu → lütfen, …");
                // tek bir klip de dört kelimeyi birden okuyamaz.
                answerGlossTr: nil,
                answerAudioId: nil
            )
        }
    }

    // MARK: - Yardımcılar

    /// Klip gerçekten indiyse kimliği, inmediyse `nil`.
    ///
    /// Cevap panelindeki "Dinle" düğmesi bu alanın varlığına bakıp çiziliyor,
    /// dolayısıyla süzgeç burada: inmemiş bir klip için düğme çıkarsa öğrenci
    /// basar ve karşılığında yalnızca bir hata mesajı alır. Soruyu **elemiyor** —
    /// sesi olmayan bir `fillBlank` hâlâ geçerli bir soru, yalnızca dinlemesiz.
    ///
    /// Bilerek `supports(kind:…)` içinde kullanılmıyor: `supportedKinds` yolu
    /// ölçülen performans bütçesini taşıyor ve bu alanların soru üretilebilirliğe
    /// hiçbir etkisi yok.
    private func playable(_ audioId: String, in availableAudio: Set<String>) -> String? {
        availableAudio.contains(audioId) ? audioId : nil
    }

    private func sentencesUsing(wordId: String) -> [LatvianSentence] {
        sentencesByWordId[wordId] ?? []
    }

    private func pickSentence(
        wordId: String,
        kind: LatvianExerciseKind,
        using generator: inout LatvianSeededGenerator
    ) -> LatvianSentence? {
        let candidates = sentencesUsing(wordId: wordId)
            .filter { $0.supports.contains(kind) }
        guard !candidates.isEmpty else { return nil }
        return candidates[Int.random(in: 0..<candidates.count, using: &generator)]
    }

    /// Havuzda `correct`'ten farklı en az bir değer var mı? İlk farklı öğede duruyor.
    /// Yalnızca "en az bir çeldirici var mı?" sorusu için paketin tamamını tekilleştirip
    /// diziye yazmak `supportedKinds`'ın maliyetinin büyük kısmıydı.
    private func hasDistractor(correct: String, pool: [String]) -> Bool {
        pool.contains { $0 != correct }
    }

    /// `!distinctDistractorSuffixes(_:).isEmpty` ile aynı yanıt, liste kurmadan.
    private func hasDistractorSuffix(_ caseForm: LatvianCaseForm) -> Bool {
        caseForm.distractorSuffixes.contains { $0 != caseForm.suffix }
    }

    /// `matchCandidates(excluding:).count >= minimum` ile aynı yanıt, eşik dolunca duruyor.
    private func hasMatchCandidates(excluding word: LatvianWord, atLeast minimum: Int) -> Bool {
        guard minimum > 0 else { return true }
        var usedLv: Set<String> = [word.lv]
        var usedTr: Set<String> = [word.tr]
        var count = 0
        for candidate in allWords where candidate.id != word.id {
            guard !usedLv.contains(candidate.lv), !usedTr.contains(candidate.tr) else { continue }
            usedLv.insert(candidate.lv)
            usedTr.insert(candidate.tr)
            count += 1
            if count >= minimum { return true }
        }
        return false
    }

    /// Çekimli biçimden eki düşürerek gövdeyi verir.
    /// Ek, biçimin tamamı kadar (ya da daha) uzunsa geriye gövde kalmaz ve taşıyıcı
    /// çıplak bir `"___"` olurdu — öğrenciye hangi kelimenin çekildiğini söylemeyen,
    /// cevaplanamaz bir soru. Böyle bir çekim bilgisi hem `supports(kind:...)` hem
    /// `makeExercise` tarafından reddediliyor; ikisi de bu tek ölçüte bakıyor.
    private func caseDrillStem(_ caseForm: LatvianCaseForm) -> String? {
        guard caseForm.suffix.count < caseForm.form.count else { return nil }
        return String(caseForm.form.dropLast(caseForm.suffix.count))
    }

    /// Doğru cevap artı en fazla iki çeldiriciden oluşan seçenek listesi üretir.
    /// Havuzda hiç farklı çeldirici yoksa `nil` döner — soru her zaman aynı tek
    /// seçeneği "doğru" göstermek yerine hiç üretilmemeli.
    /// `distinctPool` `init`'te bir kez tekilleştirilmiş olmalı (bkz. `distinctSurfaces`);
    /// burada yalnızca doğru cevap düşülüyor.
    private func choiceOptions(
        correct: String,
        distinctPool: [String],
        using generator: inout LatvianSeededGenerator
    ) -> (values: [String], correctIndex: Int)? {
        var pickedDistractors = distinctPool.filter { $0 != correct }
        guard !pickedDistractors.isEmpty else { return nil }
        pickedDistractors.shuffle(using: &generator)
        var values = [correct] + pickedDistractors.prefix(2)
        values.shuffle(using: &generator)
        guard let correctIndex = values.firstIndex(of: correct) else { return nil }
        return (values, correctIndex)
    }

    /// Hedef kelimeyle çakışmayan (ne Letoncası ne Türkçesi aynı) eşleştirme adayları.
    /// Paket aynı kelimeyi birden çok sahnede farklı id'lerle tekrarladığından
    /// (örn. "lūdzu" 9 kez, "paldies" 8 kez), sadece id'ye göre hariç tutmak eşleştirme
    /// panosunda iki özdeş kartın belirmesine yol açabilirdi.
    private func matchCandidates(excluding word: LatvianWord) -> [LatvianWord] {
        var usedLv: Set<String> = [word.lv]
        var usedTr: Set<String> = [word.tr]
        var result: [LatvianWord] = []
        for candidate in allWords where candidate.id != word.id {
            guard !usedLv.contains(candidate.lv), !usedTr.contains(candidate.tr) else { continue }
            usedLv.insert(candidate.lv)
            usedTr.insert(candidate.tr)
            result.append(candidate)
        }
        return result
    }

    /// Doğru ekle çakışmayan, birbirinden farklı çeldirici ekler; kaynak sıra korunur
    /// (bkz. `distractors(correct:pool:)` üzerindeki not — aynı sebep burada da geçerli).
    private func distinctDistractorSuffixes(_ caseForm: LatvianCaseForm) -> [String] {
        var seen: Set<String> = [caseForm.suffix]
        var result: [String] = []
        for suffix in caseForm.distractorSuffixes where seen.insert(suffix).inserted {
            result.append(suffix)
        }
        return result
    }

    /// Cevabın kelimelerini karıştırıp kelime bankasını verir.
    ///
    /// Verilen söz: dönen dizi her zaman cevabın bir permütasyonudur. Karıştırma cevabın
    /// kendisine denk gelirse soru anlamsızlaşacağı için en fazla sekiz deneme yapılır ve
    /// cevaptan farklı olan ilk dizilim döner.
    ///
    /// Verilmeyen söz — "her zaman cevaptan farklıdır" **garanti edilemez**, çünkü bazı
    /// girdilerde farklı bir dizilim yoktur ya da yedeğe düşülür:
    /// - Tüm kelimeleri özdeş bir cevapta (örn. `["nē", "nē"]`) cevaptan farklı bir
    ///   permütasyon matematiksel olarak yoktur; sekiz deneme de cevabı verir ve
    ///   `reversed()` yedeği de cevaba eşittir. Dönen dizi cevabın kendisidir.
    /// - Sekiz denemenin tamamı cevaba denk gelirse `reversed()` yedeği devreye girer;
    ///   kelime dizisi palindromsa (örn. `["te", "nē", "te"]`) bu yedek de cevaba eşittir.
    ///   Bu yola pratikte düşülmez (n ≥ 2 için olasılık ≤ 2⁻⁸) ama bir garanti değildir.
    ///
    /// Bu iki durumu "karıştırılmış gibi" gösteren sahte bir dizilim üretmek çözüm değil:
    /// banka cevabın permütasyonu olmak zorunda, ve olmayan bir permütasyon uydurulamaz.
    /// Paketteki cümlelerin hiçbiri bu iki biçimde değil; tarama testi bunu her koşuda
    /// doğruluyor.
    private func shuffledBank(
        _ answer: [String],
        using generator: inout LatvianSeededGenerator
    ) -> [String] {
        guard answer.count > 1 else { return answer }
        var bank = answer
        for _ in 0..<8 {
            bank.shuffle(using: &generator)
            if bank != answer { return bank }
        }
        return bank.reversed()
    }

    /// Hedef kelimenin cümledeki **her** geçişini boşluğa çevirir; hiç geçmiyorsa `nil`.
    ///
    /// Yalnızca ilk geçişi gizlemek, kelimenin iki kez geçtiği bir cümlede cevabı ekranda
    /// bırakırdı: "Sveiki, sveiki, kā jums iet?" içinde `sveiki` gizlenince taşıyıcı
    /// "___ sveiki, kā jums iet?" oluyordu — öğrenci cevabı okuyordu. Aynı kelimenin iki
    /// boşluğu birden doldurması geçerli bir soru; cevabı okutmak değil.
    private func blank(_ sentence: String, hiding word: String) -> String? {
        let target = LatvianGrader.normalize(word)
        var blanked: [String] = []
        var didBlank = false
        for token in sentence.split(separator: " ") {
            if LatvianGrader.normalize(String(token)) == target {
                blanked.append("___")
                didBlank = true
            } else {
                blanked.append(String(token))
            }
        }
        guard didBlank else { return nil }
        return blanked.joined(separator: " ")
    }
}
