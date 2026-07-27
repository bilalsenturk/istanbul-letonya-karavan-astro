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

/// Testlerde anahtar kurmayı kısaltır. `LatvianMemoryKey` yalnızca boş kelime kimliğinde
/// nil döndüğü için burada başarısızlık programlama hatasıdır.
func memoryKey(_ wordId: String, _ modality: LatvianModality) -> LatvianMemoryKey {
    guard let key = LatvianMemoryKey(wordId: wordId, modality: modality) else {
        fatalError("geçersiz hafıza anahtarı: \(wordId)")
    }
    return key
}

/// Seri hesabı takvime bağlı; testler sistem saat diliminden etkilenmesin diye UTC kullanıyor.
let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    return calendar
}()

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

    // Ders kurgusu da parmak izine giriyor. Ders kurucusu hafızayı, hata listesini ve
    // sahne kelimelerini geziyor; bunların herhangi birinde `Set`/`Dictionary` sırasına
    // sızacak bir belirsizlik yalnızca ayrı süreçlerde görünür hale gelir.
    let scheduler = LatvianDefaultScheduler()
    let epoch = Date(timeIntervalSince1970: 1_800_000_000)
    var progress = LatvianProgress.new()
    for (index, word) in pack.scenes.flatMap(\.words).enumerated() where index % 3 == 0 {
        let modality: LatvianModality = index % 2 == 0 ? .recognition : .production
        let rating: LatvianRating = index % 5 == 0 ? .again : .good
        progress.registerAnswer(
            wordId: word.id, modality: modality, rating: rating, scheduler: scheduler, now: epoch
        )
    }
    // Birkaç kart bilerek takılma durumuna sürükleniyor: kurtarma yolu (havuz sırası,
    // merdiven, kota kesintisi) da parmak izine girsin. Bu yol sözlükten okuyor ve
    // kararlılığa göre sıralıyor; sızacak bir belirsizlik ancak ayrı süreçlerde görünür.
    for (index, word) in pack.scenes.flatMap(\.words).enumerated() where index % 7 == 0 {
        for round in 0..<5 {
            progress.registerAnswer(
                wordId: word.id, modality: .recognition, rating: .again,
                scheduler: scheduler, now: epoch.addingTimeInterval(Double(round) * 3600)
            )
        }
    }
    let lessonMoment = epoch.addingTimeInterval(86_400 * 10)
    for scene in pack.scenes {
        let plan = LatvianLessonBuilder.plan(
            scene: scene, pack: pack, progress: progress, now: lessonMoment
        )
        lines.append("plan|\(scene.id)|" + plan.map(\.debugKey).joined(separator: ","))
        let lesson = LatvianLessonBuilder.build(
            scene: scene, pack: pack, progress: progress, factory: factory,
            availableAudio: audio, seed: UInt64(scene.index) &* 101, now: lessonMoment
        )
        lines.append("lesson|\(scene.id)|\(lesson.count)")
        for exercise in lesson { lines.append(canonicalDescription(exercise)) }
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

        print("\n=== İlerleme durumu ===")

        var progress = LatvianProgress.new()
        expect(progress.hearts == 5, "beş canla başlıyor")
        expect(progress.xp == 0, "sıfır XP ile başlıyor")
        expect(progress.streakDays == 0, "seri sıfırdan başlıyor")
        expect(progress.recentMistakes.isEmpty, "hata listesi boş başlıyor")

        progress.registerAnswer(wordId: "w1", modality: .recognition, rating: .good,
                                scheduler: scheduler, now: epoch)
        expect(progress.card(for: memoryKey("w1", .recognition))?.reviewCount == 1,
               "cevap hafızaya işleniyor")
        expect(progress.card(for: memoryKey("w1", .production)) == nil,
               "diğer modalite etkilenmiyor")
        expect(progress.xp == LatvianProgress.xpPerCorrectAnswer, "doğru cevap XP kazandırıyor")

        progress.registerAnswer(wordId: "w2", modality: .recognition, rating: .again,
                                scheduler: scheduler, now: epoch)
        expect(progress.recentMistakes.contains("w2"), "yanlış cevap hata listesine giriyor")
        expect(!progress.recentMistakes.contains("w1"), "doğru cevap hata listesine girmiyor")
        expect(progress.xp == LatvianProgress.xpPerCorrectAnswer, "yanlış cevap XP kazandırmıyor")

        progress.registerAnswer(wordId: "w2", modality: .recognition, rating: .good,
                                scheduler: scheduler, now: epoch.addingTimeInterval(60))
        expect(!progress.recentMistakes.contains("w2"),
               "sonradan doğrulanan kelime hata listesinden çıkıyor")

        expect(progress.registerAnswer(wordId: "", modality: .recognition, rating: .good,
                                       scheduler: scheduler, now: epoch) == false,
               "boş kelime kimliğiyle cevap sessizce yazılmıyor")

        // Hata listesi sınırsız büyümemeli: her ders yeni hatalar ekliyor.
        var noisy = LatvianProgress.new()
        for index in 0..<(LatvianProgress.mistakeMemory * 3) {
            noisy.registerAnswer(wordId: "n\(index)", modality: .recognition, rating: .again,
                                 scheduler: scheduler, now: epoch)
        }
        expect(noisy.recentMistakes.count == LatvianProgress.mistakeMemory,
               "hata listesi üst sınırda duruyor (\(noisy.recentMistakes.count))")
        expect(noisy.recentMistakes.last == "n\(LatvianProgress.mistakeMemory * 3 - 1)",
               "en yeni hata listenin sonunda")
        expect(!noisy.recentMistakes.contains("n0"), "en eski hata listeden düşüyor")

        var doubleMistake = LatvianProgress.new()
        doubleMistake.registerAnswer(wordId: "w1", modality: .recognition, rating: .again,
                                     scheduler: scheduler, now: epoch)
        doubleMistake.registerAnswer(wordId: "w1", modality: .production, rating: .again,
                                     scheduler: scheduler, now: epoch)
        expect(doubleMistake.recentMistakes == ["w1"],
               "aynı kelime hata listesinde iki kez yer kaplamıyor")

        // Can
        var lives = LatvianProgress.new()
        lives.loseHeart(now: epoch)
        expect(lives.hearts == 4, "can kaybı işleniyor")
        lives.loseHeart(now: epoch.addingTimeInterval(3600))
        expect(lives.hearts == 3, "ikinci can kaybı işleniyor")
        lives.refillHearts(now: epoch.addingTimeInterval(LatvianProgress.heartRefillInterval))
        expect(lives.hearts == 4, "dolum süresi dolunca bir can geliyor")
        lives.refillHearts(now: epoch.addingTimeInterval(86_400 * 365))
        expect(lives.hearts == LatvianProgress.maxHearts,
               "uzun aradan sonra canlar dolup üst sınırda duruyor (\(lives.hearts))")
        expect(lives.lastHeartLostAt == nil, "canlar dolunca dolum sayacı kapanıyor")

        var drained = LatvianProgress.new()
        for index in 0..<10 {
            drained.loseHeart(now: epoch.addingTimeInterval(Double(index) * 60))
        }
        expect(drained.hearts == 0, "can sıfırın altına inmiyor")
        drained.refillHearts(now: epoch.addingTimeInterval(LatvianProgress.heartRefillInterval * 2))
        expect(drained.hearts == 2,
               "canı bitmiş öğrencide ek kayıplar dolum sayacını ileri itmiyor (\(drained.hearts))")

        // Seri
        var streak = LatvianProgress.new()
        streak.registerLessonCompleted(now: epoch, calendar: utcCalendar)
        expect(streak.streakDays == 1, "ilk ders seriyi bire çıkarıyor")
        streak.registerLessonCompleted(now: epoch.addingTimeInterval(3600), calendar: utcCalendar)
        expect(streak.streakDays == 1, "aynı gün ikinci ders seriyi artırmıyor")
        streak.registerLessonCompleted(now: epoch.addingTimeInterval(86_400), calendar: utcCalendar)
        expect(streak.streakDays == 2, "ertesi gün seri artıyor")
        streak.registerLessonCompleted(now: epoch.addingTimeInterval(86_400 * 4), calendar: utcCalendar)
        expect(streak.streakDays == 1, "günler atlanınca seri baştan başlıyor")
        streak.registerLessonCompleted(now: epoch.addingTimeInterval(86_400 * 5 - 3600),
                                       calendar: utcCalendar)
        expect(streak.streakDays == 2, "gecenin ilerleyen saati de ertesi gün sayılıyor")

        // Kalıcılık
        let encodedProgress = try progress.encoded()
        let reloadedProgress = try LatvianProgress.decode(from: encodedProgress)
        expect(reloadedProgress == progress, "ilerleme birebir kaydedilip geri okunuyor")
        expect(reloadedProgress.card(for: memoryKey("w1", .recognition))?.reviewCount == 1,
               "hafıza kartı kaydedilip geri okunuyor")
        expect(reloadedProgress.hearts == progress.hearts, "can sayısı kalıcı")

        let sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("latvian-progress-check-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.removeItem(at: sandbox)
        let progressURL = sandbox.appendingPathComponent("latvian-progress.json")
        let backupURL = progressURL.appendingPathExtension("bak")

        expect(LatvianProgress.load(from: progressURL).outcome == .fresh,
               "kayıt yokken sıfırdan başlıyor")

        try progress.save(to: progressURL)
        let reloaded = LatvianProgress.load(from: progressURL)
        expect(reloaded.outcome == .loaded && reloaded.progress == progress,
               "ilerleme dosyaya yazılıp geri okunuyor")

        var later = progress
        later.registerAnswer(wordId: "w3", modality: .production, rating: .easy,
                             scheduler: scheduler, now: epoch)
        try later.save(to: progressURL)
        try Data("{ yarım".utf8).write(to: progressURL)
        let recovered = LatvianProgress.load(from: progressURL)
        expect(recovered.outcome == .recovered && recovered.progress == progress,
               "bozuk dosya yedekten kurtarılıyor")

        try Data("{ yarım".utf8).write(to: backupURL)
        let wiped = LatvianProgress.load(from: progressURL)
        expect(wiped.outcome == .reset && wiped.progress == LatvianProgress.new(),
               "yedek de bozuksa sıfırlanıyor ve bu bildiriliyor")

        try Data(#"{"xp":40}"#.utf8).write(to: progressURL)
        let partial = LatvianProgress.load(from: progressURL)
        expect(partial.outcome == .loaded
               && partial.progress.xp == 40
               && partial.progress.hearts == LatvianProgress.maxHearts,
               "eksik alanlı kayıt varsayılanlarla okunuyor")

        try Data(#"{"hearts":99,"xp":-5,"memory":{"bozuk-anahtar":{"stability":1,"difficulty":5,"dueAt":0,"reviewCount":1,"lapseCount":0}}}"#.utf8)
            .write(to: progressURL)
        let clamped = LatvianProgress.load(from: progressURL).progress
        expect(clamped.hearts == LatvianProgress.maxHearts, "can sayısı üst sınıra kırpılıyor")
        expect(clamped.xp == 0, "negatif XP sıfıra kırpılıyor")
        expect(clamped.allCards().isEmpty, "çözülemeyen hafıza anahtarı atılıyor")
        try? FileManager.default.removeItem(at: sandbox)

        print("\n=== Sahne kilidi ===")

        // Fikstürler zamanı ilerleterek kuruluyor: kartın vadesinde yapılan tekrar
        // kararlılığı gerçekten büyütür, aynı anda arka arkaya yapılan tekrar büyütmez —
        // gerçek FSRS'te hatırlanma tavandayken tekrarın kazancı sıfıra gider.
        func reviewedOnSchedule(times: Int, rating: LatvianRating) -> LatvianMemoryCard {
            var card = LatvianMemoryCard.new()
            var moment = epoch
            for _ in 0..<times {
                card = scheduler.review(card: card, rating: rating, now: moment)
                moment = card.dueAt
            }
            return card
        }

        var mastered = LatvianProgress.new()
        for word in pack.scenes[0].words {
            for modality in [LatvianModality.recognition, .production] {
                mastered.setCard(reviewedOnSchedule(times: 3, rating: .easy),
                                 for: memoryKey(word.id, modality))
            }
        }

        expect(LatvianLessonBuilder.freshnessThreshold == 0.9, "tazelik eşiği 0.9")
        expect(LatvianLessonBuilder.masteryCoverage == 0.8, "kapsama eşiği 0.8")
        expect(LatvianLessonBuilder.lessonLength == 16, "ders uzunluğu 16")
        expect(LatvianLessonBuilder.masteryStabilityDays == 7, "hakimiyet kararlılık eşiği yedi gün")
        expect(LatvianLessonBuilder.minimumReviews == 2, "hakimiyet en az iki tekrar istiyor")

        // Kapının kapattığı boşluk: `retrievability` tekrar anında tanım gereği tavanda,
        // dolayısıyla "şu anda hatırlıyor mu" sorusu yalnızca "az önce gördü mü" demek.
        // Ölçüt bu yüzden kararlılığı okuyor. Aşağıdaki iki kart da anlık hatırlama
        // testini geçerdi; hiçbiri hakim değil.
        let justAnswered = scheduler.review(card: .new(), rating: .easy, now: epoch)
        expect(justAnswered.retrievability(at: epoch) > 0.99,
               "az önce kusursuz cevaplanan kart o anda tavanda")
        var singleReview = LatvianProgress.new()
        for modality in [LatvianModality.recognition, .production] {
            singleReview.setCard(justAnswered, for: memoryKey("w1", modality))
        }
        expect(!LatvianLessonBuilder.isWordMastered(wordId: "w1", progress: singleReview, now: epoch),
               "tek tekrarla bilinen kelime hakim sayılmıyor")

        let shakyCard = reviewedOnSchedule(times: LatvianLessonBuilder.minimumReviews, rating: .hard)
        var shaky = LatvianProgress.new()
        for modality in [LatvianModality.recognition, .production] {
            shaky.setCard(shakyCard, for: memoryKey("w1", modality))
        }
        expect(shakyCard.reviewCount >= LatvianLessonBuilder.minimumReviews
               && shakyCard.retrievability(at: shakyCard.lastReviewedAt ?? epoch) > 0.99,
               "zorlanarak cevaplanan kart tekrar sayısını dolduruyor ve o anda tavanda")
        expect(!LatvianLessonBuilder.isWordMastered(wordId: "w1", progress: shaky, now: epoch),
               String(format: "kararlılığı bir haftayı taşımayan kelime hakim sayılmıyor (%.1f gün)",
                      shakyCard.stability))

        let durableCard = reviewedOnSchedule(times: LatvianLessonBuilder.minimumReviews, rating: .easy)
        var durable = LatvianProgress.new()
        for modality in [LatvianModality.recognition, .production] {
            durable.setCard(durableCard, for: memoryKey("w1", modality))
        }
        expect(durableCard.stability >= LatvianLessonBuilder.masteryStabilityDays,
               String(format: "vadesinde yapılan iki kusursuz tekrar kararlılığı eşiğin üstüne çıkarıyor (%.1f gün)",
                      durableCard.stability))
        expect(LatvianLessonBuilder.isWordMastered(wordId: "w1", progress: durable, now: epoch),
               "kararlılığı eşiği taşıyan kelime hakim sayılıyor")

        // Ölçütün iki koşulu da tek tek bağlayıcı: eşiğin hemen altındaki kararlılık kaç
        // tekrar görülürse görülsün yetmiyor, eşiği taşıyan kart da tek tekrarla geçmiyor.
        func progressHolding(_ card: LatvianMemoryCard) -> LatvianProgress {
            var result = LatvianProgress.new()
            for modality in [LatvianModality.recognition, .production] {
                result.setCard(card, for: memoryKey("w1", modality))
            }
            return result
        }
        var justUnder = durableCard
        justUnder.stability = LatvianLessonBuilder.masteryStabilityDays - 0.01
        justUnder.reviewCount = 20
        expect(!LatvianLessonBuilder.isWordMastered(
                wordId: "w1", progress: progressHolding(justUnder), now: epoch),
               "eşiğin hemen altındaki kararlılık yirmi tekrarla bile hakim saymıyor")
        var justOver = justUnder
        justOver.stability = LatvianLessonBuilder.masteryStabilityDays
        justOver.reviewCount = LatvianLessonBuilder.minimumReviews
        expect(LatvianLessonBuilder.isWordMastered(
                wordId: "w1", progress: progressHolding(justOver), now: epoch),
               "eşiği tam karşılayan kararlılık iki tekrarla hakim sayılıyor")
        var tooFewReviews = justOver
        tooFewReviews.reviewCount = LatvianLessonBuilder.minimumReviews - 1
        expect(!LatvianLessonBuilder.isWordMastered(
                wordId: "w1", progress: progressHolding(tooFewReviews), now: epoch),
               "kararlılık yetse de tek tekrar hakim saymıyor")

        expect(LatvianLessonBuilder.masteryRatio(scene: pack.scenes[0], progress: mastered, now: epoch) >= 0.8,
               "ezberlenmiş sahnede hakimiyet oranı yüksek")
        expect(LatvianLessonBuilder.isSceneMastered(scene: pack.scenes[0], progress: mastered, now: epoch),
               "ezberlenmiş sahne tamamlanmış sayılıyor")
        expect(!LatvianLessonBuilder.isSceneMastered(scene: pack.scenes[0], progress: LatvianProgress.new(), now: epoch),
               "boş ilerlemede sahne tamamlanmamış")

        // Ölçüt saati okumuyor: kararlılık kartın kendi durumunda duran bir sayı, sorgu
        // anıyla değişmiyor. Unutma yine de ölçülüyor — ama tekrar edilip yanlış
        // cevaplandığında kararlılık çöktüğü için, takvimden değil cevaptan.
        let staleMoment = epoch.addingTimeInterval(86_400 * 3650)
        expect(LatvianLessonBuilder.masteryRatio(scene: pack.scenes[0], progress: mastered, now: staleMoment)
               == LatvianLessonBuilder.masteryRatio(scene: pack.scenes[0], progress: mastered, now: epoch),
               "hakimiyet oranı sorgu anına bağlı değil")
        expect(LatvianLessonBuilder.isSceneMastered(scene: pack.scenes[0], progress: mastered, now: staleMoment),
               "on yıl sonra sorulduğunda da aynı sahne hakim sayılıyor")
        let lapsedAfterBreak = scheduler.review(card: durableCard, rating: .again, now: staleMoment)
        expect(lapsedAfterBreak.stability < LatvianLessonBuilder.masteryStabilityDays
               && !LatvianLessonBuilder.isWordMastered(
                    wordId: "w1", progress: progressHolding(lapsedAfterBreak), now: staleMoment),
               String(format: "aradan sonra yanlış cevaplanan kart hakimiyeti kaybediyor (%.1f gün)",
                      lapsedAfterBreak.stability))

        // Hakimiyet iki modaliteyi birden istiyor: yalnızca tanıma tarafı yetmiyor.
        var recognitionOnly = LatvianProgress.new()
        for word in pack.scenes[0].words {
            recognitionOnly.setCard(reviewedOnSchedule(times: 3, rating: .easy),
                                    for: memoryKey(word.id, .recognition))
        }
        expect(LatvianLessonBuilder.masteryRatio(scene: pack.scenes[0], progress: recognitionOnly, now: epoch) == 0,
               "yalnızca tanıma tarafı bilinen sahnede hakimiyet oranı sıfır")

        print("\n=== Ders kurgusu (örnek paket) ===")

        let lesson = LatvianLessonBuilder.build(
            scene: pack.scenes[0],
            pack: pack,
            progress: progress,
            factory: factory,
            availableAudio: allAudio,
            seed: 7,
            now: epoch
        )

        expect(lesson.count == LatvianLessonBuilder.lessonLength, "ders 16 sorudan oluşuyor")
        expect(Set(lesson.map(\.id)).count == lesson.count, "aynı soru iki kez girmiyor")

        var repeatedKind = false
        var repeatedWord = false
        for index in 1..<lesson.count {
            if lesson[index].kind == lesson[index - 1].kind { repeatedKind = true }
            if lesson[index].targetWordId == lesson[index - 1].targetWordId { repeatedWord = true }
        }
        expect(!repeatedKind, "ardışık iki soru aynı tipte değil")
        expect(!repeatedWord, "ardışık iki soru aynı kelime üzerine değil")

        expect(lesson.allSatisfy { !$0.requiresAudio || allAudio.contains($0.audioId ?? "") },
               "ses gerektiren her soru sesi olan kelimeden geliyor")

        let silentLesson = LatvianLessonBuilder.build(
            scene: pack.scenes[0],
            pack: pack,
            progress: progress,
            factory: factory,
            availableAudio: [],
            seed: 7,
            now: epoch
        )
        expect(silentLesson.allSatisfy { !$0.requiresAudio }, "ses yokken dinleme sorusu üretilmiyor")
        expect(silentLesson.count == LatvianLessonBuilder.lessonLength,
               "ses yokken bile ders tam kuruluyor (\(silentLesson.count))")

        let sameSeed = LatvianLessonBuilder.build(
            scene: pack.scenes[0], pack: pack, progress: progress, factory: factory,
            availableAudio: allAudio, seed: 7, now: epoch
        )
        expect(sameSeed == lesson, "aynı tohum birebir aynı dersi veriyor")

        let emptyScene = LatvianScene(id: "bos", index: 99, title: "Boş", words: [], sentences: [])
        expect(LatvianLessonBuilder.build(
            scene: emptyScene, pack: pack, progress: progress, factory: factory,
            availableAudio: allAudio, seed: 7, now: epoch
        ).isEmpty, "kelimesiz sahnede ders kurulmuyor, çökmüyor")
        expect(LatvianLessonBuilder.masteryRatio(scene: emptyScene, progress: progress, now: epoch) == 1,
               "kelimesiz sahne hakimiyet hesabını bölmüyor")

        print("\n=== Gerçek paket üzerinde ders kurgusu ===")

        let firstScene = realPack.scenes[0]
        let firstSceneWordIds = Set(firstScene.words.map(\.id))

        // Hakimiyet iki modaliteyi de istediğine göre, her kelimenin iki modalitede de
        // öğretilebilir olması gerekiyor; yoksa o kelimenin bir kartı hiç açılamaz ve
        // kelime asla hakim sayılamaz. Sesler ilk açılışta iniyor, dolayısıyla asıl
        // sözü verilen durum "tüm sesler elde" hali; kalıcı kontrol bunun üzerinde.
        var missingRecognition: [String] = []
        var missingProduction: [String] = []
        for word in realWords {
            let kinds = realFactory.supportedKinds(forWordId: word.id, availableAudio: realAudio)
            if !kinds.contains(where: { $0.modality == .recognition }) {
                missingRecognition.append(word.id)
            }
            if !kinds.contains(where: { $0.modality == .production }) {
                missingProduction.append(word.id)
            }
        }
        expect(missingRecognition.isEmpty,
               "sesler indiğinde her kelimenin en az bir tanıma sorusu var"
               + (missingRecognition.isEmpty
                  ? ""
                  : " — \(missingRecognition.count) eksik: \(missingRecognition.prefix(5).joined(separator: ", "))"))
        expect(missingProduction.isEmpty,
               "sesler indiğinde her kelimenin en az bir üretim sorusu var"
               + (missingProduction.isEmpty
                  ? ""
                  : " — \(missingProduction.count) eksik: \(missingProduction.prefix(5).joined(separator: ", "))"))

        // Sesler inmeden önceki geçici durum ölçülüyor ama kapı yapılmıyor: cümle tabanlı
        // üretim sorusu olmayan kelimelerin üretim tarafı yalnızca dikte/telaffuz ile,
        // yani sesle öğretilebiliyor. Sayının sessizce büyümesini görmek için basılıyor.
        let silentProductionGap = realWords.filter { word in
            !realFactory.supportedKinds(forWordId: word.id, availableAudio: [])
                .contains { $0.modality == .production }
        }
        print("  sesler inmeden önce üretim sorusu üretemeyen kelime:"
              + " \(silentProductionGap.count)/\(realWords.count)")

        let firstLesson = LatvianLessonBuilder.build(
            scene: firstScene, pack: realPack, progress: LatvianProgress.new(),
            factory: realFactory, availableAudio: realAudio, seed: 11, now: epoch
        )
        expect(firstLesson.count == LatvianLessonBuilder.lessonLength,
               "boş ilerlemede birinci sahne dersi 16 soru (\(firstLesson.count))")
        expect(firstLesson.allSatisfy { firstSceneWordIds.contains($0.targetWordId) },
               "her sorunun hedef kelimesi sahnenin kendi kelimesi")
        expect(Set(firstLesson.map(\.id)).count == firstLesson.count,
               "gerçek pakette aynı soru iki kez girmiyor")

        var realRepeatKind: [String] = []
        var realRepeatWord: [String] = []
        for index in 1..<firstLesson.count {
            if firstLesson[index].kind == firstLesson[index - 1].kind {
                realRepeatKind.append("\(index): \(firstLesson[index].kind.rawValue)")
            }
            if firstLesson[index].targetWordId == firstLesson[index - 1].targetWordId {
                realRepeatWord.append("\(index): \(firstLesson[index].targetWordId)")
            }
        }
        expect(realRepeatKind.isEmpty,
               "gerçek pakette ardışık iki soru aynı tipte değil"
               + (realRepeatKind.isEmpty ? "" : " — \(realRepeatKind.joined(separator: ", "))"))
        expect(realRepeatWord.isEmpty,
               "gerçek pakette ardışık iki soru aynı kelime üzerine değil"
               + (realRepeatWord.isEmpty ? "" : " — \(realRepeatWord.joined(separator: ", "))"))

        // Sesler inmemişken de ders tam kurulmalı: dinleme/dikte/telaffuz düşer ama
        // gerçek pakette her kelimenin ses gerektirmeyen bir sorusu var.
        let silentRealLesson = LatvianLessonBuilder.build(
            scene: firstScene, pack: realPack, progress: LatvianProgress.new(),
            factory: realFactory, availableAudio: [], seed: 11, now: epoch
        )
        expect(silentRealLesson.count == LatvianLessonBuilder.lessonLength,
               "gerçek pakette ses yokken de ders 16 soru (\(silentRealLesson.count))")
        expect(silentRealLesson.allSatisfy { !$0.requiresAudio },
               "ses yokken gerçek pakette de ses gerektiren soru yok")

        let otherSeed = LatvianLessonBuilder.build(
            scene: firstScene, pack: realPack, progress: LatvianProgress.new(),
            factory: realFactory, availableAudio: realAudio, seed: 12, now: epoch
        )
        expect(otherSeed.map(\.id) != firstLesson.map(\.id), "farklı tohum farklı ders veriyor")

        // Kotalar: üç havuz da doluyken 8 yeni / 5 tekrar / 3 hata.
        expect(LatvianLessonBuilder.newQuota == 8, "yeni kotası 8 (%50)")
        expect(LatvianLessonBuilder.reviewQuota == 5, "tekrar kotası 5 (%30)")
        expect(LatvianLessonBuilder.mistakeQuota == 3, "hata kotası 3 (%20)")

        var mixed = LatvianProgress.new()
        for word in realPack.scenes[1].words.prefix(8) {
            for modality in [LatvianModality.recognition, .production] {
                mixed.registerAnswer(wordId: word.id, modality: modality, rating: .good,
                                     scheduler: scheduler, now: epoch)
            }
        }
        for word in realPack.scenes[2].words.prefix(4) {
            mixed.registerAnswer(wordId: word.id, modality: .recognition, rating: .again,
                                 scheduler: scheduler, now: epoch)
        }
        let mixedMoment = epoch.addingTimeInterval(86_400 * 30)
        let mixedPlan = LatvianLessonBuilder.plan(
            scene: firstScene, pack: realPack, progress: mixed, now: mixedMoment
        )
        expect(mixedPlan.count == LatvianLessonBuilder.lessonLength, "plan 16 hedef içeriyor")
        expect(mixedPlan.filter { $0.source == .new }.count == LatvianLessonBuilder.newQuota,
               "yeni kotası doluyor (\(mixedPlan.filter { $0.source == .new }.count))")
        expect(mixedPlan.filter { $0.source == .review }.count == LatvianLessonBuilder.reviewQuota,
               "tekrar kotası doluyor (\(mixedPlan.filter { $0.source == .review }.count))")
        expect(mixedPlan.filter { $0.source == .mistake }.count == LatvianLessonBuilder.mistakeQuota,
               "hata kotası doluyor (\(mixedPlan.filter { $0.source == .mistake }.count))")
        expect(Set(mixedPlan.map(\.debugKey)).count == mixedPlan.count,
               "planda aynı kelime-modalite ikilisi iki kez yok")
        // "Takılan kelimesi olmayan öğrenci bugünkü dersin aynısını alır" güvencesi:
        // yukarıdaki üç kota da bozulmadan doluyor ve kurtarma hiç devreye girmiyor.
        expect(!mixedPlan.contains { $0.source == .leech },
               "takılan kelimesi olmayan öğrencinin dersinde kurtarma yok")

        print("\n=== Takılan kelime: teşhis ve kurtarma ===")

        expect(LatvianLessonBuilder.leechLapseThreshold == 4, "takılma eşiği 4 unutma")
        expect(LatvianLessonBuilder.leechQuota == 4, "kurtarma payı 4 soru")
        expect(LatvianLessonBuilder.leechQuota <= LatvianLessonBuilder.newQuota,
               "kurtarma payı yeni malzeme kotasından kesilebiliyor"
               + " (\(LatvianLessonBuilder.leechQuota) ≤ \(LatvianLessonBuilder.newQuota))")

        // Kolaydan zora sıra kurtarma merdiveninin tek dayanağı; tanıma tarafı üretimin
        // tamamının önünde olmalı, yoksa "en kolay soru" bir üretim sorusu çıkabilir.
        let hardestRecognition = LatvianExerciseKind.allCases
            .filter { $0.modality == .recognition }.map(\.difficultyRank).max() ?? 0
        let easiestProduction = LatvianExerciseKind.allCases
            .filter { $0.modality == .production }.map(\.difficultyRank).min() ?? 0
        expect(hardestRecognition < easiestProduction,
               "zorluk sırasında tüm tanıma tipleri tüm üretim tiplerinin önünde"
               + " (\(hardestRecognition) < \(easiestProduction))")
        expect(Set(LatvianExerciseKind.allCases.map(\.difficultyRank)).count
               == LatvianExerciseKind.allCases.count,
               "her soru tipinin zorluk sırası ayrı")

        /// Elle kurulmuş kart: teşhisin iki koşulunu tek tek sınamak için.
        func stuckCard(stability: Double, lapses: Int, reviews: Int = 60) -> LatvianMemoryCard {
            LatvianMemoryCard(
                stability: stability,
                difficulty: 10,
                dueAt: epoch.addingTimeInterval(stability * 86_400),
                lastReviewedAt: epoch,
                reviewCount: reviews,
                lapseCount: lapses
            )
        }

        expect(LatvianLessonBuilder.isLeech(card: stuckCard(stability: 2.0, lapses: 4)),
               "dört kez unutulup kalıcılığa ulaşamayan kart takılmış sayılıyor")
        expect(!LatvianLessonBuilder.isLeech(card: stuckCard(stability: 2.0, lapses: 3)),
               "üç unutma takılmak için yetmiyor")
        expect(!LatvianLessonBuilder.isLeech(
                card: stuckCard(stability: LatvianLessonBuilder.masteryStabilityDays, lapses: 30)),
               "otuz kez unutulmuş olsa da kararlılığa ulaşan kart takılmış sayılmıyor")
        expect(!LatvianLessonBuilder.isLeech(card: .new()),
               "hiç görülmemiş kart takılmış sayılmıyor")

        // Kurtarmanın sınandığı kelime: en az üç tanıma tipi destekleyen ilk sahne kelimesi.
        // Merdivenin basamakları ancak o zaman ayırt edilebilir.
        let rescueWord = firstScene.words.first { word in
            realFactory.supportedKinds(forWordId: word.id, availableAudio: realAudio)
                .filter { $0.modality == .recognition }.count >= 3
        }
        expect(rescueWord != nil, "gerçek pakette en az üç tanıma tipli bir kelime var")

        if let rescueWord {
            let ladder = realFactory
                .supportedKinds(forWordId: rescueWord.id, availableAudio: realAudio)
                .filter { $0.modality == .recognition }
                .sorted { $0.difficultyRank < $1.difficultyRank }

            /// `mixed` fikstürünün üstüne tek bir takılmış kelime konuyor: kotaların geri
            /// kalanı dolu kaldığından kesintinin nereden yapıldığı doğrudan okunabiliyor.
            func stuckProgress(recognitionStability: Double) -> LatvianProgress {
                var value = mixed
                value.setCard(stuckCard(stability: recognitionStability, lapses: 9),
                              for: memoryKey(rescueWord.id, .recognition))
                value.setCard(stuckCard(stability: 1.2, lapses: 11),
                              for: memoryKey(rescueWord.id, .production))
                return value
            }

            let stuck = stuckProgress(recognitionStability: 1.5)
            expect(LatvianLessonBuilder.isLeech(wordId: rescueWord.id, progress: stuck),
                   "iki tarafı da çökmüş kelime takılmış sayılıyor")
            expect(!LatvianLessonBuilder.isLeech(wordId: rescueWord.id, progress: mixed),
                   "aynı kelime takılmadan önce takılmış sayılmıyor")

            let stuckPlan = LatvianLessonBuilder.plan(
                scene: firstScene, pack: realPack, progress: stuck, now: mixedMoment
            )
            let rescued = stuckPlan.filter { $0.source == .leech }
            expect(stuckPlan.count == LatvianLessonBuilder.lessonLength,
                   "kurtarmalı ders de 16 hedef (\(stuckPlan.count))")
            expect(rescued.count == 1 && rescued.first?.wordId == rescueWord.id,
                   "takılan kelime derse kurtarma kaynağıyla giriyor (\(rescued.count))")
            expect(rescued.first?.modality == .recognition,
                   "kurtarma hedefi tanıma tarafından")
            expect(stuckPlan.filter { $0.source == .new }.count
                   == LatvianLessonBuilder.newQuota - rescued.count,
                   "kurtarma payı yeni malzeme kotasından kesiliyor"
                   + " (\(stuckPlan.filter { $0.source == .new }.count))")
            expect(stuckPlan.filter { $0.source == .review }.count == LatvianLessonBuilder.reviewQuota,
                   "kurtarma tekrar kotasına dokunmuyor"
                   + " (\(stuckPlan.filter { $0.source == .review }.count))")
            expect(stuckPlan.filter { $0.source == .mistake }.count == LatvianLessonBuilder.mistakeQuota,
                   "kurtarma hata kotasına dokunmuyor"
                   + " (\(stuckPlan.filter { $0.source == .mistake }.count))")
            expect(!stuckPlan.contains {
                       $0.wordId == rescueWord.id && $0.source == .new
                   },
                   "takılan kelime ayrıca yeni malzeme olarak da sorulmuyor")

            let stuckLesson = LatvianLessonBuilder.build(
                scene: firstScene, pack: realPack, progress: stuck,
                factory: realFactory, availableAudio: realAudio, seed: 21, now: mixedMoment
            )
            expect(stuckLesson.count == LatvianLessonBuilder.lessonLength,
                   "kurtarmalı ders de 16 soru (\(stuckLesson.count))")
            expect(stuckLesson.first?.targetWordId == rescueWord.id,
                   "ders takılan kelimeyle başlıyor"
                   + " (\(stuckLesson.first?.targetWordId ?? "-"))")
            expect(stuckLesson.first?.modality == .recognition,
                   "takılan kelime üretimle değil tanımayla geri geliyor"
                   + " (\(stuckLesson.first?.kind.rawValue ?? "-"))")
            expect(stuckLesson.first?.kind == ladder.first,
                   "dibe vurmuş kelime merdivenin en kolay basamağından geliyor"
                   + " (\(stuckLesson.first?.kind.rawValue ?? "-")"
                   + " ≟ \(ladder.first?.rawValue ?? "-"))")

            // Toparlanan kart merdivende yukarı çıkıyor: kararlılık eşiğin 5/7'sine
            // geldiğinde üçüncü basamak (kelimenin desteklediği kadarıyla) açılıyor.
            let recovering = stuckProgress(recognitionStability: 5.0)
            expect(LatvianLessonBuilder.isLeech(wordId: rescueWord.id, progress: recovering),
                   "eşiğin altındaki kart toparlanırken hâlâ kurtarma kapsamında")
            let recoveringLesson = LatvianLessonBuilder.build(
                scene: firstScene, pack: realPack, progress: recovering,
                factory: realFactory, availableAudio: realAudio, seed: 21, now: mixedMoment
            )
            let expectedStep = ladder[min(2, ladder.count - 1)]
            expect(recoveringLesson.first?.targetWordId == rescueWord.id,
                   "toparlanan kelime de derse kurtarmayla giriyor")
            expect(recoveringLesson.first?.modality == .recognition,
                   "toparlanma basamağı da tanıma tarafında")
            expect(recoveringLesson.first?.kind == expectedStep,
                   "toparlandıkça daha zor tanıma sorusu geliyor"
                   + " (\(recoveringLesson.first?.kind.rawValue ?? "-")"
                   + " ≟ \(expectedStep.rawValue))")
            expect((recoveringLesson.first?.kind.difficultyRank ?? 0)
                   > (stuckLesson.first?.kind.difficultyRank ?? 0),
                   "toparlanan kartın sorusu dibe vurmuş kartınkinden zor")

            // Kararlılık eşiği geçtiğinde teşhis kendiliğinden kalkıyor: mezuniyet ayrı bir
            // kural değil, `isLeech`in ikinci koşulunun düşmesi. İki taraf da eşiği geçince
            // kelime kurtarmadan tamamen çıkıyor ve kompozisyon eski haline dönüyor.
            var healed = mixed
            let clearedCard = stuckCard(stability: LatvianLessonBuilder.masteryStabilityDays, lapses: 9)
            expect(!LatvianLessonBuilder.isLeech(card: clearedCard),
                   "kararlılık eşiği geçen kart, dokuz unutmaya rağmen takılmış değil")
            healed.setCard(clearedCard, for: memoryKey(rescueWord.id, .recognition))
            healed.setCard(clearedCard, for: memoryKey(rescueWord.id, .production))
            expect(!LatvianLessonBuilder.isLeech(wordId: rescueWord.id, progress: healed),
                   "iki tarafı da eşiği geçen kelime kurtarmadan çıkıyor")
            let healedPlan = LatvianLessonBuilder.plan(
                scene: firstScene, pack: realPack, progress: healed, now: mixedMoment
            )
            expect(!healedPlan.contains { $0.source == .leech },
                   "kurtarılan kelime iyileşince ders kurtarmasız kurgusuna dönüyor")
            expect(healedPlan.filter { $0.source == .new }.count == LatvianLessonBuilder.newQuota,
                   "iyileşince yeni malzeme kotası da tam dolduruluyor"
                   + " (\(healedPlan.filter { $0.source == .new }.count))")

            // En fazla `leechQuota` kadar: takılan kelime sayısı payı aşarsa ders taşmıyor.
            var manyStuck = mixed
            for word in firstScene.words.prefix(9) {
                manyStuck.setCard(stuckCard(stability: 1.5, lapses: 9),
                                  for: memoryKey(word.id, .recognition))
            }
            let manyPlan = LatvianLessonBuilder.plan(
                scene: firstScene, pack: realPack, progress: manyStuck, now: mixedMoment
            )
            expect(manyPlan.count == LatvianLessonBuilder.lessonLength,
                   "dokuz takılan kelimede de ders 16 hedef (\(manyPlan.count))")
            expect(manyPlan.filter { $0.source == .leech }.count == LatvianLessonBuilder.leechQuota,
                   "kurtarma payı aşılmıyor (\(manyPlan.filter { $0.source == .leech }.count))")
            let manyLesson = LatvianLessonBuilder.build(
                scene: firstScene, pack: realPack, progress: manyStuck,
                factory: realFactory, availableAudio: realAudio, seed: 22, now: mixedMoment
            )
            expect(manyLesson.count == LatvianLessonBuilder.lessonLength,
                   "dokuz takılan kelimede de ders 16 soru (\(manyLesson.count))")
            var manyClashes = 0
            for index in 1..<manyLesson.count where manyLesson[index].kind == manyLesson[index - 1].kind
                || manyLesson[index].targetWordId == manyLesson[index - 1].targetWordId {
                manyClashes += 1
            }
            expect(manyClashes == 0,
                   "kurtarma ardışık tekrar üretmiyor (\(manyClashes) çakışma)")
        }

        // Havuz boşken kota devrediyor: boş ilerlemede tekrar ve hata havuzu yok.
        let emptyPlan = LatvianLessonBuilder.plan(
            scene: firstScene, pack: realPack, progress: LatvianProgress.new(), now: epoch
        )
        expect(emptyPlan.count == LatvianLessonBuilder.lessonLength,
               "havuzlar boşken de plan 16 hedefe ulaşıyor (\(emptyPlan.count))")
        expect(emptyPlan.allSatisfy { firstSceneWordIds.contains($0.wordId) },
               "boş ilerlemede tüm hedefler sahneden geliyor")
        expect(emptyPlan.contains { $0.modality == .production },
               "ilk derste üretim tarafı da öğretiliyor")

        print("\n=== Benzetim: tek oturumda her soruyu bilen öğrenci ===")

        // Kapının var oluş sebebi bu benzetim: aynı oturumda arka arkaya ders yapan,
        // her soruyu ilk denemede ve hızlı bilen öğrenci. Sorular arasında 20 saniye
        // geçiyor, gün geçmiyor. "Az önce doğru cevapladım" hakimiyet değildir; bu yol
        // kaç ders sürerse sürsün sahneyi açmamalı.
        //
        // Gerçek FSRS'te bu güvence yapısal: zaman geçmeden yapılan tekrar kararlılığı
        // büyütmediğinden tek oturumda ulaşılabilen en yüksek kararlılık 5.8 gün, eşik ise
        // 7 gün. Buradaki yer tutucu planlayıcı kararlılığı geçen süreden bağımsız
        // çarptığı için aynı yapısal sınıra sahip değil; onda kapıyı tutan, ders kurgusunun
        // tek oturumda dolaşabildiği kelime sayısının sınırlı kalması.
        var sprinter = LatvianProgress.new()
        var sprinterMoment = epoch
        var sprinterUnlockedAt: Int?
        var sprinterPeakRatio = 0.0
        var sprinterAnswers = 0
        let sprintLessons = 20
        for lessonIndex in 1...sprintLessons {
            let questions = LatvianLessonBuilder.build(
                scene: firstScene, pack: realPack, progress: sprinter,
                factory: realFactory, availableAudio: realAudio,
                seed: UInt64(300 + lessonIndex), now: sprinterMoment
            )
            for question in questions {
                sprinterMoment = sprinterMoment.addingTimeInterval(20)
                sprinterAnswers += 1
                sprinter.registerAnswer(
                    wordId: question.targetWordId, modality: question.modality,
                    rating: .easy, scheduler: scheduler, now: sprinterMoment
                )
            }
            // Kilit ders biter bitmez ölçülüyor: kartların en taze olduğu an burası.
            sprinterPeakRatio = max(
                sprinterPeakRatio,
                LatvianLessonBuilder.masteryRatio(scene: firstScene, progress: sprinter, now: sprinterMoment)
            )
            if sprinterUnlockedAt == nil,
               LatvianLessonBuilder.isSceneMastered(scene: firstScene, progress: sprinter, now: sprinterMoment) {
                sprinterUnlockedAt = lessonIndex
            }
        }
        print(String(format: "  %d ders / %d soru / %.0f dakika kesintisiz — en yüksek hakimiyet oranı: %.2f",
                     sprintLessons, sprinterAnswers,
                     sprinterMoment.timeIntervalSince(epoch) / 60, sprinterPeakRatio))
        expect(sprinterAnswers == sprintLessons * LatvianLessonBuilder.lessonLength,
               "tek oturum benzetiminde \(sprinterAnswers) sorunun tamamı cevaplandı")
        expect(sprinterUnlockedAt == nil,
               "tek oturumda \(sprintLessons) ders yapan kusursuz öğrenci sahneyi açamıyor"
               + (sprinterUnlockedAt.map { " — \($0). derste açıldı" } ?? ""))
        expect(sprinterPeakRatio < LatvianLessonBuilder.masteryCoverage,
               String(format: "tek oturumda hakimiyet oranı eşiğin altında kalıyor (%.2f < %.2f)",
                      sprinterPeakRatio, LatvianLessonBuilder.masteryCoverage))
        expect(!LatvianLessonBuilder.isSceneUnlocked(scene: realPack.scenes[1], pack: realPack,
                                                     progress: sprinter, now: sprinterMoment),
               "tek oturum sonunda ikinci sahne hâlâ kilitli")

        print("\n=== Benzetim: günlere yayılan, her soruyu bilen öğrenci ===")

        var learner = LatvianProgress.new()
        var learnerLessonSizes: [Int] = []
        var learnerKindClashes = 0
        var learnerWordClashes = 0
        var unlockedAtLesson: Int?
        var learnerMoment = epoch
        // Aynı kusursuz öğrenci, bu kez günde bir oturum: saat gerçekçi biçimde ilerliyor.
        let learnerLimit = 120
        for lessonIndex in 1...learnerLimit {
            let start = epoch.addingTimeInterval(Double(lessonIndex - 1) * 86_400)
            let questions = LatvianLessonBuilder.build(
                scene: firstScene, pack: realPack, progress: learner,
                factory: realFactory, availableAudio: realAudio,
                seed: UInt64(lessonIndex), now: start
            )
            learnerLessonSizes.append(questions.count)
            for index in 1..<max(1, questions.count) {
                if questions[index].kind == questions[index - 1].kind {
                    learnerKindClashes += 1
                }
                if questions[index].targetWordId == questions[index - 1].targetWordId {
                    learnerWordClashes += 1
                }
            }
            for (offset, question) in questions.enumerated() {
                learnerMoment = start.addingTimeInterval(Double(offset + 1) * 20)
                learner.registerAnswer(
                    wordId: question.targetWordId, modality: question.modality,
                    rating: .easy, scheduler: scheduler, now: learnerMoment
                )
            }
            learner.registerLessonCompleted(now: learnerMoment, calendar: utcCalendar)
            if LatvianLessonBuilder.isSceneMastered(scene: firstScene, progress: learner, now: learnerMoment) {
                learner.registerSceneCompletion(sceneId: firstScene.id, now: learnerMoment)
                unlockedAtLesson = lessonIndex
                break
            }
        }

        let ratio = LatvianLessonBuilder.masteryRatio(scene: firstScene, progress: learner, now: learnerMoment)
        let learnerDays = Int(learnerMoment.timeIntervalSince(epoch) / 86_400) + 1
        print(String(format: "  hakimiyet oranı: %.2f, seri: %d gün, XP: %d",
                     ratio, learner.streakDays, learner.xp))
        if let unlockedAtLesson {
            print("  sahne \(unlockedAtLesson). oturumda açıldı (\(learnerDays) güne yayılmış)")
        } else {
            print("  sahne \(learnerLimit) oturumda açılmadı")
        }

        // Kapının aritmetik tabanı: kapsama eşiğini dolduracak kelimelerin iki kartı da
        // en az `minimumReviews` tekrar görmeli. Bunun altındaki hiçbir ders sayısı yetmez.
        let requiredWords = Int(
            (LatvianLessonBuilder.masteryCoverage * Double(firstScene.words.count)).rounded(.up)
        )
        let minimumLessons = Int(
            (Double(requiredWords * 2 * LatvianLessonBuilder.minimumReviews)
             / Double(LatvianLessonBuilder.lessonLength)).rounded(.up)
        )
        expect(learnerLessonSizes.allSatisfy { $0 == LatvianLessonBuilder.lessonLength },
               "benzetimdeki her ders 16 soru")
        expect(learnerKindClashes == 0,
               "benzetimdeki hiçbir derste ardışık aynı tip yok (\(learnerKindClashes) çakışma)")
        expect(learnerWordClashes == 0,
               "benzetimdeki hiçbir derste ardışık aynı kelime yok (\(learnerWordClashes) çakışma)")
        expect(unlockedAtLesson != nil,
               "günlere yayılan kusursuz öğrenci sahneyi \(learnerLimit) oturum içinde tamamlıyor")
        expect((unlockedAtLesson ?? 0) >= minimumLessons,
               "sahne aritmetik tabandan önce açılmıyor"
               + " (\(unlockedAtLesson ?? 0) ≥ \(minimumLessons) oturum)")
        expect(LatvianLessonBuilder.isSceneUnlocked(scene: realPack.scenes[1], pack: realPack,
                                                    progress: learner, now: learnerMoment),
               "birinci sahne tamamlanınca ikinci sahne açılıyor")
        expect(LatvianLessonBuilder.isSceneUnlocked(
                scene: realPack.scenes[1], pack: realPack, progress: learner,
                now: learnerMoment.addingTimeInterval(86_400 * 3650)),
               "bir kez açılan sahne unutma yüzünden geri kilitlenmiyor")
        expect(!LatvianLessonBuilder.isSceneUnlocked(scene: realPack.scenes[2], pack: realPack,
                                                     progress: learner, now: learnerMoment),
               "üçüncü sahne hâlâ kilitli")
        expect(learner.streakDays == unlockedAtLesson,
               "her gün bir ders yapan öğrencinin serisi ders sayısına eşit (\(learner.streakDays))")

        print("\n=== Benzetim: gerçekçi öğrenci ===")

        // Dört soruda birini yanlış yapan, kalanını zorlanmadan ama hızlı olmadan
        // bilen öğrenci. Kusursuz yolun tek veri noktası olmaması için ölçülüyor.
        var mixedLearner = LatvianProgress.new()
        var mixedUnlockedAt: Int?
        var mixedMomentEnd = epoch
        var answered = 0
        // Kurtarmanın bu izde gerçekten çalıştığının kanıtı: kaç ders kurtarma hedefi
        // taşıdı ve bunların kaçı tanıma tarafından geldi.
        var rescueLessons = 0
        var rescueTargets = 0
        var productionRescues = 0
        let mixedLimit = 200
        for lessonIndex in 1...mixedLimit {
            let start = epoch.addingTimeInterval(Double(lessonIndex - 1) * 86_400)
            let plan = LatvianLessonBuilder.plan(
                scene: firstScene, pack: realPack, progress: mixedLearner, now: start
            )
            let rescues = plan.filter { $0.source == .leech }
            if !rescues.isEmpty { rescueLessons += 1 }
            rescueTargets += rescues.count
            productionRescues += rescues.filter { $0.modality == .production }.count
            let questions = LatvianLessonBuilder.build(
                scene: firstScene, pack: realPack, progress: mixedLearner,
                factory: realFactory, availableAudio: realAudio,
                seed: UInt64(900 + lessonIndex), now: start
            )
            for (offset, question) in questions.enumerated() {
                answered += 1
                mixedMomentEnd = start.addingTimeInterval(Double(offset + 1) * 20)
                mixedLearner.registerAnswer(
                    wordId: question.targetWordId, modality: question.modality,
                    rating: answered % 4 == 0 ? .again : .good,
                    scheduler: scheduler, now: mixedMomentEnd
                )
            }
            if LatvianLessonBuilder.isSceneMastered(scene: firstScene, progress: mixedLearner, now: mixedMomentEnd) {
                mixedUnlockedAt = lessonIndex
                break
            }
        }
        if let mixedUnlockedAt {
            print("  sahne \(mixedUnlockedAt). oturumda açıldı"
                  + " (\(mixedUnlockedAt * LatvianLessonBuilder.lessonLength) soru,"
                  + " \(mixedUnlockedAt) güne yayılmış)")
        } else {
            print("  sahne \(mixedLimit) oturumda açılmadı")
        }
        print("  kurtarma: \(rescueLessons) derste \(rescueTargets) hedef")
        expect(mixedUnlockedAt != nil, "gerçekçi öğrenci de sahneyi eninde sonunda tamamlıyor")
        expect((mixedUnlockedAt ?? 0) > (unlockedAtLesson ?? 0),
               "yanlış yapan öğrenci kusursuz öğrenciden daha çok ders yapıyor"
               + " (\(mixedUnlockedAt ?? 0) > \(unlockedAtLesson ?? 0))")
        // Üst sınır, kapının asıl arızasına karşı: ölçüm sırasında (7 günlük kararlılık
        // eşiği, yer tutucu planlayıcı) bu öğrenci 44. oturumda geçiyordu. Kurtarma
        // eklendikten sonra yeniden ölçüldü: yine 44. oturum. Kapı ya da planlayıcı
        // bozulup öğrenciyi sonsuza dek "biraz daha çalış" durumunda bırakırsa bu satır
        // sessiz kalmasın diye ölçülen değerin biraz üstüne bir tavan konuyor.
        let mixedBudget = 60
        expect((mixedUnlockedAt ?? mixedLimit) <= mixedBudget,
               "gerçekçi öğrenci makul sürede geçiyor"
               + " (\(mixedUnlockedAt ?? mixedLimit) ≤ \(mixedBudget) oturum)")
        // Kurtarma bu izde sessizce kapanırsa yukarıdaki tavan bunu yakalamaz: dört soruda
        // birini yanlış yapan öğrencide takılan kelime **çıkması** gerekiyor ve kurtarma
        // devreye **girmesi** gerekiyor. Sayı ölçülene değil sıfırdan büyüklüğe bağlanıyor;
        // ders kurgusundaki her ayar kaç kelimenin takıldığını değiştirir, ama "hiç
        // kurtarma yok" bu öğrenci profilinde arıza demektir.
        expect(rescueLessons > 0,
               "gerçekçi öğrencide kurtarma devreye giriyor (\(rescueLessons) ders)")
        expect(productionRescues == 0,
               "kurtarma hedeflerinin hiçbiri üretim tarafından değil (\(productionRescues))")

        print("\n=== Benzetim: her soruyu yanlış yapan öğrenci ===")

        var struggler = LatvianProgress.new()
        var strugglerLessons: [[String]] = []
        var strugglerPeakRatio = 0.0
        var strugglerKindClashes = 0
        var strugglerWordClashes = 0
        var strugglerRescueLessons = 0
        var strugglerRescueTargets = 0
        for lessonIndex in 1...20 {
            let start = epoch.addingTimeInterval(Double(lessonIndex - 1) * 86_400)
            let strugglerPlan = LatvianLessonBuilder.plan(
                scene: firstScene, pack: realPack, progress: struggler, now: start
            )
            let strugglerRescues = strugglerPlan.filter { $0.source == .leech }
            if !strugglerRescues.isEmpty { strugglerRescueLessons += 1 }
            strugglerRescueTargets = max(strugglerRescueTargets, strugglerRescues.count)
            let questions = LatvianLessonBuilder.build(
                scene: firstScene, pack: realPack, progress: struggler,
                factory: realFactory, availableAudio: realAudio,
                seed: UInt64(500 + lessonIndex), now: start
            )
            strugglerLessons.append(questions.map(\.targetWordId))
            for index in 1..<max(1, questions.count) {
                if questions[index].kind == questions[index - 1].kind { strugglerKindClashes += 1 }
                if questions[index].targetWordId == questions[index - 1].targetWordId {
                    strugglerWordClashes += 1
                }
            }
            for (offset, question) in questions.enumerated() {
                struggler.registerAnswer(
                    wordId: question.targetWordId, modality: question.modality,
                    rating: .again, scheduler: scheduler,
                    now: start.addingTimeInterval(Double(offset + 1) * 20)
                )
            }
            // Sahne kilidi ders biter bitmez de bakılabilir; yanlış cevaplanan kart o
            // anda "az önce görüldü" olduğundan hatırlanma olasılığı tavana yakındır.
            // Kilit bu boşluktan açılmamalı.
            let endOfLesson = start.addingTimeInterval(Double(questions.count + 1) * 20)
            strugglerPeakRatio = max(
                strugglerPeakRatio,
                LatvianLessonBuilder.masteryRatio(scene: firstScene, progress: struggler, now: endOfLesson)
            )
        }
        print(String(format: "  ders sonunda ölçülen en yüksek hakimiyet oranı: %.2f", strugglerPeakRatio))
        expect(strugglerPeakRatio < LatvianLessonBuilder.masteryCoverage,
               String(format: "yanlış cevaplanan ders bittiği anda bile sahneyi açmıyor (%.2f)", strugglerPeakRatio))
        let strugglerMoment = epoch.addingTimeInterval(86_400 * 20)
        expect(strugglerLessons.allSatisfy { $0.count == LatvianLessonBuilder.lessonLength },
               "yanlış yapan öğrencide de her ders 16 soru")
        expect(strugglerKindClashes == 0 && strugglerWordClashes == 0,
               "yanlış yapan öğrencide de ardışık tekrar yok"
               + " (\(strugglerKindClashes) tip, \(strugglerWordClashes) kelime çakışması)")
        expect(LatvianLessonBuilder.masteryRatio(scene: firstScene, progress: struggler, now: strugglerMoment) == 0,
               "hep yanlış yapan öğrencide hakimiyet oranı sıfır")
        expect(!LatvianLessonBuilder.isSceneMastered(scene: firstScene, progress: struggler, now: strugglerMoment),
               "hep yanlış yapan öğrencide sahne tamamlanmıyor")
        expect(!LatvianLessonBuilder.isSceneUnlocked(scene: realPack.scenes[1], pack: realPack,
                                                     progress: struggler, now: strugglerMoment),
               "hep yanlış yapan öğrencide ikinci sahne açılmıyor")
        let lastOverlap = Set(strugglerLessons[18]).intersection(Set(strugglerLessons[19])).count
        print("  son iki dersin ortak kelime sayısı: \(lastOverlap)")
        expect(lastOverlap >= 8,
               "ders kurgusu aynı zayıf kelimelere dönüyor (\(lastOverlap) ortak kelime)")
        expect(struggler.recentMistakes.count <= LatvianProgress.mistakeMemory,
               "hata listesi 20 dersten sonra da sınırlı (\(struggler.recentMistakes.count))")
        // Her soruyu yanlış yapan öğrencide sahnenin tamamı takılıyor; kurtarma en çok
        // payı kadar yer alıyor ve geri kalan kotalar çalışmaya devam ediyor.
        print("  kurtarma: \(strugglerRescueLessons)/20 derste, en çok \(strugglerRescueTargets) hedef")
        expect(strugglerRescueLessons > 0,
               "hep yanlış yapan öğrencide kurtarma devreye giriyor"
               + " (\(strugglerRescueLessons) ders)")
        expect(strugglerRescueTargets <= LatvianLessonBuilder.leechQuota,
               "hep yanlış yapan öğrencide de kurtarma payı aşılmıyor"
               + " (\(strugglerRescueTargets) ≤ \(LatvianLessonBuilder.leechQuota))")

        print("\n=== Ders kurma bütçesi ===")

        var lessonQuestionTotal = 0
        let lessonTiming = measure {
            for index in 0..<10 {
                lessonQuestionTotal += LatvianLessonBuilder.build(
                    scene: firstScene, pack: realPack, progress: learner,
                    factory: realFactory, availableAudio: realAudio,
                    seed: UInt64(index + 1), now: learnerMoment
                ).count
            }
        }
        expect(lessonQuestionTotal == 10 * lessonTiming.all.count * LatvianLessonBuilder.lessonLength,
               "bütçe ölçümünde derslerin tamamı kuruldu (\(lessonQuestionTotal) soru)")
        let perLesson = lessonTiming.best / 10
        print("  10 ders kurulumu: \(format(lessonTiming.all)) ms"
              + String(format: " (ders başına en iyi %.3f ms, bütçe 15 ms)", perLesson))
        expect(perLesson < 15,
               String(format: "ders kurma bütçesi: %.3f ms < 15 ms", perLesson))

        if failures > 0 {
            fputs("\n\(failures) kontrol başarısız.\n", stderr)
            exit(1)
        }
        print("\nLetonca birim kontrolleri ve paket taraması geçti.\n")
    }
}
