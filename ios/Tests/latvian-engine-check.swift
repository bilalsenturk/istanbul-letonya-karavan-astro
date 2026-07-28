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

/// Benzetim öğrencisinin hata modeli: her soruda `errorRate` olasılıkla `again`, kalanında
/// `good`.
///
/// Eski model **konumsaldı** (`cevaplanan % n == 0`): hata sorunun ne olduğuna değil
/// kaçıncı sırada sorulduğuna bağlıydı, yani ders sıralamasına faz kilitliydi. İki sonucu
/// vardı ve ikisi de ölçümü bozuyordu: ders içi sıralamayı değiştiren her düzeltme hangi
/// kelimenin sonsuza dek hata konumuna denk geleceğini yeniden dağıtıyordu, ve ders tohumu
/// hangi **kartın** sorulacağını değiştirmediği için tohumlar arası varyans sıfırdı — 0.80
/// eşiğinin yakınındaki her satır tek bir desenin fonksiyonuydu.
///
/// Bu model hatayı tohumlu üreteçten çekiyor: aynı tohum aynı koşuyu tekrar üretir (test
/// belirlenimci kalır) ama farklı tohumlar gerçekten farklı koşular verir, dolayısıyla
/// sonuç bir aralık olarak raporlanabilir.
struct LatvianSimulatedLearner {
    private var generator: LatvianSeededGenerator
    private let errorRate: Double

    init(seed: UInt64, errorRate: Double) {
        generator = LatvianSeededGenerator(seed: seed &* 6_700_417 &+ 11)
        self.errorRate = errorRate
    }

