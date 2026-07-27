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

        if failures > 0 {
            fputs("\n\(failures) kontrol başarısız.\n", stderr)
            exit(1)
        }
        print("\nTüm Letonca motor kontrolleri geçti.\n")
    }
}
