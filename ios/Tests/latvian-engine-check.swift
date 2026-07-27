import Foundation

var failures = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ✓ \(message)")
    } else {
        fputs("  ✗ \(message)\n", stderr)
        failures += 1
    }
}

/// Örnek paket. `w5` hedef kelimesi kendi cümlesinde iki kez geçiyor (boşluk doldurmanın
/// cevabı sızdırıp sızdırmadığını sınamak için), `w6`'nın çekim eki biçiminin tamamı kadar
/// uzun (gövdesiz hal tatbikatını sınamak için).
let samplePackJSON = """
{
  "version": 1,
  "generatedAt": "2026-07-27T00:00:00.000Z",
  "audioBaseUrl": "https://blob.example.com/letonca/ses",
  "scenes": [
    {
      "id": "lv-s01",
      "index": 1,
      "title": "Tanışma",
      "words": [
        {"id":"w1","lv":"labdien","tr":"iyi günler","icon":"👋","audioId":"a1","lemma":"labdien","freqRank":400},
        {"id":"w2","lv":"paldies","tr":"teşekkürler","audioId":"a2","lemma":"paldies","freqRank":300},
        {"id":"w3","lv":"lūdzu","tr":"lütfen","audioId":"a3","lemma":"lūdzu","freqRank":350},
        {"id":"w4","lv":"kafija","tr":"kahve","icon":"☕","audioId":"a4","lemma":"kafija","freqRank":900,
         "caseForm":{"base":"kafija","form":"ar kafiju","case":"instrumental","suffix":"u","distractorSuffixes":["a","as"]}},
        {"id":"w5","lv":"sveiki","tr":"merhaba","audioId":"a7","lemma":"sveiki","freqRank":200},
        {"id":"w6","lv":"tikai","tr":"sadece","audioId":"a9","lemma":"tikai","freqRank":500,
         "caseForm":{"base":"tikai","form":"ai","case":"dativ","suffix":"ai","distractorSuffixes":["am","iem"]}}
      ],
      "sentences": [
        {"id":"s1","lv":"Labdien, mani sauc Leyla.","tr":"İyi günler, benim adım Leyla.","audioId":"a5",
         "wordIds":["w1"],"supports":["lv_to_tr","tr_to_lv","order","dictation","fill_blank"]},
        {"id":"s2","lv":"Es gribu kafiju.","tr":"Kahve istiyorum.","audioId":"a6",
         "wordIds":["w4"],"supports":["tr_to_lv","order","case_drill"]},
        {"id":"s3","lv":"Sveiki, sveiki, kā jums iet?","tr":"Merhaba, merhaba, nasılsınız?","audioId":"a8",
         "wordIds":["w5"],"supports":["fill_blank","lv_to_tr"]},
        {"id":"s4","lv":"Tikai vienu kafiju.","tr":"Sadece bir kahve.","audioId":"a10",
         "wordIds":["w6"],"supports":["case_drill","order"]}
      ]
    }
  ]
}
"""

// MARK: - Gerçek paket

/// Uygulamanın gerçekten sevk ettiği paket. `Bundle.main` çıplak `swiftc` ikilisinde
/// çalışmadığından yol, kaynak dosyanın konumundan türetiliyor; ortam değişkeni varsa
/// (başka bir dizinden koşturmak için) o kazanıyor.
let realPackPath: String = {
    if let override = ProcessInfo.processInfo.environment["LATVIAN_PACK_PATH"], !override.isEmpty {
        return override
    }
    return URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // ios/Tests
        .deletingLastPathComponent()  // ios
        .appendingPathComponent("Karavan/Resources/latvian-pack.json")
        .path
}()

func loadRealPack() throws -> LatvianPack {
    try LatvianPack.decode(from: Data(contentsOf: URL(fileURLWithPath: realPackPath)))
}

func allAudioIds(in pack: LatvianPack) -> Set<String> {
    var ids: Set<String> = []
    for scene in pack.scenes {
        for word in scene.words { ids.insert(word.audioId) }
        for sentence in scene.sentences { ids.insert(sentence.audioId) }
    }
    return ids
}

// MARK: - Süreçler arası parmak izi

/// FNV-1a 64 bit. Swift'in kendi `hashValue`'su süreç başına tohumlandığı için süreçler
/// arası karşılaştırmada kullanılamaz; bu özet aynı girdi için her süreçte aynı çıkar.
func stableDigest(_ text: String) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01b3
    }
    return hash
}