    mutating func nextRating() -> LatvianRating {
        Double.random(in: 0..<1, using: &generator) < errorRate ? .again : .good
    }
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

// MARK: - Ders oturumu için cevap üreticileri

/// Soruyu doğru cevaplayan yanıt. Gerçek paketten kurulan bir dersi baştan sona
/// oynayabilmek için gerekiyor: her soru tipinin cevabı farklı bir `LatvianAnswer` kipi.
func correctAnswer(for exercise: LatvianExercise) -> LatvianAnswer {
    switch exercise.content {
    case .choice(_, let correctIndex): return .choice(index: correctIndex)
    case .wordBank(_, let answer): return .words(answer)
    case .matching(let pairs): return .pairs(pairs)
    case .typing(let accepted): return .text(accepted.first ?? "")
    case .speaking(let target): return .spoken(transcript: target)
    }
}

/// Soruyu kesinlikle yanlış cevaplayan yanıt. "Kesinlikle" önemli: oturum testleri
/// belirli sayıda can kaybı bekliyor, dolayısıyla yanlışın tesadüfen doğru çıkması
/// ölçümü bozardı. Testler ayrıca bu iki üreticiyi gerçek ders üzerinde notlatarak
/// doğruluyor (bkz. "üreticiler gerçek ders üzerinde doğrulanıyor").
func wrongAnswer(for exercise: LatvianExercise) -> LatvianAnswer {
    switch exercise.content {
    case .choice(let options, let correctIndex):
        // Seçenekler birbirinden farklı (paket taraması bunu ayrıca sınıyor), yani
        // doğru dizinden başka herhangi bir dizin yanlış. Tek seçenekli soru üretilmiyor;
        // yine de aralık dışı bir dizin de yanlış sayıldığı için geri düşüş güvenli.
        return .choice(index: options.indices.first { $0 != correctIndex } ?? correctIndex + 1)
    case .wordBank(_, let answer):
        // Sırayı ters çevirmek tek kelimelik cevapta doğruyu verirdi; fazladan bir
        // kelime her durumda yanlış.
        return .words(answer + ["zzz"])
    case .matching(let pairs):
        // Çift sayısı tutmayan cevap doğrudan yanlış sayılıyor.
        return .pairs(Array(pairs.dropLast()))
    case .typing(let accepted):
        return .text((accepted.first ?? "") + " zzz")
    case .speaking(let target):
        return .spoken(transcript: target + " zzz")
    }
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

        print("\n=== İlerleme göstergesi ===")

        // Gösterge ile kapı iki ayrı sayı: kapı tam/tam sayıyor, gösterge mesafe ölçüyor.
        // Aşağıdaki kontroller ikisinin bağını tek tek bağlıyor.
        let scene = pack.scenes[0]
        let sceneWordCount = Set(scene.words.map(\.id)).count
        let neededWords = LatvianLessonBuilder.masteredWordsNeeded(in: sceneWordCount)
        expect(neededWords > 0 && neededWords <= sceneWordCount
               && Double(neededWords) / Double(sceneWordCount) >= LatvianLessonBuilder.masteryCoverage
               && Double(neededWords - 1) / Double(sceneWordCount) < LatvianLessonBuilder.masteryCoverage,
               "kapıyı açan en az kelime sayısı kapsama eşiğiyle birebir aynı aritmetikten çıkıyor "
               + "(\(neededWords)/\(sceneWordCount))")

        expect(LatvianLessonBuilder.masteryProgress(
                scene: scene, progress: LatvianProgress.new(), now: epoch) == 0,
               "hiç dokunulmamış ilerlemede gösterge sıfır")
        expect(LatvianLessonBuilder.masteryProgress(card: nil) == 0, "kartsız modalitede gösterge sıfır")

        // Kart düzeyi: iki koşul da tek tek bağlayıcı, gösterge ikisinin küçüğü.
        var halfway = LatvianMemoryCard.new()
        halfway.stability = LatvianLessonBuilder.masteryStabilityDays / 2
        halfway.reviewCount = LatvianLessonBuilder.minimumReviews
        expect(abs(LatvianLessonBuilder.masteryProgress(card: halfway) - 0.5) < 1e-9,
               "kararlılığın yarısındaki kart göstergede yarı yolda")
        var stableButUnproven = halfway
        stableButUnproven.stability = LatvianLessonBuilder.masteryStabilityDays * 3
        stableButUnproven.reviewCount = 1
        expect(LatvianLessonBuilder.masteryProgress(card: stableButUnproven) < 1
               && !LatvianLessonBuilder.isMastered(card: stableButUnproven),
               "kararlılığı fazlasıyla yeten ama tek tekrarlı kart göstergeyi doldurmuyor")
        var provenButShaky = halfway
        provenButShaky.reviewCount = 20
        expect(LatvianLessonBuilder.masteryProgress(card: provenButShaky) < 1,
               "yirmi tekrar eksik kararlılığı kapatmıyor")
        var atGate = halfway
        atGate.stability = LatvianLessonBuilder.masteryStabilityDays
        expect(LatvianLessonBuilder.masteryProgress(card: atGate) == 1
               && LatvianLessonBuilder.isMastered(card: atGate),
               "kapıyı tam karşılayan kartta gösterge tam dolu")
        var farPast = atGate
        farPast.stability = LatvianLessonBuilder.masteryStabilityDays * 10
        farPast.reviewCount = 50
        expect(LatvianLessonBuilder.masteryProgress(card: farPast) == 1,
               "kapıyı fazlasıyla geçen kart göstergeyi 1'in üstüne çıkarmıyor")
        var brokenCard = atGate
        brokenCard.stability = .nan
        expect(LatvianLessonBuilder.masteryProgress(card: brokenCard) == 0,
               "bozuk kayıttan gelen NaN kararlılık göstergeyi bozmuyor")

        // Kelime düzeyi: iki taraf da isteniyor, dolayısıyla tek taraf tam yolun yarısı.
        expect(abs(LatvianLessonBuilder.masteryProgress(
                    wordId: pack.scenes[0].words[0].id, progress: recognitionOnly, now: epoch) - 0.5) < 1e-9,
               "yalnızca tanıma tarafı hakim olan kelime göstergede tam yarıda")

        // Monoton yükseliş: kartlar kararlılık kazandıkça gösterge hiç düşmüyor ve
        // gerçekten kıpırdıyor. Kapıya varmadan 1 olmuyor, vardığı anda 1 oluyor.
        var climbing = LatvianProgress.new()
        var previousProgress = LatvianLessonBuilder.masteryProgress(
            scene: scene, progress: climbing, now: epoch
        )
        var sawRise = false
        var brokeMonotonicity = false
        var claimedEarly = false
        var openedAt: (step: Int, progress: Double)?
        var step = 0
        for word in scene.words {
            for stability in stride(from: 1.0, through: LatvianLessonBuilder.masteryStabilityDays, by: 2.0) {
                var card = LatvianMemoryCard.new()
                card.stability = stability
                card.reviewCount = LatvianLessonBuilder.minimumReviews
                for modality in [LatvianModality.recognition, .production] {
                    climbing.setCard(card, for: memoryKey(word.id, modality))
                }
                step += 1
                let value = LatvianLessonBuilder.masteryProgress(scene: scene, progress: climbing, now: epoch)
                let isOpen = LatvianLessonBuilder.isSceneMastered(scene: scene, progress: climbing, now: epoch)
                if value < previousProgress - 1e-9 { brokeMonotonicity = true }
                if value > previousProgress + 1e-9 { sawRise = true }
                if value >= 1, !isOpen { claimedEarly = true }
                if isOpen, openedAt == nil { openedAt = (step, value) }
                previousProgress = value
            }
        }
        expect(!brokeMonotonicity, "kartlar kararlılık kazandıkça gösterge hiç geri gitmiyor")
        expect(sawRise, "gösterge tek bir kelime bile çizgiyi geçmeden yükselmeye başlıyor")
        expect(!claimedEarly, "gösterge kapı açılmadan hiçbir adımda 1'e ulaşmıyor")
        expect(openedAt.map { abs($0.progress - 1) < 1e-9 } ?? false,
               "kapı açıldığı adımda gösterge tam olarak 1 "
               + String(format: "(%.4f)", openedAt?.progress ?? -1))

        // Kapının hemen altı: kapsamayı bir kelimeyle kaçıran sahnede gösterge yüksek
        // ama 1 DEĞİL — arayüz "tamamlandı" diyemesin diye.
        func progressWithMasteredWords(_ count: Int) -> LatvianProgress {
            var result = LatvianProgress.new()
            var full = LatvianMemoryCard.new()
            full.stability = LatvianLessonBuilder.masteryStabilityDays
            full.reviewCount = LatvianLessonBuilder.minimumReviews
            for word in scene.words.prefix(count) {
                for modality in [LatvianModality.recognition, .production] {
                    result.setCard(full, for: memoryKey(word.id, modality))
                }
            }
            return result
        }
        for masteredCount in 0...sceneWordCount {
            let state = progressWithMasteredWords(masteredCount)
            let value = LatvianLessonBuilder.masteryProgress(scene: scene, progress: state, now: epoch)
            let isOpen = LatvianLessonBuilder.isSceneMastered(scene: scene, progress: state, now: epoch)
            expect((value >= 1) == isOpen,
                   String(format: "%d/%d hakim kelimede gösterge (%.3f) ile kapı (%@) aynı şeyi söylüyor",
                          masteredCount, sceneWordCount, value, isOpen ? "açık" : "kapalı"))
            expect(value <= 1 + 1e-9, "gösterge hiçbir durumda 1'i aşmıyor")
        }

        // Kelimelerin HEPSİ kapsama eşiği kadar ilerlemişken gösterge dolmamalı: hiç
        // kelime çizgiyi geçmedi, dolayısıyla kapı da kapalı.
        var uniformlyClose = LatvianProgress.new()
        var closeCard = LatvianMemoryCard.new()
        closeCard.stability = LatvianLessonBuilder.masteryStabilityDays - 0.01
        closeCard.reviewCount = LatvianLessonBuilder.minimumReviews
        for word in scene.words {
            for modality in [LatvianModality.recognition, .production] {
                uniformlyClose.setCard(closeCard, for: memoryKey(word.id, modality))
            }
        }
        let closeValue = LatvianLessonBuilder.masteryProgress(scene: scene, progress: uniformlyClose, now: epoch)
        expect(closeValue < 1 && closeValue > 0.9
               && LatvianLessonBuilder.masteryRatio(scene: scene, progress: uniformlyClose, now: epoch) == 0,
               String(format: "hepsi çizginin bir tık altındaki sahnede gösterge yüksek ama dolu değil (%.4f)",
                      closeValue))

        // Gösterge de kapı gibi sorgu anını okumuyor.
        expect(LatvianLessonBuilder.masteryProgress(scene: scene, progress: climbing, now: staleMoment)
               == LatvianLessonBuilder.masteryProgress(scene: scene, progress: climbing, now: epoch),
               "gösterge sorgu anına bağlı değil")
        expect(LatvianLessonBuilder.masteryProgress(
                scene: LatvianScene(id: "bos-gosterge", index: 98, title: "Boş", words: [], sentences: []),
                progress: progress, now: epoch) == 1,
               "kelimesiz sahnede gösterge de kapı gibi 1")
        expect(LatvianLessonBuilder.masteredWordsNeeded(in: 0) == 0,
               "kelimesiz sahne kapı hesabını bölmüyor")

        print("\n=== Demlenme ===")

        let untouchedRest = LatvianSceneRest(restingWordCount: 0, readyAt: nil, hasWorkNow: true)
        expect(LatvianLessonBuilder.rest(scene: scene, progress: LatvianProgress.new(), now: epoch) == untouchedRest,
               "hiç çalışılmamış sahnede demlenen kelime yok ama yapılacak iş var")

        // Kusuru üreten durum: her kelimenin iki tarafı da çalışılmış, hiçbirinin vadesi
        // gelmemiş, hiçbiri hâlâ hakim değil. Ders yeni bir şey öğretemez.
        var soaking = LatvianProgress.new()
        var soakingCard = LatvianMemoryCard.new()
        soakingCard.stability = 5.9
        soakingCard.reviewCount = 4
        soakingCard.lastReviewedAt = epoch
        soakingCard.dueAt = epoch.addingTimeInterval(86_400 * 5.9)
        for word in scene.words {
            for modality in [LatvianModality.recognition, .production] {
                soaking.setCard(soakingCard, for: memoryKey(word.id, modality))
            }
        }
        let soakingRest = LatvianLessonBuilder.rest(scene: scene, progress: soaking, now: epoch)
        expect(soakingRest.restingWordCount == sceneWordCount && !soakingRest.hasWorkNow
               && soakingRest.readyAt == soakingCard.dueAt,
               "bir oturumda kusursuz çalışılmış sahnenin tamamı demleniyor, en erken vade bildiriliyor "
               + "(\(soakingRest.restingWordCount) kelime)")
        expect(LatvianLessonBuilder.masteryProgress(scene: scene, progress: soaking, now: epoch) > 0.8
               && !LatvianLessonBuilder.isSceneMastered(scene: scene, progress: soaking, now: epoch),
               String(format: "aynı durumda halka dolmaya yakın ama durak açılmıyor (%.3f)",
                      LatvianLessonBuilder.masteryProgress(scene: scene, progress: soaking, now: epoch)))

        // Vade geldiğinde iş geri geliyor ve kelime artık demlenmiyor.
        let afterRest = LatvianLessonBuilder.rest(
            scene: scene, progress: soaking, now: soakingCard.dueAt
        )
        expect(afterRest.hasWorkNow && afterRest.restingWordCount == 0,
               "vade geldiğinde demlenme bitiyor, sahnede yapılacak iş oluyor")

        // Hakim kelime demlenmiyor: bekleyecek bir şeyi kalmadı.
        var settled = soaking
        var settledCard = soakingCard
        settledCard.stability = LatvianLessonBuilder.masteryStabilityDays
        settledCard.dueAt = epoch.addingTimeInterval(86_400 * 30)
        for modality in [LatvianModality.recognition, .production] {
            settled.setCard(settledCard, for: memoryKey(scene.words[0].id, modality))
        }
        expect(LatvianLessonBuilder.rest(scene: scene, progress: settled, now: epoch).restingWordCount
               == sceneWordCount - 1,
               "çizgiyi geçen kelime demlenenler arasında sayılmıyor")

        // Tek tarafı hiç tanıtılmamış kelime demlenmiyor: o taraf bugün öğretilebilir.
        var halfIntroduced = soaking
        halfIntroduced.setCard(.new(), for: memoryKey(scene.words[1].id, .production))
        var stripped = LatvianProgress.new()
        for entry in halfIntroduced.allCards()
        where !(entry.key.wordId == scene.words[1].id && entry.key.modality == .production) {
            stripped.setCard(entry.card, for: entry.key)
        }
        let strippedRest = LatvianLessonBuilder.rest(scene: scene, progress: stripped, now: epoch)
        expect(strippedRest.hasWorkNow && strippedRest.restingWordCount == sceneWordCount - 1,
               "bir tarafı hiç tanıtılmamış kelime demlenmiyor, sahnede iş sayılıyor")

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

        print("\n=== Telaffuz sorusu olmayan cihaz ===")

        // Apple'ın konuşma tanıması Letoncayı hiç içermiyor: `SFSpeechRecognizer(locale: "lv-LV")`
        // her cihazda `nil`. Uygulama bu yüzden dersi `.speak` dışlanmış olarak kuruyor
        // (bkz. `LatvianSpeechAvailability`). Sınanan dört şey var: soru gerçekten düşüyor mu,
        // ders kısalıyor mu, hakimiyet kapısı hâlâ kapanabiliyor mu, ve dışlama listesi
        // boşken hiçbir şey değişmiyor mu.
        let noSpeak: Set<LatvianExerciseKind> = [.speak]

        // Takılmış kart da denenmeli: kurtarma merdiveni tipleri ayrı bir yerde sıralıyor,
        // süzgeç oradan geçen dersi de kesmeli.
        var stressed = LatvianProgress.new()
        for (index, word) in realWords.enumerated() where index % 3 == 0 {
            stressed.registerAnswer(
                wordId: word.id, modality: index % 2 == 0 ? .recognition : .production,
                rating: index % 5 == 0 ? .again : .good, scheduler: scheduler, now: epoch
            )
        }
        for (index, word) in realWords.enumerated() where index % 7 == 0 {
            for round in 0..<5 {
                stressed.registerAnswer(
                    wordId: word.id, modality: .recognition, rating: .again,
                    scheduler: scheduler, now: epoch.addingTimeInterval(Double(round) * 3600)
                )
            }
        }

        var speakLeaks: [String] = []
        var shortenedLessons: [String] = []
        var emptyExclusionDrift: [String] = []
        var speakInUnfiltered = 0
        let excludedMoment = epoch.addingTimeInterval(86_400 * 10)
        for scene in realPack.scenes {
            for (label, state) in [("boş", LatvianProgress.new()), ("takılmış", stressed)] {
                let seed = UInt64(scene.index) &* 97 &+ (label == "boş" ? 0 : 1)
                let full = LatvianLessonBuilder.build(
                    scene: scene, pack: realPack, progress: state, factory: realFactory,
                    availableAudio: realAudio, seed: seed, now: excludedMoment
                )
                let muted = LatvianLessonBuilder.build(
                    scene: scene, pack: realPack, progress: state, factory: realFactory,
                    availableAudio: realAudio, seed: seed, now: excludedMoment,
                    excludedKinds: noSpeak
                )
                let untouched = LatvianLessonBuilder.build(
                    scene: scene, pack: realPack, progress: state, factory: realFactory,
                    availableAudio: realAudio, seed: seed, now: excludedMoment,
                    excludedKinds: []
                )
                speakInUnfiltered += full.filter { $0.kind == .speak }.count
                if muted.contains(where: { $0.kind == .speak }) {
                    speakLeaks.append("\(scene.id)/\(label)")
                }
                if muted.count != full.count {
                    shortenedLessons.append("\(scene.id)/\(label): \(muted.count)/\(full.count)")
                }
                if untouched != full { emptyExclusionDrift.append("\(scene.id)/\(label)") }
            }
        }

        // Süzgeç sınanmadan geçmesin: dışlama olmadan kurulan derslerde telaffuz sorusu
        // gerçekten çıkıyor olmalı, yoksa "hiç yok" iddiası boş bir iddia olurdu.
        expect(speakInUnfiltered > 0,
               "dışlama olmadan telaffuz sorusu gerçekten çıkıyor (\(speakInUnfiltered) soru)")
        expect(speakLeaks.isEmpty,
               "`.speak` dışlanınca hiçbir derste telaffuz sorusu kalmıyor"
               + (speakLeaks.isEmpty ? "" : " — \(speakLeaks.joined(separator: ", "))"))
        expect(shortenedLessons.isEmpty,
               "telaffuz düşünce ders kısalmıyor, yerini başka soru alıyor"
               + (shortenedLessons.isEmpty ? "" : " — \(shortenedLessons.joined(separator: ", "))"))
        expect(emptyExclusionDrift.isEmpty,
               "boş dışlama listesi dersi birebir aynı bırakıyor"
               + (emptyExclusionDrift.isEmpty ? "" : " — \(emptyExclusionDrift.joined(separator: ", "))"))
        expect(LatvianLessonBuilder.build(
            scene: firstScene, pack: realPack, progress: LatvianProgress.new(),
            factory: realFactory, availableAudio: realAudio, seed: 11, now: epoch,
            excludedKinds: []
        ) == firstLesson, "boş dışlama listesi, argümansız çağrıyla aynı dersi veriyor")

        // Asıl mesele bu: telaffuz düşünce hakimiyet kapısı hâlâ kapanıyor mu? Sahne kilidi
        // her kelimeden hem tanıma hem üretim istiyor; bir kelimenin **tek** üretim sorusu
        // telaffuz olsaydı o kelimenin üretim kartı hiç açılamaz ve sahne sonsuza dek kilitli
        // kalırdı. Fikstür üzerinde değil, sevk edilen paketin 259 kelimesinin tamamında.
        var speechlessWithoutSpeak: [String] = []
        var productionlessWithoutSpeak: [String] = []
        for word in realWords {
            let kinds = realFactory
                .supportedKinds(forWordId: word.id, availableAudio: realAudio)
                .filter { !noSpeak.contains($0) }
            if kinds.isEmpty { speechlessWithoutSpeak.append(word.id) }
            if !kinds.contains(where: { $0.modality == .production }) {
                productionlessWithoutSpeak.append(word.id)
            }
        }
        expect(speechlessWithoutSpeak.isEmpty,
               "telaffuz düşünce hiçbir kelime tüm soru tiplerini kaybetmiyor"
               + (speechlessWithoutSpeak.isEmpty
                  ? " (\(realWords.count) kelime)"
                  : " — \(speechlessWithoutSpeak.count) eksik: "
                    + speechlessWithoutSpeak.prefix(5).joined(separator: ", ")))
        expect(productionlessWithoutSpeak.isEmpty,
               "telaffuz düşünce her kelimenin hâlâ en az bir üretim sorusu var —"
               + " hakimiyet kapısı kapanmaya devam ediyor"
               + (productionlessWithoutSpeak.isEmpty
                  ? " (\(realWords.count) kelime)"
                  : " — \(productionlessWithoutSpeak.count) eksik: "
                    + productionlessWithoutSpeak.prefix(5).joined(separator: ", ")))

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

        print("\n=== Takılan kartın sıfırlanması (planlayıcı) ===")

        // Kural planlayıcının içinde durduğu için bu bölüm `LatvianDefaultScheduler`
        // üzerinden sınanıyor; `LatvianFSRSScheduler` aynı `LatvianLeechReset.applied`
        // çağrısını yapıyor (bkz. `LatvianFSRSAdapter.swift`), dolayısıyla sınanan kural
        // ikisinde de aynı.
        let freshCard = LatvianMemoryCard.new()
        expect(LatvianLeechReset.lapseSpacing == 2,
               "iki sıfırlama arasında en az iki unutma (\(LatvianLeechReset.lapseSpacing))")

        // Tam eşikteki takılan kart, bir kez daha unutuluyor.
        let atThreshold = stuckCard(stability: 2.0, lapses: LatvianLessonBuilder.leechLapseThreshold)
        expect(LatvianLessonBuilder.isLeech(card: atThreshold), "sınanan kart gerçekten takılmış")
        let firstReset = scheduler.review(card: atThreshold, rating: .again, now: epoch)
        expect(firstReset.stability == freshCard.stability,
               "takılan kart yeniden unutulunca kararlılığı taze kartınkine dönüyor"
               + String(format: " (%.3f)", firstReset.stability))
        expect(firstReset.difficulty == freshCard.difficulty,
               "sıfırlanan kartın zorluğu taze kartınkine dönüyor"
               + String(format: " (%.1f → %.1f)", atThreshold.difficulty, firstReset.difficulty))
        expect(firstReset.lapseCount == atThreshold.lapseCount + 1,
               "sıfırlama unutma sayacını silmiyor, biriktirmeye devam ediyor"
               + " (\(firstReset.lapseCount))")
        expect(firstReset.reviewCount == atThreshold.reviewCount + 1,
               "sıfırlama tekrar sayacını da koruyor (\(firstReset.reviewCount))")
        expect(firstReset.reviewCount >= LatvianLessonBuilder.minimumReviews,
               "sıfırlanan kart hakimiyet kapısının tekrar sayısı koşulunu kaybetmiyor")
        expect(firstReset.dueAt > epoch, "sıfırlanan kart yine ileri bir vade alıyor")
        expect(firstReset.lastReviewedAt == epoch, "sıfırlanan kartın son tekrar anı cevabın anı")
        expect(LatvianLessonBuilder.isLeech(card: firstReset),
               "sıfırlanan kart hâlâ takılmış sayılıyor: kurtarma payı onu öğretmeye devam ediyor")

        // Aynı kart hemen ardından bir kez daha unutuluyor: aralık kuralı ikinci
        // sıfırlamayı engelliyor, yoksa kart kalıcı olarak taze durumda donardı.
        let noSecondReset = scheduler.review(
            card: firstReset, rating: .again, now: epoch.addingTimeInterval(3_600)
        )
        expect(noSecondReset.stability > freshCard.stability,
               "hemen ardından gelen ikinci unutma kartı yeniden sıfırlamıyor"
               + String(format: " (%.3f)", noSecondReset.stability))
        expect(noSecondReset.difficulty > freshCard.difficulty,
               "ikinci unutmada zorluk yeniden birikmeye başlıyor"
               + String(format: " (%.1f)", noSecondReset.difficulty))

        // Aralık dolunca sıfırlama yeniden devreye giriyor.
        let secondReset = scheduler.review(
            card: noSecondReset, rating: .again, now: epoch.addingTimeInterval(7_200)
        )
        expect(secondReset.stability == freshCard.stability
               && secondReset.difficulty == freshCard.difficulty,
               "aralık dolunca sıfırlama yeniden devreye giriyor")
        expect(secondReset.lapseCount == atThreshold.lapseCount + 3,
               "üç unutma boyunca sayaç kesintisiz birikti (\(secondReset.lapseCount))")

        // Doğru cevap hiçbir durumda sıfırlamıyor: öğrencinin az önce kazandığı
        // kararlılığı geri almak açık zarar olurdu.
        let leechInWindow = stuckCard(stability: 2.0, lapses: LatvianLessonBuilder.leechLapseThreshold + 2)
        expect(LatvianLeechReset.isDue(
                previous: leechInWindow,
                updated: scheduler.review(card: leechInWindow, rating: .again, now: epoch)),
               "sınanan kart sıfırlama penceresinde")
        let afterCorrect = scheduler.review(card: leechInWindow, rating: .good, now: epoch)
        expect(afterCorrect.stability > leechInWindow.stability,
               "doğru cevap takılan kartı sıfırlamıyor, kararlılığı büyütüyor"
               + String(format: " (%.2f → %.2f)", leechInWindow.stability, afterCorrect.stability))

        // Teşhis cevaptan **önceki** duruma bakıyor: her unutma kararlılığı zaten eşiğin
        // altına çökerttiğinden, sonraki duruma bakmak iyi öğrenilmiş bir kartı da tek
        // hatayla sıfırlardı.
        let strongCard = stuckCard(stability: LatvianLessonBuilder.masteryStabilityDays * 4, lapses: 8)
        expect(!LatvianLessonBuilder.isLeech(card: strongCard), "kalıcılığa ulaşmış kart takılmış değil")
        let strongAfterLapse = scheduler.review(card: strongCard, rating: .again, now: epoch)
        expect(strongAfterLapse.stability > freshCard.stability
               && strongAfterLapse.difficulty > freshCard.difficulty,
               "kalıcılığa ulaşmış kart tek bir hatayla sıfırlanmıyor"
               + String(format: " (S=%.2f D=%.1f)", strongAfterLapse.stability, strongAfterLapse.difficulty))

        // Eşiğin altındaki kart da sıfırlanmıyor: teşhis tek yerde, `isLeech`te.
        let belowThreshold = stuckCard(stability: 2.0, lapses: LatvianLessonBuilder.leechLapseThreshold - 1)
        let belowAfterLapse = scheduler.review(card: belowThreshold, rating: .again, now: epoch)
        expect(belowAfterLapse.stability > freshCard.stability,
               "takılma eşiğinin altındaki kart sıfırlanmıyor"
               + String(format: " (%.2f)", belowAfterLapse.stability))

        // Döngü koruması: sürekli unutulan kart her unutmada değil, unutmaların yarısında
        // sıfırlanıyor ve sayaç kırk unutma boyunca kesintisiz birikiyor.
        var loopCard = stuckCard(stability: 2.0, lapses: LatvianLessonBuilder.leechLapseThreshold)
        var loopResets = 0
        var loopMoment = epoch
        let loopLapses = 40
        for _ in 0..<loopLapses {
            loopMoment = loopMoment.addingTimeInterval(3_600)
            loopCard = scheduler.review(card: loopCard, rating: .again, now: loopMoment)
            if loopCard.stability == freshCard.stability { loopResets += 1 }
        }
        expect(loopCard.lapseCount == atThreshold.lapseCount + loopLapses,
               "kırk unutma boyunca sayaç birikmeye devam ediyor (\(loopCard.lapseCount))")
        expect(loopResets == loopLapses / LatvianLeechReset.lapseSpacing,
               "kırk unutmada \(loopLapses / LatvianLeechReset.lapseSpacing) sıfırlama —"
               + " her unutmada değil (\(loopResets))")

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

        /// Günde bir oturum yapan (ya da `sameSitting` ile hepsini arka arkaya yapan) bir
        /// öğrenciyi benzetir.
        ///
        /// `errorRate` `nil` ise öğrenci kusursuz (`easy`); değilse her soruda o olasılıkla
        /// `again`, kalanında `good` (bkz. `LatvianSimulatedLearner`). Ders tohumu da koşu
        /// tohumundan türetiliyor, böylece bir koşunun tamamı tek bir sayıyla belirleniyor.
        func simulate(
            runSeed: UInt64,
            errorRate: Double?,
            limit: Int,
            sameSitting: Bool = false
        ) -> (unlockedAt: Int?, peak: Double, resets: Int, rescueLessons: Int, productionRescues: Int) {
            var progress = LatvianProgress.new()
            var model = LatvianSimulatedLearner(seed: runSeed, errorRate: errorRate ?? 0)
            var moment = epoch
            var peak = 0.0
            var unlockedAt: Int?
            var resets = 0
            var rescueLessons = 0
            var productionRescues = 0

            for lessonIndex in 1...limit {
                let start = sameSitting
                    ? moment
                    : epoch.addingTimeInterval(Double(lessonIndex - 1) * 86_400)
                let plan = LatvianLessonBuilder.plan(
                    scene: firstScene, pack: realPack, progress: progress, now: start
                )
                let rescues = plan.filter { $0.source == .leech }
                if !rescues.isEmpty { rescueLessons += 1 }
                productionRescues += rescues.filter { $0.modality == .production }.count

                let questions = LatvianLessonBuilder.build(
                    scene: firstScene, pack: realPack, progress: progress,
                    factory: realFactory, availableAudio: realAudio,
                    seed: runSeed &* 1_000 &+ UInt64(lessonIndex), now: start
                )
                for (offset, question) in questions.enumerated() {
                    moment = start.addingTimeInterval(Double(offset + 1) * 20)
                    progress.registerAnswer(
                        wordId: question.targetWordId, modality: question.modality,
                        rating: errorRate == nil ? .easy : model.nextRating(),
                        scheduler: scheduler, now: moment
                    )
                    // Sıfırlamanın imzası. Yer tutucu planlayıcı hiçbir olağan yolda
                    // kararlılığı sıfır bırakmıyor (her dal ya pozitif bir sabitten
                    // başlıyor ya pozitif çarpanla ilerliyor), dolayısıyla tekrar görmüş
                    // bir kartta sıfır kararlılık yalnızca sıfırlamadan gelebilir.
                    let key = memoryKey(question.targetWordId, question.modality)
                    if let card = progress.card(for: key), card.stability == 0, card.reviewCount > 0 {
                        resets += 1
                    }
                }
                peak = max(
                    peak,
                    LatvianLessonBuilder.masteryRatio(scene: firstScene, progress: progress, now: moment)
                )
                if LatvianLessonBuilder.isSceneMastered(scene: firstScene, progress: progress, now: moment) {
                    unlockedAt = lessonIndex
                    break
                }
            }
            return (unlockedAt, peak, resets, rescueLessons, productionRescues)
        }

        print("\n=== Benzetim: gerçekçi öğrenci (dört soruda bir yanlış) ===")

        // Dört soruda birini yanlış yapan, kalanını zorlanmadan ama hızlı olmadan bilen
        // öğrenci. Kusursuz yolun tek veri noktası olmaması için ölçülüyor.
        //
        // **Altı ayrı tohumla koşuluyor ve yayılım da sınanıyor.** Eski hâlinde tek bir
        // konumsal hata deseni vardı (`cevaplanan % 4 == 0`); o desen ders sıralamasına faz
        // kilitli olduğundan tohumlar arası varyans üretmiyordu ve tek bir sayıya bakmak
        // sonucu olduğundan güvenilir gösteriyordu. Artık tek bir tohumda tutan bir sonuç
        // yeterli değil: altısı da geçmeli.
        let mixedSeeds: [UInt64] = [1, 2, 3, 4, 5, 6]
        let mixedLimit = 200
        var mixedRuns: [(seed: UInt64, unlockedAt: Int?, peak: Double, resets: Int)] = []
        var mixedRescueLessons = 0
        var mixedProductionRescues = 0
        for runSeed in mixedSeeds {
            let run = simulate(runSeed: runSeed, errorRate: 0.25, limit: mixedLimit)
            mixedRuns.append((runSeed, run.unlockedAt, run.peak, run.resets))
            mixedRescueLessons += run.rescueLessons
            mixedProductionRescues += run.productionRescues
        }
        let mixedUnlocks = mixedRuns.compactMap(\.unlockedAt).sorted()
        let mixedResets = mixedRuns.map(\.resets).reduce(0, +)
        print("  oturum sayıları (tohum sırasıyla): "
              + mixedRuns.map { $0.unlockedAt.map(String.init) ?? "açılmadı" }.joined(separator: " "))
        if let low = mixedUnlocks.first, let high = mixedUnlocks.last {
            print("  yayılım: \(low)–\(high) oturum (ortanca \(mixedUnlocks[mixedUnlocks.count / 2]))")
        }
        print("  kurtarma: \(mixedRescueLessons) ders, sıfırlama: \(mixedResets) kart")

        expect(mixedUnlocks.count == mixedSeeds.count,
               "gerçekçi öğrenci altı tohumun hepsinde sahneyi tamamlıyor"
               + " (\(mixedUnlocks.count)/\(mixedSeeds.count))")
        expect(mixedUnlocks.allSatisfy { $0 > (unlockedAtLesson ?? 0) },
               "yanlış yapan öğrenci her tohumda kusursuz öğrenciden daha çok ders yapıyor"
               + " (\(mixedUnlocks.first ?? 0) > \(unlockedAtLesson ?? 0))")
        // Üst sınır, kapının asıl arızasına karşı: ölçüldüğünde (yer tutucu planlayıcı,
        // 7 günlük kararlılık eşiği, sıfırlama açık) bu altı tohum 33-52 oturum aralığında
        // geçiyordu. Kapı ya da planlayıcı bozulup öğrenciyi sonsuza dek "biraz daha çalış"
        // durumunda bırakırsa bu satır sessiz kalmasın diye ölçülen en kötü tohumun biraz
        // üstüne tavan konuyor. Alt sınır yok: hızlanmak arıza değil.
        let mixedBudget = 70
        expect((mixedUnlocks.last ?? mixedLimit) <= mixedBudget,
               "gerçekçi öğrenci her tohumda makul sürede geçiyor"
               + " (\(mixedUnlocks.last ?? mixedLimit) ≤ \(mixedBudget) oturum)")
        // Yayılımın kendisi de ölçülüyor: tohumlar arası fark yeniden sıfıra inerse hata
        // modeli sessizce konumsala dönmüş demektir ve yukarıdaki tavan bunu yakalamaz.
        expect(Set(mixedUnlocks).count > 1,
               "tohumlar gerçekten farklı koşular üretiyor"
               + " (\(Set(mixedUnlocks).count) ayrı sonuç)")
        // Kurtarma ve sıfırlama bu izde sessizce kapanırsa yukarıdaki tavan bunu yakalamaz:
        // dört soruda birini yanlış yapan öğrencide takılan kelime **çıkması**, kurtarmanın
        // ve planlayıcı tarafındaki sıfırlamanın **devreye girmesi** gerekiyor. Sayılar
        // ölçülene değil sıfırdan büyüklüğe bağlanıyor.
        expect(mixedRescueLessons > 0,
               "gerçekçi öğrencide kurtarma devreye giriyor (\(mixedRescueLessons) ders)")
        expect(mixedResets > 0,
               "gerçekçi öğrencide takılan kart sıfırlanıyor (\(mixedResets) sıfırlama)")
        expect(mixedProductionRescues == 0,
               "kurtarma hedeflerinin hiçbiri üretim tarafından değil (\(mixedProductionRescues))")

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

        print("\n=== Benzetim: tohum yayılımı (koruma özellikleri) ===")

        // Yukarıdaki üç benzetim tek bir ders tohumuyla koşuyor. Tek tohumda tutan bir
        // sonuç sonuç değildir: aynı özellikler altı ayrı tohumda da tutmalı. Hata modeli
        // artık tohumdan beslendiği için bu koşular gerçekten farklı.
        let spreadSeeds: [UInt64] = [11, 12, 13, 14, 15, 16]

        let perfectRuns = spreadSeeds.map { simulate(runSeed: $0, errorRate: nil, limit: 60) }
        let perfectUnlocks = perfectRuns.compactMap(\.unlockedAt).sorted()
        print("  kusursuz, günde bir oturum: "
              + perfectRuns.map { $0.unlockedAt.map(String.init) ?? "açılmadı" }.joined(separator: " "))
        expect(perfectUnlocks.count == spreadSeeds.count,
               "kusursuz öğrenci altı tohumun hepsinde sahneyi açıyor"
               + " (\(perfectUnlocks.count)/\(spreadSeeds.count))")
        expect((perfectUnlocks.last ?? 0) <= minimumLessons + 4,
               "kusursuz öğrenci her tohumda aritmetik tabana yakın kalıyor"
               + " (\(perfectUnlocks.last ?? 0) ≤ \(minimumLessons + 4) oturum)")
        expect(perfectRuns.allSatisfy { $0.resets == 0 },
               "kusursuz öğrencide hiçbir kart sıfırlanmıyor"
               + " (\(perfectRuns.map(\.resets).reduce(0, +)))")
        expect(perfectRuns.allSatisfy { $0.rescueLessons == 0 },
               "kusursuz öğrencide kurtarma hiç devreye girmiyor")

        // Hep yanlış yapan öğrenci: sıfırlama defalarca devreye giriyor ama sahneyi
        // açmıyor. Sıfırlama "unut ve baştan öğren" demek, "geç" demek değil.
        let wrongRuns = spreadSeeds.map { simulate(runSeed: $0, errorRate: 1, limit: 40) }
        print(String(format: "  hep yanlış: en yüksek kapsama %.2f, sıfırlama %d",
                     wrongRuns.map(\.peak).max() ?? 0,
                     wrongRuns.map(\.resets).reduce(0, +)))
        expect(wrongRuns.allSatisfy { $0.unlockedAt == nil },
               "hep yanlış yapan öğrenci hiçbir tohumda sahneyi açamıyor")
        expect(wrongRuns.allSatisfy { $0.peak == 0 },
               "hep yanlış yapan öğrencide hakimiyet oranı her tohumda sıfır")
        expect(wrongRuns.contains { $0.resets > 0 },
               "hep yanlış yapan öğrencide sıfırlama devreye giriyor"
               + " (\(wrongRuns.map(\.resets).reduce(0, +)))")

        // Tek oturumda 20 kusursuz ders: gün geçmediği için kapı kapalı kalmalı.
        let sittingRuns = spreadSeeds.map {
            simulate(runSeed: $0, errorRate: nil, limit: 20, sameSitting: true)
        }
        print(String(format: "  tek oturumda 20 ders: en yüksek kapsama %.2f",
                     sittingRuns.map(\.peak).max() ?? 0))
        expect(sittingRuns.allSatisfy { $0.unlockedAt == nil },
               "tek oturumda 20 ders yapan kusursuz öğrenci hiçbir tohumda sahneyi açamıyor")
        expect(sittingRuns.allSatisfy { $0.peak < LatvianLessonBuilder.masteryCoverage },
               String(format: "tek oturumda hakimiyet oranı her tohumda eşiğin altında (%.2f)",
                      sittingRuns.map(\.peak).max() ?? 0))

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

        print("\n=== Ders oturumu: akış ===")

        func choice(_ id: String, correct: Int = 0) -> LatvianExercise {
            LatvianExercise(
                id: id, kind: .listenChoose, targetWordId: "w-\(id)", prompt: "p",
                content: .choice(options: ["a", "b"], correctIndex: correct)
            )
        }

        let session = LatvianLessonSession(exercises: [choice("q1"), choice("q2"), choice("q3")])

        expect(session.current?.id == "q1", "ilk soru sırada")
        expect(session.progress == 0, "başlangıçta ilerleme sıfır")
        expect(session.heartsLeft == LatvianLessonSession.maxHearts, "beş canla başlıyor")
        expect(!session.isAwaitingAdvance, "başlangıçta bekleyen cevap yok")

        let correctResult = session.submit(.choice(index: 0), elapsed: 2, usedHint: false)
        expect(correctResult.grade.isCorrect, "doğru cevap doğru notlanıyor")
        expect(correctResult.rating == .easy, "hızlı doğru easy veriyor")
        expect(correctResult.comboCount == 1, "kombo başlıyor")
        expect(correctResult.xpGained == LatvianLessonSession.baseXP, "doğru cevap 10 XP veriyor")
        expect(correctResult.heartsLeft == LatvianLessonSession.maxHearts, "doğru cevapta can gitmiyor")
        expect(session.isAwaitingAdvance, "cevap sonrası ilerleme bekleniyor")
        expect(session.current?.id == "q1", "submit sırayı ilerletmiyor, soru ekranda kalıyor")
        expect(session.progress == 0, "submit ilerlemeyi tek başına artırmıyor")

        session.advance()
        expect(session.current?.id == "q2", "sonraki soruya geçiliyor")
        expect(!session.isAwaitingAdvance, "ilerledikten sonra bekleyen cevap yok")
        expect(abs(session.progress - 1.0 / 3.0) < 1e-9, "doğru cevap ilerlemeyi artırıyor")

        let wrongResult = session.submit(.choice(index: 1), elapsed: 3, usedHint: false)
        expect(!wrongResult.grade.isCorrect, "yanlış cevap yanlış notlanıyor")
        expect(wrongResult.rating == .again, "yanlış cevap again veriyor")
        expect(wrongResult.heartsLeft == LatvianLessonSession.maxHearts - 1, "yanlış cevapta bir can gidiyor")
        expect(wrongResult.comboCount == 0, "yanlış cevap komboyu sıfırlıyor")
        expect(wrongResult.xpGained == 0, "yanlış cevap XP vermiyor")

        session.advance()
        expect(session.current?.id == "q3", "yanlış sorudan sonra sıradaki soruya geçiliyor")
        expect(session.remainingCount == 2, "yanlış soru sona geri eklendi")
        expect(abs(session.progress - 1.0 / 3.0) < 1e-9, "yanlış cevap ilerlemeyi artırmıyor")

        _ = session.submit(.choice(index: 0), elapsed: 2, usedHint: false)
        session.advance()
        expect(session.current?.id == "q2", "yanlış yapılan soru tekrar soruluyor")
        expect(!session.isFinished, "yanlış soru doğrulanmadan ders bitmiyor")

        let retryResult = session.submit(.choice(index: 0), elapsed: 2, usedHint: false)
        expect(retryResult.rating == .hard,
               "ikinci denemede doğru bulunan soru hızlı cevaplansa bile hard veriyor")
        session.advance()
        expect(session.isFinished, "tüm sorular doğrulanınca ders bitiyor")
        expect(session.current == nil, "ders bitince sıra boş")
        expect(session.progress == 1, "biten derste ilerleme tam")
        expect(!session.isFailed, "canı olan biten ders başarısız değil")
        expect(session.answerCount == 4 && session.correctCount == 3,
               "dört cevap gönderildi, üçü doğru")
        expect(abs(session.accuracy - 0.75) < 1e-9, "doğruluk gönderilen cevap başına ölçülüyor")

        // Derece üretimine giden üç girdi — `elapsed`, `usedHint` ve soru tipinin hız
        // eşiği — gerçekten bağlanmış mı. Eşiğin tipten geldiğini göstermek için aynı
        // süre iki farklı tipe veriliyor: 12 saniye `listenChoose`'da (eşik 5) yavaş,
        // `match`te (eşik 15) hâlâ hızlı.
        let matchPairs = [
            LatvianMatchPair(lv: "labdien", tr: "iyi günler"),
            LatvianMatchPair(lv: "paldies", tr: "teşekkürler"),
            LatvianMatchPair(lv: "lūdzu", tr: "lütfen"),
            LatvianMatchPair(lv: "kafija", tr: "kahve"),
        ]
        let matching = LatvianExercise(
            id: "t3", kind: .match, targetWordId: "w-t3", prompt: "p",
            content: .matching(pairs: matchPairs)
        )
        let timing = LatvianLessonSession(exercises: [choice("t1"), choice("t2"), matching])
        expect(timing.submit(.choice(index: 0), elapsed: 12, usedHint: false).rating == .good,
               "eşiği aşan doğru cevap good veriyor")
        timing.advance()
        expect(timing.submit(.choice(index: 0), elapsed: 1, usedHint: true).rating == .hard,
               "ipucu alan doğru cevap hard veriyor")
        timing.advance()
        expect(timing.submit(.pairs(matchPairs), elapsed: 12, usedHint: false).rating == .easy,
               "hız eşiği soru tipinden geliyor: eşleştirmede 12 saniye hâlâ hızlı")
        timing.advance()
        expect(timing.isFinished, "üç soruluk karışık ders bitiyor")

        print("\n=== Ders oturumu: sıra dışı çağrılar ===")

        // `submit` ve `advance` ayrı olduğu için arayüz ikisini yanlış sırada ya da iki kez
        // çağırabilir (çift dokunuş, geri gelen ekran). Hiçbiri sayaçları bozmamalı.
        let guarded = LatvianLessonSession(exercises: [choice("g1"), choice("g2")])

        guarded.advance()
        expect(guarded.current?.id == "g1", "cevap gönderilmeden advance sırayı ilerletmiyor")
        expect(guarded.remainingCount == 2, "cevapsız advance kuyruğu değiştirmiyor")
        expect(guarded.answerCount == 0, "cevapsız advance cevap saymıyor")

        let firstSubmit = guarded.submit(.choice(index: 0), elapsed: 2, usedHint: false)
        let repeatSubmit = guarded.submit(.choice(index: 1), elapsed: 90, usedHint: true)
        expect(repeatSubmit == firstSubmit, "ilerlemeden ikinci submit kayıtlı sonucu aynen dönüyor")
        expect(guarded.xpEarned == LatvianLessonSession.baseXP, "çift submit XP'yi iki kez saymıyor")
        expect(guarded.answerCount == 1, "çift submit doğruluk paydasını şişirmiyor")
        expect(guarded.heartsLeft == LatvianLessonSession.maxHearts, "çift submit can eksiltmiyor")
        expect(guarded.comboCount == 1, "çift submit komboyu iki kez artırmıyor")

        guarded.advance()
        guarded.advance()
        expect(guarded.current?.id == "g2", "çift advance bir soru atlamıyor")
        expect(guarded.remainingCount == 1, "çift advance kuyruktan iki soru düşürmüyor")
        expect(abs(guarded.progress - 0.5) < 1e-9, "çift advance ilerlemeyi iki kez artırmıyor")

        _ = guarded.submit(.choice(index: 0), elapsed: 2, usedHint: false)
        guarded.advance()
        expect(guarded.isFinished, "iki soruluk ders bitiyor")
        let afterFinish = guarded.submit(.choice(index: 0), elapsed: 2, usedHint: false)
        expect(afterFinish.xpGained == 0, "biten derse gönderilen cevap XP vermiyor")
        expect(guarded.xpEarned == 2 * LatvianLessonSession.baseXP, "biten dersin XP'si sabit kalıyor")
        expect(guarded.answerCount == 2, "biten derse gönderilen cevap sayılmıyor")
        expect(guarded.isFinished && guarded.progress == 1, "biten ders bitmiş kalıyor")

        // İkinci denemede doğru bulunan soru `attempts == 2` ile derecelendiriliyor; bunun
        // tek yolu denemelerin soru **konumuna** göre sayılması. Kimliğe göre sayılsaydı
        // aynı kimliği taşıyan iki soru tek soru sanılırdı.
        let twins = LatvianLessonSession(exercises: [choice("same"), choice("same")])
        _ = twins.submit(.choice(index: 0), elapsed: 2, usedHint: false)
        twins.advance()
        let twinResult = twins.submit(.choice(index: 0), elapsed: 2, usedHint: false)
        expect(twinResult.rating == .easy, "aynı kimlikli ikinci soru ilk deneme sayılıyor")
        twins.advance()
        expect(twins.isFinished && twins.progress == 1,
               "aynı kimlikli iki soru ayrı ayrı tamamlanıyor")

        let empty = LatvianLessonSession(exercises: [])
        expect(empty.isFinished, "boş ders bitmiş sayılıyor")
        expect(empty.progress == 1, "boş derste ilerleme tam")
        expect(empty.accuracy == 0, "cevapsız derste doğruluk sıfır")
        expect(empty.current == nil, "boş derste sıra boş")

        print("\n=== Ders oturumu: kombo kilometre taşları ===")

        let comboSession = LatvianLessonSession(exercises: (1...12).map { choice("c\($0)") })
        var milestones: [Int] = []
        for _ in 1...12 {
            let outcome = comboSession.submit(.choice(index: 0), elapsed: 2, usedHint: false)
            if outcome.isComboMilestone { milestones.append(outcome.comboCount) }
            comboSession.advance()
        }
        expect(milestones == [3, 5, 10], "kombo 3, 5 ve 10'da kilometre taşı veriyor")
        expect(comboSession.comboCount == 12, "kombo on ikiye kadar büyüyor")
        expect(comboSession.xpEarned
               == 12 * LatvianLessonSession.baseXP + 3 * LatvianLessonSession.comboBonusXP,
               "kombo bonusu XP'ye ekleniyor (\(comboSession.xpEarned))")
        expect(comboSession.accuracy == 1, "hatasız derste doğruluk yüzde yüz")
        expect(comboSession.isFinished && !comboSession.isFailed, "hatasız ders başarıyla bitiyor")

        // Karar: kilometre taşı ders başına **bir kez** veriliyor. Aksi halde kombo
        // kırıp yeniden kurmak XP kazandırırdı: 3'lük eşiği dört kez toplamak hatasız
        // koşudan fazla bonus verir ve XP performansın azalan fonksiyonu olurdu.
        let rebuild = LatvianLessonSession(exercises: (1...9).map { choice("r\($0)") })
        var rebuildMilestones: [Int] = []
        for step in 1...9 {
            // 4. soru bilerek yanlış: kombo sıfırlanıp yeniden 3'e tırmanıyor.
            let answer: LatvianAnswer = step == 4 ? .choice(index: 1) : .choice(index: 0)
            let outcome = rebuild.submit(answer, elapsed: 2, usedHint: false)
            if outcome.isComboMilestone { rebuildMilestones.append(outcome.comboCount) }
            rebuild.advance()
        }
        // Kombo 3'e iki kez çıkıyor (1-2-3, sonra kırılıp 1-2-3-4-5) ama 3'lük eşik yalnız
        // bir kez ödüllendiriliyor; 5'lik eşik ilk kez görüldüğü için veriliyor.
        expect(rebuildMilestones == [3, 5],
               "kombo üçe iki kez çıksa da 3'lük kilometre taşı bir kez veriliyor (\(rebuildMilestones))")
        expect(rebuildMilestones.filter { $0 == 3 }.count == 1,
               "aynı kilometre taşı ders içinde tekrarlanmıyor")
        expect(rebuild.heartsLeft == LatvianLessonSession.maxHearts - 1, "tek yanlış tek can götürüyor")

        print("\n=== Ders oturumu: can bitişi ===")

        let failing = LatvianLessonSession(exercises: (1...8).map { choice("f\($0)") })
        for _ in 1...5 {
            _ = failing.submit(.choice(index: 1), elapsed: 2, usedHint: false)
            failing.advance()
        }
        expect(failing.isFailed, "beş yanlıştan sonra ders başarısız")
        expect(failing.heartsLeft == 0, "canlar tükendi")
        expect(!failing.isFinished, "başarısız ders tamamlanmış sayılmıyor")
        expect(failing.progress == 0, "hiç doğru yapılmayan derste ilerleme sıfır")

        // Başarısız ders dönmüyor: kuyruk donuyor, sayaçlar sabit kalıyor.
        let frozenRemaining = failing.remainingCount
        let frozenCurrentId = failing.current?.id
        for _ in 1...20 {
            _ = failing.submit(.choice(index: 0), elapsed: 2, usedHint: false)
            failing.advance()
        }
        expect(failing.answerCount == 5, "başarısız derse gönderilen cevaplar sayılmıyor (\(failing.answerCount))")
        expect(failing.xpEarned == 0, "başarısız derste XP birikmiyor")
        expect(failing.remainingCount == frozenRemaining, "başarısız derste kuyruk dönmüyor")
        expect(failing.current?.id == frozenCurrentId, "başarısız derste sıra ilerlemiyor")
        expect(failing.isFailed && !failing.isFinished, "başarısız ders başarısız kalıyor")

        // Tek soruluk ders beş kez yanlış cevaplanınca kuyruk boşalmıyor: aksi halde
        // `queue.isEmpty` doğru olur ve bitmiş ders sanılırdı.
        let single = LatvianLessonSession(exercises: [choice("only")])
        for _ in 1...5 {
            _ = single.submit(.choice(index: 1), elapsed: 2, usedHint: false)
            single.advance()
        }
        expect(single.isFailed && !single.isFinished, "tek soruluk ders can bitince başarısız")
        expect(single.remainingCount == 1, "başarısız tek soruluk derste soru kuyrukta kalıyor")

        print("\n=== Ders oturumu: gerçek ders üzerinde üç koşu ===")

        let freshProgress = LatvianProgress.new()
        let realLesson = LatvianLessonBuilder.build(
            scene: firstScene, pack: realPack, progress: freshProgress,
            factory: realFactory, availableAudio: realAudio, seed: 4242, now: epoch
        )
        expect(realLesson.count == LatvianLessonBuilder.lessonLength,
               "gerçek paketten 16 soruluk ders kuruldu (\(realLesson.count))")
        expect(Set(realLesson.map(\.id)).count == realLesson.count, "gerçek derste soru kimlikleri benzersiz")

        // Cevap üreticileri kendi başlarına doğrulanıyor: koşuların can ve XP sayıları
        // ancak "doğru" gerçekten doğru, "yanlış" gerçekten yanlışsa anlamlı.
        let generatorsSound = realLesson.allSatisfy { exercise in
            LatvianGrader.grade(exercise: exercise, answer: correctAnswer(for: exercise)).isCorrect
                && !LatvianGrader.grade(exercise: exercise, answer: wrongAnswer(for: exercise)).isCorrect
        }
        expect(generatorsSound, "üreticiler gerçek ders üzerinde doğrulanıyor")

        /// Bir koşuyu oynatır. `missIds` içindeki sorular **ilk** karşılaşmada yanlış
        /// cevaplanır. Dönen sayı, oturumun kabul ettiği cevap sayısı.
        func play(
            _ lesson: [LatvianExercise], missIds: Set<String>, maxSubmissions: Int = 200
        ) -> (session: LatvianLessonSession, milestones: [Int], retryRatings: [LatvianRating]) {
            let session = LatvianLessonSession(exercises: lesson)
            var missed: Set<String> = []
            var milestones: [Int] = []
            var retryRatings: [LatvianRating] = []
            var seen: Set<String> = []
            for _ in 0..<maxSubmissions {
                guard let exercise = session.current, !session.isFailed else { break }
                let shouldMiss = missIds.contains(exercise.id) && !missed.contains(exercise.id)
                let isRetry = seen.contains(exercise.id)
                seen.insert(exercise.id)
                let answer = shouldMiss ? wrongAnswer(for: exercise) : correctAnswer(for: exercise)
                if shouldMiss { missed.insert(exercise.id) }
                let outcome = session.submit(answer, elapsed: 2, usedHint: false)
                if outcome.isComboMilestone { milestones.append(outcome.comboCount) }
                if isRetry { retryRatings.append(outcome.rating) }
                session.advance()
            }
            return (session, milestones, retryRatings)
        }

        // 1) Kusursuz koşu.
        let perfect = play(realLesson, missIds: [])
        print("  kusursuz: \(perfect.session.answerCount) cevap,"
              + " \(perfect.session.xpEarned) XP, \(perfect.session.heartsLeft) can,"
              + String(format: " doğruluk %.2f", perfect.session.accuracy))
        expect(perfect.session.answerCount == 16, "kusursuz koşu 16 cevapta bitiyor (\(perfect.session.answerCount))")
        expect(perfect.session.xpEarned == 175, "kusursuz koşu 175 XP veriyor (\(perfect.session.xpEarned))")
        expect(perfect.session.accuracy == 1, "kusursuz koşuda doğruluk 1")
        expect(perfect.session.heartsLeft == 5, "kusursuz koşuda beş can duruyor")
        expect(perfect.session.isFinished && !perfect.session.isFailed, "kusursuz koşu başarıyla bitiyor")
        expect(perfect.session.progress == 1, "kusursuz koşuda ilerleme tam")
        expect(perfect.milestones == [3, 5, 10], "kusursuz koşuda üç kilometre taşı")
        expect(perfect.session.comboCount == 16, "kusursuz koşuda kombo on altıya çıkıyor")

        // 2) Birkaç yanlışlı koşu: 3., 8. ve 12. soru ilk karşılaşmada kaçırılıyor.
        let missIds = Set([2, 7, 11].map { realLesson[$0].id })
        let mistakes = play(realLesson, missIds: missIds)
        print("  üç yanlış: \(mistakes.session.answerCount) cevap,"
              + " \(mistakes.session.xpEarned) XP, \(mistakes.session.heartsLeft) can,"
              + String(format: " doğruluk %.2f", mistakes.session.accuracy))
        expect(mistakes.session.answerCount == 19, "üç yanlışlı koşu 19 cevapta bitiyor (\(mistakes.session.answerCount))")
        expect(mistakes.session.correctCount == 16, "üç yanlışlı koşuda 16 doğru cevap")
        expect(mistakes.session.heartsLeft == 2, "üç yanlış üç can götürüyor (\(mistakes.session.heartsLeft))")
        expect(abs(mistakes.session.accuracy - 16.0 / 19.0) < 1e-9, "üç yanlışlı koşuda doğruluk 16/19")
        expect(mistakes.session.isFinished && !mistakes.session.isFailed, "üç yanlışlı koşu yine de bitiyor")
        expect(mistakes.session.progress == 1, "üç yanlışlı koşuda her soru tamamlanıyor")
        expect(mistakes.milestones == [3, 5], "üç yanlışlı koşuda iki kilometre taşı")
        expect(mistakes.session.xpEarned == 170, "üç yanlışlı koşu 170 XP veriyor (\(mistakes.session.xpEarned))")
        expect(mistakes.retryRatings == [.hard, .hard, .hard],
               "tekrar sorulan sorular attempts=2 ile hard alıyor")
        expect(mistakes.session.xpEarned < perfect.session.xpEarned,
               "yanlış yapmak XP'yi hiçbir zaman artırmıyor")

        // 3) Beş canın da gittiği koşu: her soru yanlış.
        let doomed = LatvianLessonSession(exercises: realLesson)
        for _ in 0..<50 {
            guard let exercise = doomed.current else { break }
            _ = doomed.submit(wrongAnswer(for: exercise), elapsed: 2, usedHint: false)
            doomed.advance()
        }
        print("  can biten: \(doomed.answerCount) cevap, \(doomed.xpEarned) XP,"
              + " \(doomed.heartsLeft) can,"
              + String(format: " doğruluk %.2f", doomed.accuracy))
        expect(doomed.answerCount == 5, "can biten koşu beş cevapta duruyor (\(doomed.answerCount))")
        expect(doomed.xpEarned == 0, "can biten koşuda XP yok")
        expect(doomed.accuracy == 0, "can biten koşuda doğruluk sıfır")
        expect(doomed.heartsLeft == 0, "can biten koşuda can kalmıyor")
        expect(doomed.isFailed && !doomed.isFinished, "can biten koşu başarısız, bitmiş değil")
        expect(doomed.progress == 0, "can biten koşuda hiç soru tamamlanmıyor")
        expect(doomed.remainingCount == LatvianLessonBuilder.lessonLength,
               "can biten koşuda 16 soru kuyrukta kalıyor (\(doomed.remainingCount))")

        // Oturum gerçekten saatsiz: aynı ders iki kez oynanınca sonuç birebir aynı.
        let replay = play(realLesson, missIds: missIds)
        expect(replay.session.xpEarned == mistakes.session.xpEarned
               && replay.session.answerCount == mistakes.session.answerCount
               && replay.milestones == mistakes.milestones,
               "aynı koşu iki kez oynandığında aynı sonucu veriyor")

        // MARK: - Bildirim kuralları

        print("\n=== Bildirim kuralları: sessiz saatler ===")

        var notifIstanbul = Calendar(identifier: .gregorian)
        notifIstanbul.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        var notifWarsaw = Calendar(identifier: .gregorian)
        notifWarsaw.timeZone = TimeZone(identifier: "Europe/Warsaw")!

        /// İstanbul yerel saatiyle bir an. Testlerin tamamı bu takvimle kuruluyor.
        func notifMoment(_ hour: Int, _ minute: Int = 0, day: Int = 15) -> Date {
            notifIstanbul.date(
                from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute)
            )!
        }

