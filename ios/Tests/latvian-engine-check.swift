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
         "caseForm":{"base":"kafija","form":"ar kafiju","case":"instrumental","suffix":"u","distractorSuffixes":["a","as"]}}
      ],
      "sentences": [
        {"id":"s1","lv":"Labdien, mani sauc Leyla.","tr":"İyi günler, benim adım Leyla.","audioId":"a5",
         "wordIds":["w1"],"supports":["lv_to_tr","tr_to_lv","order","dictation","fill_blank"]},
        {"id":"s2","lv":"Es gribu kafiju.","tr":"Kahve istiyorum.","audioId":"a6",
         "wordIds":["w4"],"supports":["tr_to_lv","order","case_drill"]}
      ]
    }
  ]
}
"""

@main
struct LatvianEngineCheck {
    static func main() throws {
        print("\n=== Letonca paket modeli ===")

        let pack = try LatvianPack.decode(from: Data(samplePackJSON.utf8))

        expect(pack.scenes.count == 1, "sahne çözümleniyor")
        expect(pack.scenes[0].words.count == 4, "kelimeler çözümleniyor")
        expect(pack.scenes[0].words[0].icon == "👋", "emoji çözümleniyor")
        expect(pack.scenes[0].words[1].icon == nil, "emojisi olmayan kelime nil dönüyor")
        expect(pack.scenes[0].words[3].caseForm?.suffix == "u", "çekim bilgisi çözümleniyor")
        expect(pack.scenes[0].sentences[0].supports.contains(.lvToTr), "soru tipleri çözümleniyor")
        expect(pack.word(id: "w2")?.lv == "paldies", "kelime id ile bulunuyor")
        expect(pack.word(id: "yok") == nil, "olmayan kelime nil dönüyor")
        expect(pack.scene(id: "lv-s01")?.title == "Tanışma", "sahne id ile bulunuyor")
        expect(pack.audioURL(for: "a1").absoluteString == "https://blob.example.com/letonca/ses/a1.mp3",
               "ses adresi kuruluyor")

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

        let allAudio: Set<String> = ["a1", "a2", "a3", "a4", "a5", "a6"]
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
            expect(Set(bank) == Set(answer), "kelime bankası cevabın tüm parçalarını içeriyor")
        } else {
            expect(false, "sıralama kelime bankası üretiyor")
        }

        let caseDrill = factory.makeExercise(wordId: "w4", kind: .caseDrill, seed: 4, availableAudio: allAudio)
        expect(caseDrill != nil, "çekim bilgisi olan kelimede hal tatbikatı üretiliyor")
        if case .choice(let options, let correct)? = caseDrill?.content {
            expect(options.count == 3, "hal tatbikatı üç ek seçeneği sunuyor")
            expect(options[correct] == "u", "doğru ek işaretli")
        }
        expect(caseDrill?.carrier?.contains("kafij") == true, "hal tatbikatı taşıyıcı cümle gösteriyor")
        expect(factory.makeExercise(wordId: "w1", kind: .caseDrill, seed: 4, availableAudio: allAudio) == nil,
               "çekim bilgisi olmayan kelimede hal tatbikatı üretilmiyor")

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

        if failures > 0 {
            fputs("\n\(failures) kontrol başarısız.\n", stderr)
            exit(1)
        }
        print("\nTüm Letonca motor kontrolleri geçti.\n")
    }
}