/// Sorunun tüm içeriğini sırasıyla düz metne çevirir: seçenek sırası, kelime bankası
/// sırası ve eşleştirme çiftlerinin sırası da özete giriyor — sadece `id` karşılaştırmak
/// asıl yaşanan hatayı (süreçler arası değişen `Set` sırası) kaçırırdı.
func canonicalDescription(_ exercise: LatvianExercise) -> String {
    var parts: [String] = [
        exercise.id,
        exercise.kind.rawValue,
        exercise.targetWordId,
        exercise.prompt,
        exercise.audioId ?? "-",
        exercise.carrier ?? "-",
        exercise.explanation ?? "-",
    ]
    switch exercise.content {
    case .choice(let options, let correctIndex):
        parts.append("choice:\(correctIndex):" + options.joined(separator: "\u{1F}"))
    case .wordBank(let bank, let answer):
        parts.append("bank:" + bank.joined(separator: "\u{1F}")
                     + ":answer:" + answer.joined(separator: "\u{1F}"))
    case .matching(let pairs):
        parts.append("match:" + pairs.map { "\($0.lv)=\($0.tr)" }.joined(separator: "\u{1F}"))
    case .typing(let accepted):
        parts.append("typing:" + accepted.joined(separator: "\u{1F}"))
    case .speaking(let target):
        parts.append("speak:" + target)
    }
    return parts.joined(separator: "\u{1E}")
}

/// Gerçek paket üzerinde sabit bir soru kümesi üretir. Aynı ikili, farklı süreçlerde
/// aynı satırları vermek zorunda.
func fingerprintLines() throws -> [String] {
    let pack = try loadRealPack()
    let audio = allAudioIds(in: pack)
    let factory = LatvianExerciseFactory(pack: pack)
    var lines: [String] = []
    for (wordIndex, word) in pack.scenes.flatMap(\.words).enumerated() {
        let kinds = factory.supportedKinds(forWordId: word.id, availableAudio: audio)
        lines.append("\(word.id)|kinds|" + kinds.map(\.rawValue).joined(separator: ","))
        for (kindIndex, kind) in kinds.enumerated() {
            let seed = UInt64(wordIndex &* 31 &+ kindIndex &+ 1)
            guard let exercise = factory.makeExercise(
                wordId: word.id, kind: kind, seed: seed, availableAudio: audio
            ) else {
                lines.append("\(word.id)|\(kind.rawValue)|NIL")
                continue
            }
            lines.append(canonicalDescription(exercise))
        }
    }
    return lines
}

func runFingerprint() throws {
    let lines = try fingerprintLines()
    let hex = String(stableDigest(lines.joined(separator: "\u{1D}")), radix: 16)
    let padded = String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    print("FINGERPRINT lines=\(lines.count) digest=\(padded)")
}

// MARK: - Bozuk soru taraması

/// Öğrenciye gösterilmemesi gereken kusurlar. Boş dizi "sorun yok" demek.
func defects(in exercise: LatvianExercise, word: LatvianWord) -> [String] {
    var problems: [String] = []

    if exercise.requiresAudio && exercise.audioId == nil {
        problems.append("ses gerektiriyor ama audioId yok")
    }

    switch exercise.content {
    case .choice(let options, let correctIndex):
        if Set(options).count != options.count {
            problems.append("seçenekler birbirinin aynı")
        }
        guard options.indices.contains(correctIndex) else {
            problems.append("doğru seçenek dizini aralık dışı (\(correctIndex)/\(options.count))")
            break
        }
        let correct = options[correctIndex]
        if options.filter({ $0 == correct }).count > 1 {
            problems.append("doğru seçenek çeldiriciler arasında tekrar ediyor")
        }
        if let carrier = exercise.carrier {
            switch exercise.kind {
            case .fillBlank:
                if !carrier.contains("___") { problems.append("taşıyıcıda boşluk yok") }
                let hidden = LatvianGrader.normalize(correct)
                let leaks = carrier.split(separator: " ").contains {
                    LatvianGrader.normalize(String($0)) == hidden
                }
                if leaks { problems.append("taşıyıcı gizlenen kelimeyi hâlâ gösteriyor") }
            case .caseDrill:
                if !carrier.contains("___") { problems.append("taşıyıcıda boşluk yok") }
                if carrier.hasPrefix("___") { problems.append("taşıyıcının gövdesi boş") }
                if let form = word.caseForm.map({ LatvianGrader.normalize($0.form) }),
                   !form.isEmpty,
                   LatvianGrader.normalize(carrier).contains(form) {
                    problems.append("taşıyıcı çekimli biçimin tamamını gösteriyor")
                }
            default:
                break
            }
        }

    case .wordBank(let bank, let answer):
        if bank.sorted() != answer.sorted() {
            problems.append("kelime bankası cevabın permütasyonu değil")
        }

    case .matching(let pairs):
        if pairs.count < 4 { problems.append("dörtten az eşleştirme çifti") }
        if Set(pairs.map(\.lv)).count != pairs.count { problems.append("sol taraf tekrar ediyor") }
        if Set(pairs.map(\.tr)).count != pairs.count { problems.append("sağ taraf tekrar ediyor") }

    case .typing, .speaking:
        break
    }

    return problems
}