        expect(LatvianNotificationRules.isQuietHour(notifMoment(2), calendar: notifIstanbul),
               "gece 02:00 sessiz saatte")
        expect(LatvianNotificationRules.isQuietHour(notifMoment(23), calendar: notifIstanbul),
               "23:00 sessiz saatte")
        expect(!LatvianNotificationRules.isQuietHour(notifMoment(8), calendar: notifIstanbul),
               "08:00 sessizliğin dışında (pencere kapanışı hariç)")
        expect(!LatvianNotificationRules.isQuietHour(notifMoment(22, 59), calendar: notifIstanbul),
               "22:59 sessiz saatte değil")

        // AYNI AN, iki dilim: sessizlik mutlak zamana değil YEREL saate bağlı.
        // 23:30 İstanbul (UTC+3) = 22:30 Varşova (UTC+2).
        let notifCrossing = notifMoment(23, 30)
        expect(LatvianNotificationRules.isQuietHour(notifCrossing, calendar: notifIstanbul),
               "aynı an İstanbul'da (23:30) sessiz saatte")
        expect(!LatvianNotificationRules.isQuietHour(notifCrossing, calendar: notifWarsaw),
               "aynı an Varşova'da (22:30) sessiz saatte DEĞİL")
        let notifDawn = notifMoment(8, 30)
        expect(!LatvianNotificationRules.isQuietHour(notifDawn, calendar: notifIstanbul),
               "aynı an İstanbul'da (08:30) sessizliğin dışında")
        expect(LatvianNotificationRules.isQuietHour(notifDawn, calendar: notifWarsaw),
               "aynı an Varşova'da (07:30) hâlâ sessiz saatte")

