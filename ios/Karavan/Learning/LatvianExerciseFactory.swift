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

    private var allWords: [LatvianWord] { pack.scenes.flatMap(\.words) }

    init(pack: LatvianPack) {
        self.pack = pack
    }

    func supportedKinds(forWordId wordId: String, availableAudio: Set<String>) -> [LatvianExerciseKind] {
        guard let word = pack.word(id: wordId) else { return [] }
        let hasAudio = availableAudio.contains(word.audioId)
        let sentences = sentencesUsing(wordId: wordId)

        return LatvianExerciseKind.allCases.filter { kind in
            switch kind {
            case .listenChoose:
                return hasAudio && !distractors(correct: word.lv, pool: allWords.map(\.lv)).isEmpty
            case .dictation, .speak:
                return hasAudio
            case .iconChoose:
                guard word.icon != nil else { return false }
                let iconPool = allWords.filter { $0.icon != nil }.map(\.lv)
                return !distractors(correct: word.lv, pool: iconPool).isEmpty
            case .caseDrill:
                guard let caseForm = word.caseForm,
                      !distinctDistractorSuffixes(caseForm).isEmpty else { return false }
                return sentences.contains { $0.supports.contains(.caseDrill) }
            case .match:
                return matchCandidates(excluding: word).count >= 3
            case .fillBlank:
                return sentences.contains { sentence in
                    sentence.supports.contains(kind) && blank(sentence.lv, hiding: word.lv) != nil
                } && !distractors(correct: word.lv, pool: allWords.map(\.lv)).isEmpty
            case .lvToTr, .trToLv, .order:
                return sentences.contains { $0.supports.contains(kind) }
            }
        }
    }

    func makeExercise(
        wordId: String,
        kind: LatvianExerciseKind,
        seed: UInt64,
        availableAudio: Set<String>
    ) -> LatvianExercise? {
        guard supportedKinds(forWordId: wordId, availableAudio: availableAudio).contains(kind),
              let word = pack.word(id: wordId) else { return nil }

        var generator = LatvianSeededGenerator(seed: seed)
        let id = "\(wordId)-\(kind.rawValue)-\(seed)"

        switch kind {
        case .listenChoose:
            guard let options = choiceOptions(correct: word.lv, pool: allWords.map(\.lv), using: &generator) else { return nil }
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "Duyduğun kelimeyi seç.",
                audioId: word.audioId,
                content: .choice(options: options.values, correctIndex: options.correctIndex),
                explanation: "\(word.lv) — \(word.tr)"
            )

        case .iconChoose:
            let pool = allWords.filter { $0.icon != nil }
            guard let options = choiceOptions(correct: word.lv, pool: pool.map(\.lv), using: &generator) else { return nil }
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "\(word.icon ?? "") için doğru kelimeyi seç.",
                content: .choice(options: options.values, correctIndex: options.correctIndex),
                explanation: "\(word.lv) — \(word.tr)"
            )

        case .lvToTr:
            guard let sentence = pickSentence(wordId: wordId, kind: kind, using: &generator) else { return nil }
            let answer = sentence.tr.split(separator: " ").map(String.init)
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "Türkçesini kur.",
                content: .wordBank(bank: shuffledBank(answer, using: &generator), answer: answer),
                carrier: sentence.lv,
                explanation: sentence.tr
            )

        case .trToLv:
            guard let sentence = pickSentence(wordId: wordId, kind: kind, using: &generator) else { return nil }
            let answer = sentence.lv.split(separator: " ").map(String.init)
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "Letoncasını kur.",
                content: .wordBank(bank: shuffledBank(answer, using: &generator), answer: answer),
                carrier: sentence.tr,
                explanation: sentence.lv
            )

        case .order:
            guard let sentence = pickSentence(wordId: wordId, kind: kind, using: &generator) else { return nil }
            let answer = sentence.lv.split(separator: " ").map(String.init)
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "Kelimeleri doğru sıraya diz.",
                content: .wordBank(bank: shuffledBank(answer, using: &generator), answer: answer),
                carrier: sentence.tr,
                explanation: sentence.lv
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
            guard let options = choiceOptions(correct: word.lv, pool: allWords.map(\.lv), using: &generator) else { return nil }
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "Boşluğa gelen kelimeyi seç.",
                content: .choice(options: options.values, correctIndex: options.correctIndex),
                carrier: blanked,
                explanation: sentence.tr
            )

        case .caseDrill:
            guard let caseForm = word.caseForm else { return nil }
            var distractorSuffixes = distinctDistractorSuffixes(caseForm)
            guard !distractorSuffixes.isEmpty else { return nil }
            distractorSuffixes.shuffle(using: &generator)
            var suffixes = [caseForm.suffix] + distractorSuffixes.prefix(2)
            suffixes.shuffle(using: &generator)
            guard let correctIndex = suffixes.firstIndex(of: caseForm.suffix) else { return nil }
            let stem = String(caseForm.form.dropLast(caseForm.suffix.count))
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "Doğru eki seç.",
                content: .choice(options: suffixes, correctIndex: correctIndex),
                carrier: "\(stem)___",
                explanation: "\(caseForm.form) — \(word.tr)"
            )

        case .dictation:
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "Duyduğunu yaz.",
                audioId: word.audioId,
                content: .typing(accepted: [word.lv]),
                explanation: "\(word.lv) — \(word.tr)"
            )

        case .speak:
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "Dinle ve tekrar et.",
                audioId: word.audioId,
                content: .speaking(target: word.lv),
                explanation: "\(word.lv) — \(word.tr)"
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
                content: .matching(pairs: pairs)
            )
        }
    }

    // MARK: - Yardımcılar

    private func sentencesUsing(wordId: String) -> [LatvianSentence] {
        pack.scenes.flatMap(\.sentences).filter { $0.wordIds.contains(wordId) }
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

    /// `correct` hariç, pooldaki birbirinden farklı değerler; `pool`'daki sıra korunur.
    /// Paket içinde aynı kelimenin birden çok sahnede tekrarlanması (örn. "paldies" 8 kez)
    /// yüzey metninde çakışan çeldiriciler üretmesin diye tekilleştiriliyor.
    /// `Set` yalnızca üyelik testi için kullanılıyor — `Array(Set(...))` gibi kümeden diziye
    /// dönüşüm kullanılmıyor, çünkü Swift'te `Set` sırası aynı çalıştırma içinde bile kararlı
    /// değildir (ilk hash kullanımıyla sonrakiler farklı sıra verebilir); bu, "aynı tohum aynı
    /// soru" garantisini kırar.
    private func distractors(correct: String, pool: [String]) -> [String] {
        var seen: Set<String> = [correct]
        var result: [String] = []
        for item in pool where seen.insert(item).inserted {
            result.append(item)
        }
        return result
    }

    /// Doğru cevap artı en fazla iki çeldiriciden oluşan seçenek listesi üretir.
    /// Havuzda hiç farklı çeldirici yoksa `nil` döner — soru her zaman aynı tek
    /// seçeneği "doğru" göstermek yerine hiç üretilmemeli.
    private func choiceOptions(
        correct: String,
        pool: [String],
        using generator: inout LatvianSeededGenerator
    ) -> (values: [String], correctIndex: Int)? {
        var pickedDistractors = distractors(correct: correct, pool: pool)
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

    private func shuffledBank(
        _ answer: [String],
        using generator: inout LatvianSeededGenerator
    ) -> [String] {
        guard answer.count > 1 else { return answer }
        var bank = answer
        // Karıştırma cevabın kendisine denk gelirse soru anlamsızlaşır; farklı olana kadar dene.
        for _ in 0..<8 {
            bank.shuffle(using: &generator)
            if bank != answer { return bank }
        }
        return bank.reversed()
    }

    private func blank(_ sentence: String, hiding word: String) -> String? {
        let tokens = sentence.split(separator: " ").map(String.init)
        guard let index = tokens.firstIndex(where: {
            LatvianGrader.normalize($0) == LatvianGrader.normalize(word)
        }) else { return nil }
        var blanked = tokens
        blanked[index] = "___"
        return blanked.joined(separator: " ")
    }
}