/// Ölçümü en iyi turdan alır (zamanlayıcı gürültüsünü eler), turların hepsini rapor eder.
func measure(rounds: Int = 3, _ body: () -> Void) -> (best: Double, all: [Double]) {
    var samples: [Double] = []
    for _ in 0..<rounds {
        let start = Date()
        body()
        samples.append(Date().timeIntervalSince(start) * 1000)
    }
    return (samples.min() ?? 0, samples)
}

func format(_ milliseconds: [Double]) -> String {
    milliseconds.map { String(format: "%.2f", $0) }.joined(separator: " / ")
}

@main
struct LatvianEngineCheck {
    static func main() throws {
        // Süreçler arası belirlenimcilik kipi: sabit bir soru kümesinin özetini basıp çıkar.
        // Kabuk betiği bunu üç ayrı süreçte koşturup çıktıları karşılaştırıyor.
        if CommandLine.arguments.contains("--fingerprint") {
            try runFingerprint()
            return
        }

        print("\n=== Letonca paket modeli ===")

        let pack = try LatvianPack.decode(from: Data(samplePackJSON.utf8))

        expect(pack.scenes.count == 1, "sahne çözümleniyor")
        expect(pack.scenes[0].words.count == 6, "kelimeler çözümleniyor")
        expect(pack.scenes[0].words[0].icon == "👋", "emoji çözümleniyor")
        expect(pack.scenes[0].words[1].icon == nil, "emojisi olmayan kelime nil dönüyor")
        expect(pack.scenes[0].words[3].caseForm?.suffix == "u", "çekim bilgisi çözümleniyor")
        expect(pack.scenes[0].sentences[0].supports.contains(.lvToTr), "soru tipleri çözümleniyor")
        expect(pack.word(id: "w2")?.lv == "paldies", "kelime id ile bulunuyor")
        expect(pack.word(id: "yok") == nil, "olmayan kelime nil dönüyor")
        expect(pack.scene(id: "lv-s01")?.title == "Tanışma", "sahne id ile bulunuyor")
        expect(pack.scene(id: "yok") == nil, "olmayan sahne nil dönüyor")
        expect(pack.sentence(id: "s2")?.lv == "Es gribu kafiju.", "cümle id ile bulunuyor")
        expect(pack.sentence(id: "yok") == nil, "olmayan cümle nil dönüyor")
        expect(pack.audioURL(for: "a1").absoluteString == "https://blob.example.com/letonca/ses/a1.mp3",
               "ses adresi kuruluyor")

        // Dizinler kodlanmıyor; bir tur kodlayıp geri çözmek onları yeniden kurmalı.
        let roundTripped = try LatvianPack.decode(from: JSONEncoder().encode(pack))
        expect(roundTripped.word(id: "w2")?.lv == "paldies", "kodlanıp çözülen pakette dizin yeniden kuruluyor")
        expect(roundTripped.sentence(id: "s3")?.audioId == "a8", "kodlanıp çözülen pakette cümle dizini çalışıyor")

        print("\n=== Soru modeli ===")

        expect(LatvianExerciseKind.listenChoose.modality == .recognition, "dinle-seç tanıma sorusu")
        expect(LatvianExerciseKind.iconChoose.modality == .recognition, "görselden-seç tanıma sorusu")
        expect(LatvianExerciseKind.match.modality == .recognition, "eşleştirme tanıma sorusu")
        expect(LatvianExerciseKind.lvToTr.modality == .recognition, "LV→TR tanıma sorusu")
        expect(LatvianExerciseKind.trToLv.modality == .production, "TR→LV üretim sorusu")
        expect(LatvianExerciseKind.dictation.modality == .production, "dikte üretim sorusu")
        expect(LatvianExerciseKind.order.modality == .production, "sıralama üretim sorusu")
        expect(LatvianExerciseKind.speak.modality == .production, "telaffuz üretim sorusu")
        expect(LatvianExerciseKind.fillBlank.modality == .recognition, "boşluk doldurma tanıma sorusu")
        expect(LatvianExerciseKind.caseDrill.modality == .recognition, "hal tatbikatı tanıma sorusu")

        let choiceExercise = LatvianExercise(
            id: "e1",
            kind: .listenChoose,
            targetWordId: "w1",
            prompt: "Duyduğun kelimeyi seç.",
            audioId: "a1",
            content: .choice(options: ["labdien", "paldies", "lūdzu"], correctIndex: 0)
        )

        expect(choiceExercise.modality == .recognition, "soru modalitesi tipinden geliyor")
        expect(choiceExercise.optionCount == 3, "seçenek sayısı okunuyor")

        let typingExercise = LatvianExercise(
            id: "e2",
            kind: .trToLv,
            targetWordId: "w1",
            prompt: "Türkçesini yaz.",
            content: .typing(accepted: ["labdien"])
        )

        expect(typingExercise.optionCount == 0, "seçmeli olmayan soruda seçenek sayısı sıfır")

        func exercise(_ kind: LatvianExerciseKind) -> LatvianExercise {
            LatvianExercise(
                id: "k-\(kind)",
                kind: kind,
                targetWordId: "w1",
                prompt: "test",
                content: .typing(accepted: ["labdien"])
            )
        }

        expect(exercise(.listenChoose).requiresAudio, "dinle-seç ses gerektiriyor")
        expect(exercise(.dictation).requiresAudio, "dikte ses gerektiriyor")
        expect(exercise(.speak).requiresAudio, "telaffuz ses gerektiriyor")
        expect(!exercise(.iconChoose).requiresAudio, "görselden-seç ses gerektirmiyor")
        expect(!exercise(.match).requiresAudio, "eşleştirme ses gerektirmiyor")
        expect(!exercise(.lvToTr).requiresAudio, "LV→TR ses gerektirmiyor")
        expect(!exercise(.trToLv).requiresAudio, "TR→LV ses gerektirmiyor")
        expect(!exercise(.order).requiresAudio, "sıralama ses gerektirmiyor")
        expect(!exercise(.fillBlank).requiresAudio, "boşluk doldurma ses gerektirmiyor")
        expect(!exercise(.caseDrill).requiresAudio, "hal tatbikatı ses gerektirmiyor")

        print("\n=== Notlama ===")

        expect(LatvianGrader.normalize("Lūdzu!") == "ludzu", "diakritik ve noktalama düşüyor")
        expect(LatvianGrader.normalize("  Es   gribu  ") == "es gribu", "fazla boşluk tekleşiyor")
        expect(LatvianGrader.normalize("Paldies") == LatvianGrader.normalize("paldies."), "büyük harf ve nokta önemsiz")
        expect(LatvianGrader.normalize("IŞIK") == LatvianGrader.normalize("ışık"), "Türkçe büyük harf farkı eriyor")
        expect(LatvianGrader.normalize("kafiju") != LatvianGrader.normalize("kafija"), "farklı ek farklı cevap")
        expect(LatvianGrader.normalize("\u{0130}STANBUL") == LatvianGrader.normalize("istanbul"),
               "noktalı büyük İ (U+0130) küçük i'ye eriyor")
        expect(LatvianGrader.normalize("\u{0130}yi") == LatvianGrader.normalize("iyi"),
               "karışık İ/i yazımı aynı köke eriyor")
        expect(LatvianGrader.normalize("Īsi") == LatvianGrader.normalize("isi"),
               "Letonca Ī, İ eşlemesinden etkilenmeden diakritikle eriyor")
        expect(LatvianGrader.normalize("kafija") != LatvianGrader.normalize("kafiju"),
               "İ eşlemesi Letonca farklı ekleri birbirine karıştırmıyor")

        func exercise(_ kind: LatvianExerciseKind, _ content: LatvianExerciseContent) -> LatvianExercise {
            LatvianExercise(id: "x", kind: kind, targetWordId: "w1", prompt: "p", content: content)
        }

        let choiceQuestion = exercise(.listenChoose, .choice(options: ["labdien", "paldies"], correctIndex: 1))
        expect(LatvianGrader.grade(exercise: choiceQuestion, answer: .choice(index: 1)).isCorrect, "doğru seçenek geçiyor")
        expect(!LatvianGrader.grade(exercise: choiceQuestion, answer: .choice(index: 0)).isCorrect, "yanlış seçenek kalıyor")
        expect(LatvianGrader.grade(exercise: choiceQuestion, answer: .choice(index: 9)).isCorrect == false,
               "aralık dışı seçenek yanlış sayılıyor")
        expect(LatvianGrader.grade(exercise: choiceQuestion, answer: .text("paldies")).isCorrect == false,
               "yanlış cevap türü yanlış sayılıyor")
        expect(LatvianGrader.grade(exercise: choiceQuestion, answer: .choice(index: 0)).correctAnswer == "paldies",
               "doğru cevap metni dönüyor")

        let bankQuestion = exercise(.trToLv, .wordBank(bank: ["sauc", "Mani", "Leyla"], answer: ["Mani", "sauc", "Leyla"]))
        expect(LatvianGrader.grade(exercise: bankQuestion, answer: .words(["Mani", "sauc", "Leyla"])).isCorrect,
               "doğru sıra geçiyor")
        expect(!LatvianGrader.grade(exercise: bankQuestion, answer: .words(["sauc", "Mani", "Leyla"])).isCorrect,
               "yanlış sıra kalıyor")
        expect(LatvianGrader.grade(exercise: bankQuestion, answer: .words(["mani", "sauc", "leyla"])).isCorrect,
               "büyük harf farkı affediliyor")

        let typingQuestion = exercise(.dictation, .typing(accepted: ["Paldies"]))
        expect(LatvianGrader.grade(exercise: typingQuestion, answer: .text("paldies")).isCorrect, "yazım küçük harfle geçiyor")
        expect(LatvianGrader.grade(exercise: typingQuestion, answer: .text(" Paldies! ")).isCorrect, "boşluk ve noktalama affediliyor")
        expect(!LatvianGrader.grade(exercise: typingQuestion, answer: .text("paldie")).isCorrect, "eksik yazım kalıyor")

        let matchQuestion = exercise(.match, .matching(pairs: [
            LatvianMatchPair(lv: "paldies", tr: "teşekkürler"),
            LatvianMatchPair(lv: "lūdzu", tr: "lütfen"),
        ]))
        expect(LatvianGrader.grade(exercise: matchQuestion, answer: .pairs([
            LatvianMatchPair(lv: "lūdzu", tr: "lütfen"),
            LatvianMatchPair(lv: "paldies", tr: "teşekkürler"),
        ])).isCorrect, "eşleştirme sırası önemsiz")
        expect(!LatvianGrader.grade(exercise: matchQuestion, answer: .pairs([
            LatvianMatchPair(lv: "paldies", tr: "lütfen"),
            LatvianMatchPair(lv: "lūdzu", tr: "teşekkürler"),
        ])).isCorrect, "çapraz eşleştirme yanlış")
        expect(!LatvianGrader.grade(exercise: matchQuestion, answer: .pairs([
            LatvianMatchPair(lv: "paldies", tr: "teşekkürler"),
        ])).isCorrect, "eksik eşleştirme yanlış")
        expect(!LatvianGrader.grade(exercise: matchQuestion, answer: .pairs([
            LatvianMatchPair(lv: "paldies", tr: "teşekkürler"),
            LatvianMatchPair(lv: "paldies", tr: "teşekkürler"),
        ])).isCorrect, "aynı çiftin tekrarı diğer çifti karşılamıyor, yanlış sayılıyor")

        let speakQuestion = exercise(.speak, .speaking(target: "Lūdzu"))
        expect(LatvianGrader.grade(exercise: speakQuestion, answer: .spoken(transcript: "ludzu")).isCorrect,
               "telaffuz dökümü diakritiksiz geçiyor")
        expect(!LatvianGrader.grade(exercise: speakQuestion, answer: .spoken(transcript: "paldies")).isCorrect,
               "yanlış telaffuz kalıyor")

        print("\n=== Hafıza ===")

        expect(LatvianRating.from(isCorrect: true, attempts: 1, usedHint: false, elapsed: 2, fastThreshold: 5) == .easy,
               "ilk denemede hızlı doğru → easy")
        expect(LatvianRating.from(isCorrect: true, attempts: 1, usedHint: false, elapsed: 9, fastThreshold: 5) == .good,
               "ilk denemede yavaş doğru → good")
        expect(LatvianRating.from(isCorrect: true, attempts: 1, usedHint: true, elapsed: 2, fastThreshold: 5) == .hard,
               "ipuçlu doğru → hard")
        expect(LatvianRating.from(isCorrect: true, attempts: 2, usedHint: false, elapsed: 2, fastThreshold: 5) == .hard,
               "ikinci denemede doğru → hard")
        expect(LatvianRating.from(isCorrect: false, attempts: 1, usedHint: false, elapsed: 2, fastThreshold: 5) == .again,
               "yanlış → again")

        expect(LatvianExerciseKind.listenChoose.fastThresholdSeconds == 5, "seçmeli sorunun hız eşiği 5 sn")
        expect(LatvianExerciseKind.speak.fastThresholdSeconds == 10, "telaffuz sorusunun hız eşiği 10 sn")
        expect(LatvianExerciseKind.dictation.fastThresholdSeconds == 12, "dikte sorusunun hız eşiği 12 sn")
        expect(LatvianExerciseKind.match.fastThresholdSeconds == 15, "eşleştirme sorusunun hız eşiği 15 sn")

        expect(LatvianRating.from(isCorrect: true, attempts: 1, usedHint: false, elapsed: 8,
                                   fastThreshold: LatvianExerciseKind.listenChoose.fastThresholdSeconds) == .good,
               "seçmeli soruda 8 sn → good (eşik 5 sn)")
        expect(LatvianRating.from(isCorrect: true, attempts: 1, usedHint: false, elapsed: 8,
                                   fastThreshold: LatvianExerciseKind.dictation.fastThresholdSeconds) == .easy,
               "aynı 8 sn dikte sorusunda → easy (eşik 12 sn)")

        let scheduler = LatvianDefaultScheduler()
        let epoch = Date(timeIntervalSince1970: 1_800_000_000)

        let fresh = LatvianMemoryCard.new()
        expect(fresh.reviewCount == 0, "yeni kart hiç tekrar edilmemiş")
        expect(fresh.retrievability(at: epoch) == 0, "hiç görülmemiş kartın hatırlanma olasılığı sıfır")
        expect(fresh.isDue(at: epoch), "yeni kart her zaman vadesi gelmiş sayılır")

        let afterGood = scheduler.review(card: fresh, rating: .good, now: epoch)
        expect(afterGood.reviewCount == 1, "tekrar sayacı artıyor")
        expect(afterGood.stability > fresh.stability, "doğru cevap kararlılığı artırıyor")
        expect(afterGood.dueAt > epoch, "sonraki tekrar ileri tarihte")
        expect(afterGood.retrievability(at: epoch) > 0.99, "tekrar anında hatırlanma olasılığı tam")
        expect(!afterGood.isDue(at: epoch), "az önce tekrar edilen kart vadesinden önce vadesi gelmemiş sayılır")
        expect(!afterGood.isDue(at: afterGood.dueAt.addingTimeInterval(-1)), "vade anından hemen önce henüz vadesi gelmemiş")
        expect(afterGood.isDue(at: afterGood.dueAt), "vade anında kart vadesi gelmiş sayılır")
        expect(afterGood.isDue(at: afterGood.dueAt.addingTimeInterval(1)), "vade anından sonra da vadesi gelmiş sayılır")

        let afterEasy = scheduler.review(card: fresh, rating: .easy, now: epoch)
        expect(afterEasy.stability > afterGood.stability, "easy, good'dan daha uzun aralık veriyor")

        let matured = scheduler.review(card: scheduler.review(card: fresh, rating: .good, now: epoch),
                                       rating: .good,
                                       now: epoch.addingTimeInterval(86_400))
        let lapsed = scheduler.review(card: matured, rating: .again, now: epoch.addingTimeInterval(200_000))
        expect(lapsed.stability < matured.stability, "yanlış cevap kararlılığı düşürüyor")
        expect(lapsed.dueAt.timeIntervalSince(epoch.addingTimeInterval(200_000)) < 86_400,
               "yanlış cevaptan sonra kart bir gün içinde geri geliyor")

        expect(matured.retrievability(at: matured.dueAt) < matured.retrievability(at: epoch),
               "zaman geçtikçe hatırlanma olasılığı düşüyor")
        expect(matured.retrievability(at: epoch.addingTimeInterval(86_400 * 3650)) < 0.2,
               "çok uzun aradan sonra hatırlanma olasılığı çöküyor")

        guard let key = LatvianMemoryKey(wordId: "w1", modality: .production) else {
            fatalError("beklenen geçerli anahtar oluşturulamadı")
        }
        expect(key == LatvianMemoryKey(wordId: "w1", modality: .production), "aynı anahtar eşit")
        expect(key != LatvianMemoryKey(wordId: "w1", modality: .recognition), "modalite anahtarı ayırıyor")
        expect(key.storageKey == "w1#production", "anahtar dizeye çevrilebiliyor")
        expect(LatvianMemoryKey(storageKey: "w1#production") == key, "anahtar dizeden geri okunuyor")
        expect(LatvianMemoryKey(wordId: "", modality: .production) == nil,
               "boş kelime id'si ile anahtar oluşturulamıyor")

        guard let separatorKey = LatvianMemoryKey(wordId: "w#1", modality: .recognition) else {
            fatalError("beklenen geçerli anahtar oluşturulamadı")
        }
        expect(separatorKey.storageKey == "w#1#recognition", "ayırıcı içeren kelime id'si anahtara yazılıyor")
        expect(LatvianMemoryKey(storageKey: separatorKey.storageKey) == separatorKey,
               "ayırıcı içeren kelime id'li anahtar dizeden geri okunuyor")

        print("\n=== Soru üretici ===")

        let allAudio: Set<String> = ["a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9", "a10"]
        let factory = LatvianExerciseFactory(pack: pack)

        let listen = factory.makeExercise(wordId: "w1", kind: .listenChoose, seed: 1, availableAudio: allAudio)
        expect(listen != nil, "dinle-seç üretiliyor")
        expect(listen?.audioId == "a1", "dinle-seç doğru sesi taşıyor")
        if case .choice(let options, let correct)? = listen?.content {
            expect(options.count == 3, "dinle-seç üç seçenekli")
            expect(options[correct] == "labdien", "doğru seçenek hedef kelime")
            expect(Set(options).count == 3, "seçenekler birbirinden farklı")
        } else {
            expect(false, "dinle-seç seçmeli içerik üretiyor")
        }

        expect(factory.makeExercise(wordId: "w1", kind: .listenChoose, seed: 1, availableAudio: []) == nil,
               "sesi olmayan kelimede dinleme sorusu üretilmiyor")

        let icon = factory.makeExercise(wordId: "w1", kind: .iconChoose, seed: 2, availableAudio: allAudio)
        expect(icon != nil, "emojisi olan kelimede görselden-seç üretiliyor")
        expect(factory.makeExercise(wordId: "w2", kind: .iconChoose, seed: 2, availableAudio: allAudio) == nil,
               "emojisi olmayan kelimede görselden-seç üretilmiyor")

        let order = factory.makeExercise(wordId: "w1", kind: .order, seed: 3, availableAudio: allAudio)
        if case .wordBank(let bank, let answer)? = order?.content {
            expect(answer == ["Labdien,", "mani", "sauc", "Leyla."], "sıralama doğru cevabı cümlenin kendisi")
            expect(bank.sorted() == answer.sorted(), "kelime bankası cevabın permütasyonu")
            // Bankanın var oluş sebebi bu: cevapla aynı sırada gelirse soru anlamsız.
            expect(bank != answer, "kelime bankası cevabın sırasında gelmiyor")
        } else {
            expect(false, "sıralama kelime bankası üretiyor")
        }

        let caseDrill = factory.makeExercise(wordId: "w4", kind: .caseDrill, seed: 4, availableAudio: allAudio)
        expect(caseDrill != nil, "çekim bilgisi olan kelimede hal tatbikatı üretiliyor")
        if case .choice(let options, let correct)? = caseDrill?.content {
            expect(options.count == 3, "hal tatbikatı üç ek seçeneği sunuyor")
            expect(options.indices.contains(correct) && options[correct] == "u", "doğru ek işaretli")
        } else {
            expect(false, "hal tatbikatı seçmeli içerik üretiyor")
        }
        expect(caseDrill?.carrier?.contains("kafij") == true, "hal tatbikatı taşıyıcı cümle gösteriyor")
        expect(factory.makeExercise(wordId: "w1", kind: .caseDrill, seed: 4, availableAudio: allAudio) == nil,
               "çekim bilgisi olmayan kelimede hal tatbikatı üretilmiyor")

        // Eki biçiminin tamamı kadar uzun olan çekim bilgisi gövdesiz bir "___" verirdi.
        expect(!factory.supportedKinds(forWordId: "w6", availableAudio: allAudio).contains(.caseDrill),
               "gövdesi kalmayan çekim bilgisi hal tatbikatını desteklemiyor")
        expect(factory.makeExercise(wordId: "w6", kind: .caseDrill, seed: 8, availableAudio: allAudio) == nil,
               "gövdesi kalmayan çekim bilgisinde hal tatbikatı üretilmiyor")
        expect(factory.supportedKinds(forWordId: "w6", availableAudio: allAudio).contains(.order),
               "gövdesiz çekim bilgisi yalnızca hal tatbikatını eliyor, diğer tipleri değil")

        // Hedef kelime cümlede iki kez geçtiğinde ikinci geçiş cevabı ekranda bırakmamalı.
        let repeated = factory.makeExercise(wordId: "w5", kind: .fillBlank, seed: 7, availableAudio: allAudio)
        expect(repeated != nil, "tekrar eden hedef kelimeli cümlede boşluk doldurma üretiliyor")
        if let carrier = repeated?.carrier {
            let hidden = LatvianGrader.normalize("sveiki")
            expect(!carrier.split(separator: " ").contains { LatvianGrader.normalize(String($0)) == hidden },
                   "hedef kelime iki kez geçse de taşıyıcıda hiç görünmüyor")
            expect(carrier.split(separator: " ").filter { $0 == "___" }.count == 2,
                   "hedef kelimenin her iki geçişi de boşluğa çevriliyor")
        } else {
            expect(false, "boşluk doldurma taşıyıcı üretiyor")
        }

        let dictation = factory.makeExercise(wordId: "w1", kind: .dictation, seed: 5, availableAudio: allAudio)
        if case .typing(let accepted)? = dictation?.content {
            expect(accepted.contains("labdien"), "dikte hedef kelimeyi kabul ediyor")
        } else {
            expect(false, "dikte yazma içeriği üretiyor")
        }

        let match = factory.makeExercise(wordId: "w1", kind: .match, seed: 6, availableAudio: allAudio)
        if case .matching(let pairs)? = match?.content {
            expect(pairs.count == 4, "eşleştirme dört çift üretiyor")
            expect(pairs.contains { $0.lv == "labdien" }, "eşleştirme hedef kelimeyi içeriyor")
        } else {
            expect(false, "eşleştirme çift üretiyor")
        }

        let first = factory.makeExercise(wordId: "w1", kind: .listenChoose, seed: 42, availableAudio: allAudio)
        let second = factory.makeExercise(wordId: "w1", kind: .listenChoose, seed: 42, availableAudio: allAudio)
        expect(first == second, "aynı tohum aynı soruyu üretiyor")

        let kinds = factory.supportedKinds(forWordId: "w4", availableAudio: allAudio)
        expect(kinds.contains(.caseDrill), "çekimli kelime hal tatbikatını destekliyor")
        expect(!factory.supportedKinds(forWordId: "w2", availableAudio: []).contains(.dictation),
               "sessiz kelime dikteyi desteklemiyor")
        expect(!kinds.isEmpty, "her kelimenin en az bir soru tipi var")

        print("\n=== Gerçek paket taraması ===")

        let realPack = try loadRealPack()
        let realWords = realPack.scenes.flatMap(\.words)
        let realAudio = allAudioIds(in: realPack)
        let realFactory = LatvianExerciseFactory(pack: realPack)

        expect(realWords.count >= 250, "gerçek paket \(realWords.count) kelime taşıyor")

        var generated = 0
        var perKind: [String: Int] = [:]
        var undeliverable: [String] = []
        var unexpectedlyDeliverable: [String] = []
        var broken: [String] = []

        for (wordIndex, word) in realWords.enumerated() {
            let supported = realFactory.supportedKinds(forWordId: word.id, availableAudio: realAudio)
            let supportedSet = Set(supported)
            for (kindIndex, kind) in supported.enumerated() {
                let seed = UInt64(wordIndex &* 13 &+ kindIndex &* 7 &+ 1)
                guard let exercise = realFactory.makeExercise(
                    wordId: word.id, kind: kind, seed: seed, availableAudio: realAudio
                ) else {
                    undeliverable.append("\(word.id)/\(kind.rawValue)")
                    continue
                }
                generated += 1
                perKind[kind.rawValue, default: 0] += 1
                for problem in defects(in: exercise, word: word) {
                    broken.append("\(word.id)/\(kind.rawValue): \(problem)")
                }
            }
            // Ters yön: bildirilmeyen bir tip asla üretilmemeli.
            for kind in LatvianExerciseKind.allCases where !supportedSet.contains(kind) {
                if realFactory.makeExercise(
                    wordId: word.id, kind: kind, seed: 1, availableAudio: realAudio
                ) != nil {
                    unexpectedlyDeliverable.append("\(word.id)/\(kind.rawValue)")
                }
            }
        }

        print("  toplam \(generated) soru üretildi (\(realWords.count) kelime)")
        for kind in LatvianExerciseKind.allCases {
            print("    \(kind.rawValue): \(perKind[kind.rawValue] ?? 0)")
        }

        expect(undeliverable.isEmpty,
               "supportedKinds'in bildirdiği her tip üretilebiliyor"
               + (undeliverable.isEmpty ? "" : " — eksik: \(undeliverable.prefix(5).joined(separator: ", "))"))
        expect(unexpectedlyDeliverable.isEmpty,
               "supportedKinds'in bildirmediği hiçbir tip üretilmiyor"
               + (unexpectedlyDeliverable.isEmpty ? "" : " — fazla: \(unexpectedlyDeliverable.prefix(5).joined(separator: ", "))"))
        expect(broken.isEmpty,
               "üretilen soruların hiçbiri bozuk değil"
               + (broken.isEmpty ? "" : " — \(broken.count) kusur, ilki: \(broken[0])"))
        expect(generated >= 1800, "tarama kapsamı korunuyor (\(generated) soru)")

        print("\n=== Performans bütçeleri ===")

        var kindTotal = 0
        let kindTiming = measure {
            for word in realWords {
                kindTotal += realFactory.supportedKinds(forWordId: word.id, availableAudio: realAudio).count
            }
        }
        print("  supportedKinds × \(realWords.count) kelime: \(format(kindTiming.all)) ms"
              + String(format: " (en iyi %.2f ms, bütçe 10 ms, %d tip)", kindTiming.best, kindTotal / kindTiming.all.count))
        expect(kindTiming.best < 10,
               String(format: "supportedKinds bütçesi: %.2f ms < 10 ms", kindTiming.best))

        var plan: [(String, LatvianExerciseKind)] = []
        planLoop: for word in realWords {
            for kind in realFactory.supportedKinds(forWordId: word.id, availableAudio: realAudio) {
                plan.append((word.id, kind))
                if plan.count >= 120 { break planLoop }
            }
        }
        expect(plan.count >= 100, "üretim bütçesi 100+ soru üzerinde ölçülüyor (\(plan.count))")

        var built = 0
        let buildTiming = measure {
            for (index, item) in plan.enumerated() {
                if realFactory.makeExercise(
                    wordId: item.0, kind: item.1, seed: UInt64(index + 1), availableAudio: realAudio
                ) != nil {
                    built += 1
                }
            }
        }
        print("  \(plan.count) soru üretimi: \(format(buildTiming.all)) ms"
              + String(format: " (en iyi %.2f ms, bütçe 10 ms, %d üretildi)", buildTiming.best, built / buildTiming.all.count))
        expect(buildTiming.best < 10,
               String(format: "üretim bütçesi: %.2f ms < 10 ms", buildTiming.best))

        if failures > 0 {
            fputs("\n\(failures) kontrol başarısız.\n", stderr)
            exit(1)
        }
        print("\nLetonca birim kontrolleri ve paket taraması geçti.\n")
    }
}