        print("\n=== Bildirim kuralları: alışkanlık saati ===")

        expect(LatvianNotificationRules.preferredHour(recentLessonHours: [], current: nil) == 20,
               "geçmiş yoksa varsayılan saat 20:00")
        expect(LatvianNotificationRules.preferredHour(recentLessonHours: [9, 9], current: nil) == 20,
               "iki veri noktası alışkanlık sayılmıyor, varsayılanda kalınıyor")
        expect(LatvianNotificationRules.preferredHour(recentLessonHours: [9, 9, 9], current: nil) == 20,
               "üç veri noktası da eşiğin altında")
        expect(LatvianNotificationRules.preferredHour(recentLessonHours: [9, 9], current: 18) == 18,
               "geçmiş yetersizken KURULU saat korunuyor, varsayılana geri dönülmüyor")
        expect(LatvianNotificationRules.preferredHour(recentLessonHours: [9, 9, 9, 9], current: nil) == 9,
               "dört ders aynı saatteyse alışkanlık öğreniliyor")
        expect(LatvianNotificationRules.preferredHour(recentLessonHours: [19, 20, 20, 21], current: nil) == 20,
               "komşu saatler tek tepe sayılıyor (19-20-21 kümesi 20'de topluyor)")
        expect(LatvianNotificationRules.preferredHour(recentLessonHours: [2, 2, 2, 2, 2], current: nil) == 20,
               "sessiz saate düşen alışkanlık varsayılana çekiliyor")
        expect(LatvianNotificationRules.preferredHour(recentLessonHours: [99, 99, 99, 99], current: nil) == 20,
               "geçersiz saatler eleniyor, geriye alışkanlık kalmıyor")
        expect(LatvianNotificationRules.preferredHour(recentLessonHours: [8, 12, 16, 20], current: nil) == 20,
               "dağınık geçmişte hiçbir küme eşiği geçmiyor, varsayılanda kalınıyor")

        // Histerezis: kayan pencerenin saati her ders sonunda oynatmasını engelliyor.
        expect(LatvianNotificationRules.preferredHour(recentLessonHours: [20, 20, 19, 9], current: 20) == 20,
               "zayıf bir aday kurulu saati deviremiyor (histerezis)")
        expect(LatvianNotificationRules.preferredHour(recentLessonHours: [9, 9, 9, 10], current: 20) == 9,
               "belirgin bir aday kurulu saatin yerine geçiyor")
        expect(LatvianNotificationRules.preferredHour(recentLessonHours: [9, 9, 9, 10], current: 2) == 9,
               "kurulu saat sessiz saate düşmüşse aday koşulsuz kazanıyor")

        // Pencere: yalnızca son `historyWindow` ders sayılıyor.
        let notifOldHabit = [21, 21, 21, 21, 9, 9, 9, 9, 9]
        expect(LatvianNotificationRules.preferredHour(recentLessonHours: notifOldHabit, current: nil) == 9,
               "eski alışkanlık pencereden düşüyor, yenisi geçerli")
        expect(LatvianNotificationRules.appendLessonHour(11, to: [1, 2, 3, 4, 5, 6, 7]) == [2, 3, 4, 5, 6, 7, 11],
               "geçmiş yedi kayıtla sınırlı, en eskisi düşüyor")
        expect(LatvianNotificationRules.appendLessonHour(99, to: [9, 9]) == [9, 9],
               "geçersiz saat geçmişe yazılmıyor")

        print("\n=== Bildirim kuralları: seri kurtarma ===")

        /// 10-14 Ağustos arası her gün ders yapmış öğrenci: seri 5, son ders 14 Ağustos.
        /// `streakDays`/`lastLessonDay` `private(set)` olduğu için durum ancak gerçek
        /// motor çağrılarıyla kuruluyor.
        var notifStreaking = LatvianProgress.new()
        for day in 10...14 {
            notifStreaking.registerLessonCompleted(now: notifMoment(20, day: day), calendar: notifIstanbul)
        }
        expect(notifStreaking.streakDays == 5, "beş günlük seri kuruldu (\(notifStreaking.streakDays))")
        expect(notifStreaking.lastLessonDay == "2026-08-14", "son ders 14 Ağustos")

        expect(LatvianNotificationRules.needsStreakRescue(
                progress: notifStreaking, now: notifMoment(21), calendar: notifIstanbul),
               "aktif seride, gün bitmeden ders yoksa kurtarma gerekiyor")
        expect(!LatvianNotificationRules.needsStreakRescue(
                progress: notifStreaking, now: notifMoment(14), calendar: notifIstanbul),
               "günün erken saatinde kurtarma bildirimi yok")
        expect(!LatvianNotificationRules.needsStreakRescue(
                progress: notifStreaking, now: notifMoment(23, 10), calendar: notifIstanbul),
               "sessiz saate girildiyse kurtarma bildirimi yok")

        var notifDoneToday = notifStreaking
        notifDoneToday.registerLessonCompleted(now: notifMoment(10), calendar: notifIstanbul)
        expect(notifDoneToday.streakDays == 6, "bugün de ders yapılınca seri altıya çıkıyor")
        expect(!LatvianNotificationRules.needsStreakRescue(
                progress: notifDoneToday, now: notifMoment(21), calendar: notifIstanbul),
               "bugün ders yapıldıysa kurtarma bildirimi yok")

        expect(!LatvianNotificationRules.needsStreakRescue(
                progress: LatvianProgress.new(), now: notifMoment(21), calendar: notifIstanbul),
               "seri yoksa kurtarma bildirimi yok")

        // Kopmuş seri: `streakDays` bir sonraki derse kadar sıfırlanmadığından hâlâ
        // 3 görünüyor, ama son ders 12 Ağustos — kurtarılacak bir şey kalmamış.
        var notifStale = LatvianProgress.new()
        for day in 10...12 {
            notifStale.registerLessonCompleted(now: notifMoment(20, day: day), calendar: notifIstanbul)
        }
        expect(notifStale.streakDays == 3, "kopmuş serinin sayacı hâlâ üç")
        expect(!LatvianNotificationRules.needsStreakRescue(
                progress: notifStale, now: notifMoment(21), calendar: notifIstanbul),
               "üç gün önce kopmuş seri için kurtarma bildirimi YOK")
        expect(!LatvianNotificationRules.isStreakAtRisk(
                progress: notifStale, now: notifMoment(21), calendar: notifIstanbul),
               "kopmuş seri 'tehlikede' sayılmıyor")

        expect(LatvianNotificationRules.nextStreakRescueMoment(
                progress: notifStreaking, now: notifMoment(10), calendar: notifIstanbul)
               == notifMoment(21, 30),
               "seri bugün tehlikedeyse kurtarma bugün 21:30'a kuruluyor")
        expect(LatvianNotificationRules.nextStreakRescueMoment(
                progress: notifDoneToday, now: notifMoment(10), calendar: notifIstanbul)
               == notifMoment(21, 30, day: 16),
               "bugün ders yapıldıysa kurtarma YARIN 21:30'a kuruluyor")
        expect(LatvianNotificationRules.nextStreakRescueMoment(
                progress: notifStreaking, now: notifMoment(22), calendar: notifIstanbul) == nil,
               "kurtarma anı geçtiyse geçmişe bildirim kurulmuyor")
        expect(LatvianNotificationRules.nextStreakRescueMoment(
                progress: notifStale, now: notifMoment(10), calendar: notifIstanbul) == nil,
               "kopmuş seri için kurtarma anı yok")
        expect(LatvianNotificationRules.nextStreakRescueMoment(
                progress: LatvianProgress.new(), now: notifMoment(10), calendar: notifIstanbul) == nil,
               "hiç seri yokken kurtarma anı yok")

        print("\n=== Bildirim kuralları: dönüm noktaları ===")

        expect(LatvianNotificationRules.isMilestone(7), "7 gün dönüm noktası")
        expect(LatvianNotificationRules.isMilestone(30), "30 gün dönüm noktası")
        expect(LatvianNotificationRules.isMilestone(100), "100 gün dönüm noktası")
        expect(!LatvianNotificationRules.isMilestone(8), "8 gün dönüm noktası değil")
        expect(!LatvianNotificationRules.isMilestone(0), "0 gün dönüm noktası değil")
        expect(!LatvianNotificationRules.isMilestone(1), "1 gün dönüm noktası değil")

        expect(LatvianNotificationRules.milestoneMoment(
                streakDays: 7, now: notifMoment(20), calendar: notifIstanbul)
               == notifMoment(20, 30),
               "dönüm noktası ders bittikten yarım saat sonra çalıyor")
        expect(LatvianNotificationRules.milestoneMoment(
                streakDays: 8, now: notifMoment(20), calendar: notifIstanbul) == nil,
               "dönüm noktası olmayan seride bildirim yok")
        expect(LatvianNotificationRules.milestoneMoment(
                streakDays: 7, now: notifMoment(22, 50), calendar: notifIstanbul)
               == notifMoment(22, 59),
               "gecikme sessiz saate taşarsa an sessizliğin hemen öncesine çekiliyor")
        expect(LatvianNotificationRules.milestoneMoment(
                streakDays: 7, now: notifMoment(23, 30), calendar: notifIstanbul) == nil,
               "sessiz saatte biten derste dönüm noktası bildirimi kurulmuyor")

        print("\n=== Bildirim kuralları: unutma uyarısı ===")

        expect(LatvianNotificationRules.decayingScene(
                pack: pack, progress: LatvianProgress.new(), now: epoch) == nil,
               "hiç öğrenilmemiş sahne için unutma uyarısı yok")

        // Sahne bir kez geçilmiş ama hafızada tek kart yok: hakimiyet oranı sıfır.
        var notifDecayed = LatvianProgress.new()
        notifDecayed.registerSceneCompletion(sceneId: "lv-s01", now: notifMoment(20, day: 1))
        expect(LatvianNotificationRules.decayingScene(
                pack: pack, progress: notifDecayed, now: notifMoment(10))?.id == "lv-s01",
               "geçilmiş ama hakimiyeti düşen sahne unutma uyarısına giriyor")

        expect(LatvianNotificationRules.canSendDecayNotice(lastDecayNotice: nil, now: epoch),
               "hiç uyarı gönderilmemişse gönderilebiliyor")
        expect(!LatvianNotificationRules.canSendDecayNotice(
                lastDecayNotice: epoch, now: epoch.addingTimeInterval(86_400 * 3)),
               "unutma uyarısı üç günde bir gönderilmiyor")
        expect(!LatvianNotificationRules.canSendDecayNotice(
                lastDecayNotice: epoch, now: epoch.addingTimeInterval(86_400 * 7 - 1)),
               "soğuma bir saniye eksikken hâlâ kapalı")
        expect(LatvianNotificationRules.canSendDecayNotice(
                lastDecayNotice: epoch, now: epoch.addingTimeInterval(86_400 * 7)),
               "soğuma tam yedi günde açılıyor")
        expect(LatvianNotificationRules.canSendDecayNotice(
                lastDecayNotice: epoch, now: epoch.addingTimeInterval(86_400 * 8)),
               "unutma uyarısı sekiz gün sonra gönderilebiliyor")

        expect(LatvianNotificationRules.decayHour(reminderHour: 20) == 12,
               "akşam hatırlatmasında unutma uyarısı öğlene kuruluyor")
        expect(LatvianNotificationRules.decayHour(reminderHour: 9) == 17,
               "sabah hatırlatmasında unutma uyarısı akşam üstüne kuruluyor")
        expect(!LatvianNotificationRules.isQuietHour(LatvianNotificationRules.decayHour(reminderHour: 8)),
               "unutma uyarısının saati hiçbir durumda sessiz saatte değil")

        expect(LatvianNotificationRules.decayMoment(
                scheduledAt: nil, rescueAt: nil, reminderHour: 20,
                now: notifMoment(10), calendar: notifIstanbul)
               == notifMoment(12, day: 17),
               "taze uyarı iki gün sonrasına kuruluyor")
        expect(LatvianNotificationRules.decayMoment(
                scheduledAt: notifMoment(12, day: 17), rescueAt: nil, reminderHour: 20,
                now: notifMoment(10, day: 16), calendar: notifIstanbul)
               == notifMoment(12, day: 17),
               "kurulu uyarı her ders sonunda ötelenmiyor, aynı anda kalıyor")
        expect(LatvianNotificationRules.decayMoment(
                scheduledAt: notifMoment(12, day: 17), rescueAt: notifMoment(21, 30, day: 17),
                reminderHour: 20, now: notifMoment(10, day: 16), calendar: notifIstanbul)
               == notifMoment(12, day: 18),
               "kurulu uyarı seri kurtarmayla aynı güne düşerse bir gün öteleniyor")
        expect(LatvianNotificationRules.decayMoment(
                scheduledAt: notifMoment(12, day: 10), rescueAt: nil, reminderHour: 20,
                now: notifMoment(10), calendar: notifIstanbul) == nil,
               "önceki uyarının üstünden yedi gün geçmeden yenisi kurulmuyor")
        expect(LatvianNotificationRules.decayMoment(
                scheduledAt: notifMoment(12, day: 1), rescueAt: nil, reminderHour: 20,
                now: notifMoment(10), calendar: notifIstanbul)
               == notifMoment(12, day: 17),
               "soğuma dolduktan sonra yeni uyarı kurulabiliyor")

        print("\n=== Bildirim kuralları: plan ===")

        let notifFreshPlan = LatvianNotificationRules.plan(
            progress: LatvianProgress.new(), pack: pack, recentLessonHours: [],
            currentReminderHour: nil, scheduledDecayAt: nil,
            now: notifMoment(10), calendar: notifIstanbul
        )
        expect(notifFreshPlan.count == 1, "yeni öğrencide yalnızca günlük hatırlatma var")
        expect(notifFreshPlan[0].id == "letonca.daily", "günlük hatırlatmanın kimliği sabit")
        expect(notifFreshPlan[0].timing == .everyDay(hour: 20, minute: 0),
               "günlük hatırlatma her gün 20:00'de tekrarlıyor")

        var notifFullProgress = notifStreaking
        notifFullProgress.registerSceneCompletion(sceneId: "lv-s01", now: notifMoment(20, day: 1))
        let notifFullPlan = LatvianNotificationRules.plan(
            progress: notifFullProgress, pack: pack, recentLessonHours: [],
            currentReminderHour: nil, scheduledDecayAt: nil,
            now: notifMoment(10), calendar: notifIstanbul
        )
        expect(notifFullPlan.map(\.slot) == [.daily, .streakRescue, .decay],
               "seri tehlikede ve sahne soluyorsa üç kutu da planlanıyor")
        expect(notifFullPlan.map(\.id) == ["letonca.daily", "letonca.streakRescue", "letonca.decay"],
               "kimlikler sabit: yeniden kurmak kopya üretmiyor")
        expect(notifFullPlan[1].timing == .once(year: 2026, month: 8, day: 15, hour: 21, minute: 30),
               "kurtarma bugün 21:30'a planlanıyor")
        expect(notifFullPlan[2].timing == .once(year: 2026, month: 8, day: 17, hour: 12, minute: 0),
               "unutma uyarısı iki gün sonra 12:00'ye planlanıyor")
        expect(notifFullPlan.allSatisfy { !LatvianNotificationRules.isQuietHour($0.hour) },
               "planlanan hiçbir bildirim sessiz saate düşmüyor")
        expect(LatvianNotificationRules.dailyLoad(notifFullPlan) == 2,
               "dolu planda bile bir güne en fazla iki bildirim düşüyor"
               + " (\(LatvianNotificationRules.dailyLoad(notifFullPlan)))")

        let notifReplanned = LatvianNotificationRules.plan(
            progress: notifFullProgress, pack: pack, recentLessonHours: [],
            currentReminderHour: nil, scheduledDecayAt: nil,
            now: notifMoment(10), calendar: notifIstanbul
        )
        expect(notifReplanned == notifFullPlan, "aynı girdi aynı planı veriyor (kayma yok)")

        // Aynı an, farklı dilim: gün sınırı ve dolayısıyla planlanan tarihler yerel.
        let notifWarsawPlan = LatvianNotificationRules.plan(
            progress: notifFullProgress, pack: pack, recentLessonHours: [],
            currentReminderHour: nil, scheduledDecayAt: nil,
            now: notifMoment(0, 30), calendar: notifWarsaw
        )
        expect(notifWarsawPlan.allSatisfy { !LatvianNotificationRules.isQuietHour($0.hour) },
               "dilim değişse de plan sessiz saate bildirim koymuyor")
        expect(LatvianNotificationRules.dailyLoad(notifWarsawPlan) <= 2,
               "dilim değişse de günde en fazla iki bildirim")

        expect(LatvianNotificationRules.plannedIdentifiers.count == 3,
               "plan üç kutu kuruyor")
        expect(LatvianNotificationRules.managedIdentifiers.count == 6,
               "kapatma altı kimliği birden siliyor (üç plan + üç dönüm noktası)")
        expect(LatvianNotificationRules.managedIdentifiers
                .allSatisfy { $0.hasPrefix(LatvianNotificationRules.idPrefix) },
               "bütün Letonca kimlikleri ortak önekle başlıyor — başka bildirim silinmiyor")
        expect(Set(LatvianNotificationRules.managedIdentifiers).count
               == LatvianNotificationRules.managedIdentifiers.count,
               "kimlikler tekil")

        if failures > 0 {
            fputs("\n\(failures) kontrol başarısız.\n", stderr)
            exit(1)
        }
        print("\nLetonca birim kontrolleri ve paket taraması geçti.\n")
    }
}
