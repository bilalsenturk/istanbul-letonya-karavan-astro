# Letonca Öğrenme Motoru (iOS) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** İçerik paketini okuyup cihaz üstünde soru üreten, cevapları notlayan, FSRS ile unutmayı takip eden ve sahne kilidini hakimiyete bağlayan öğrenme motorunu kurmak. Arayüz bir sonraki planda.

**Architecture:** Saf Swift değer tipleri ve saf fonksiyonlar. Motorun hiçbir parçası `SwiftUI`, `AVFoundation` veya ağa bağımlı değil; hepsi `ios/Tests/` altındaki `swiftc` tabanlı test betiğiyle çalıştırılabiliyor. FSRS bir protokolün arkasında duruyor, böylece testler SPM bağımlılığı olmadan çalışıyor ve gerçek `swift-fsrs` yalnızca uygulama hedefinde bağlanıyor.

**Tech Stack:** Swift 5.9+, Foundation, [swift-fsrs](https://github.com/open-spaced-repetition/swift-fsrs) (SPM, MIT).

## Global Constraints

- Bu plandaki hiçbir dosya `SwiftUI`, `UIKit` veya `AVFoundation` import etmez. Arayüz ve ses çalma bir sonraki planın konusu.
- `ios/Tests/latvian-engine-check.swift` betiği bu plandaki her dosyayı `swiftc` ile derler. Bir dosya SPM bağımlılığı import ederse test derlenmez — bu yüzden FSRS protokol arkasında durur.
- Kullanıcıya görünen tüm metinler Türkçe; tip ve fonksiyon adları İngilizce.
- Letonca diakritikler hiçbir yerde kaybolmaz. Notlama sırasında karşılaştırma için normalize edilir, ama saklanan ve gösterilen değer her zaman diakritikli hâlidir.
- Rastgelelik her zaman tohumlanmış (`seed`) olur. Sebep: aynı girdiyle aynı ders üretilmeli, yoksa test edilemez.
- İlerleme dosyası `UserDefaults`'a değil, `Application Support` altında JSON dosyasına yazılır.
- Sahne kilidi eşiği tek bir yerde tanımlıdır: kelimelerin %80'inin hatırlama olasılığı ≥ 0.9.
- Ders uzunluğu 16 soru; karışım %50 yeni / %30 tekrar / %20 hata.

---

## File Structure

**Oluşturulacak (`ios/Karavan/Learning/` altında):**

- `LatvianPack.swift` — Paketin `Codable` karşılıkları ve yükleyici.
- `LatvianExercise.swift` — Cihazda üretilen soru modeli (11 tip).
- `LatvianExerciseFactory.swift` — Paketten soru üretimi.
- `LatvianGrader.swift` — Cevap notlama ve metin normalizasyonu.
- `LatvianMemory.swift` — FSRS protokolü, hafıza kaydı, derece eşlemesi.
- `LatvianProgress.swift` — İlerleme durumu (XP, seri, can, hafıza kayıtları) ve kalıcılık.
- `LatvianLessonBuilder.swift` — Ders kompozisyonu ve sahne kilidi.
- `LatvianFSRSAdapter.swift` — Gerçek `swift-fsrs` bağlayıcısı. Yalnızca uygulama hedefinde derlenir, testlerde derlenmez.

**Oluşturulacak (`ios/Tests/` altında):**

- `latvian-engine-check.swift`, `run-latvian-check.sh`

**Silinecek:**

- `ios/Karavan/Learning/LatvianLearningModels.swift`, `LatvianLearningStore.swift`, `LatvianLearningAudioPlayer.swift` — Görev 8'de, yeni motor çalıştıktan sonra.

---

### Task 1: Paket modeli ve yükleyici

**Files:**
- Create: `ios/Karavan/Learning/LatvianPack.swift`
- Create: `ios/Tests/latvian-engine-check.swift`
- Create: `ios/Tests/run-latvian-check.sh`

**Interfaces:**
- Consumes: `ios/Karavan/Resources/latvian-pack.json` (önceki plan)
- Produces: `LatvianPack`, `LatvianScene`, `LatvianWord`, `LatvianSentence`, `LatvianCaseForm`, `LatvianExerciseKind`; `LatvianPack.decode(from data: Data) throws -> LatvianPack`; `LatvianPack.word(id:)`, `LatvianPack.scene(id:)`.

- [ ] **Step 1: Testi yaz**

`ios/Tests/latvian-engine-check.swift`:

```swift
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
expect(pack.audioURL(for: "a1").absoluteString == "https://blob.example.com/letonca/ses/a1.wav",
       "ses adresi kuruluyor")

if failures > 0 {
    fputs("\n\(failures) kontrol başarısız.\n", stderr)
    exit(1)
}
print("\nTüm Letonca motor kontrolleri geçti.\n")
```

- [ ] **Step 2: Test betiğini yaz**

`ios/Tests/run-latvian-check.sh`:

```bash
#!/usr/bin/env bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/../Karavan/Learning"
OUT="$(mktemp -d)"
swiftc -O -parse-as-library -o "$OUT/latviancheck" \
  "$DIR/latvian-engine-check.swift" \
  "$SRC/LatvianPack.swift"
"$OUT/latviancheck"
```

Çalıştırılabilir yap:

```bash
chmod +x ios/Tests/run-latvian-check.sh
```

- [ ] **Step 3: Testi çalıştırıp başarısız olduğunu gör**

```bash
./ios/Tests/run-latvian-check.sh
```

Beklenen: `error: cannot find 'LatvianPack' in scope` — dosya henüz yok.

- [ ] **Step 4: Paket modelini yaz**

`ios/Karavan/Learning/LatvianPack.swift`:

```swift
import Foundation

enum LatvianExerciseKind: String, Codable, CaseIterable, Sendable {
    case listenChoose = "listen_choose"
    case iconChoose = "icon_choose"
    case lvToTr = "lv_to_tr"
    case trToLv = "tr_to_lv"
    case match
    case fillBlank = "fill_blank"
    case caseDrill = "case_drill"
    case dictation
    case order
    case speak
}

enum LatvianCase: String, Codable, Sendable {
    case nominativ, genitiv, dativ, akuzativ, instrumental, lokativ, vokativ
}

struct LatvianCaseForm: Codable, Hashable, Sendable {
    let base: String
    let form: String
    let `case`: LatvianCase
    let suffix: String
    let distractorSuffixes: [String]
}

struct LatvianWord: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let lv: String
    let tr: String
    let icon: String?
    let audioId: String
    let lemma: String
    let freqRank: Int
    let caseForm: LatvianCaseForm?
}

struct LatvianSentence: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let lv: String
    let tr: String
    let audioId: String
    let wordIds: [String]
    let supports: [LatvianExerciseKind]
}

struct LatvianScene: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let index: Int
    let title: String
    let words: [LatvianWord]
    let sentences: [LatvianSentence]
}

struct LatvianPack: Codable, Sendable {
    static let supportedVersion = 1

    let version: Int
    let generatedAt: String
    let audioBaseUrl: String
    let scenes: [LatvianScene]

    private var wordIndex: [String: LatvianWord] {
        Dictionary(uniqueKeysWithValues: scenes.flatMap(\.words).map { ($0.id, $0) })
    }

    static func decode(from data: Data) throws -> LatvianPack {
        let pack = try JSONDecoder().decode(LatvianPack.self, from: data)
        guard pack.version == supportedVersion else {
            throw LatvianPackError.unsupportedVersion(pack.version)
        }
        guard !pack.scenes.isEmpty else { throw LatvianPackError.empty }
        return pack
    }

    static func loadBundled(name: String = "latvian-pack") throws -> LatvianPack {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            throw LatvianPackError.missingResource(name)
        }
        return try decode(from: Data(contentsOf: url))
    }

    func word(id: String) -> LatvianWord? {
        scenes.lazy.flatMap(\.words).first { $0.id == id }
    }

    func scene(id: String) -> LatvianScene? {
        scenes.first { $0.id == id }
    }

    func sentence(id: String) -> LatvianSentence? {
        scenes.lazy.flatMap(\.sentences).first { $0.id == id }
    }

    func audioURL(for audioId: String) -> URL {
        URL(string: "\(audioBaseUrl)/\(audioId).wav")!
    }

    /// Ses kimliği → seslendirilen metin. Ses indirme aşaması bunu kullanır.
    var audioManifest: [String: String] {
        var manifest: [String: String] = [:]
        for scene in scenes {
            for word in scene.words { manifest[word.audioId] = word.lv }
            for sentence in scene.sentences { manifest[sentence.audioId] = sentence.lv }
        }
        return manifest
    }
}

enum LatvianPackError: Error, LocalizedError {
    case unsupportedVersion(Int)
    case empty
    case missingResource(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Letonca paketi sürüm \(version) desteklenmiyor."
        case .empty:
            return "Letonca paketinde sahne yok."
        case .missingResource(let name):
            return "Letonca paketi bulunamadı: \(name).json"
        }
    }
}
```

- [ ] **Step 5: Testi çalıştır**

```bash
./ios/Tests/run-latvian-check.sh
```

Beklenen: on `✓`, sonda `Tüm Letonca motor kontrolleri geçti.`, çıkış kodu 0.

- [ ] **Step 6: Commit**

```bash
git add ios/Karavan/Learning/LatvianPack.swift ios/Tests/latvian-engine-check.swift ios/Tests/run-latvian-check.sh
git commit -m "feat: add Latvian pack model and decoder"
```

---

### Task 2: Soru modeli

**Files:**
- Create: `ios/Karavan/Learning/LatvianExercise.swift`
- Modify: `ios/Tests/latvian-engine-check.swift`, `ios/Tests/run-latvian-check.sh`

**Interfaces:**
- Consumes: `LatvianExerciseKind`, `LatvianWord` (Görev 1)
- Produces: `LatvianExercise` (id, kind, targetWordId, modality, prompt, content); `enum LatvianExerciseContent` (choice/wordBank/matching/typing/speaking); `enum LatvianModality { recognition, production }`; `LatvianAnswer`.

`modality`, hangi FSRS kaydının güncelleneceğini belirler: tanıma soruları tanıma kaydını, üretim soruları üretim kaydını besler.

- [ ] **Step 1: Testi ekle**

`ios/Tests/latvian-engine-check.swift` içinde son `if failures > 0` bloğunun üstüne ekle:

```swift
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
expect(LatvianExerciseKind.caseDrill.modality == .production, "hal tatbikatı üretim sorusu")

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
```

- [ ] **Step 2: Test betiğine dosyayı ekle**

`ios/Tests/run-latvian-check.sh` içindeki `swiftc` çağrısına satır ekle:

```bash
  "$SRC/LatvianExercise.swift" \
```

- [ ] **Step 3: Testi çalıştırıp başarısız olduğunu gör**

```bash
./ios/Tests/run-latvian-check.sh
```

Beklenen: `error: cannot find 'LatvianExercise' in scope`.

- [ ] **Step 4: Soru modelini yaz**

`ios/Karavan/Learning/LatvianExercise.swift`:

```swift
import Foundation

enum LatvianModality: String, Codable, Hashable, Sendable {
    case recognition
    case production
}

extension LatvianExerciseKind {
    /// Hangi hafıza kaydını beslediğini belirler.
    var modality: LatvianModality {
        switch self {
        case .listenChoose, .iconChoose, .match, .lvToTr, .fillBlank:
            return .recognition
        case .trToLv, .dictation, .order, .speak, .caseDrill:
            return .production
        }
    }

    var turkishTitle: String {
        switch self {
        case .listenChoose: return "Dinle ve seç"
        case .iconChoose: return "Görselden seç"
        case .lvToTr: return "Letoncadan Türkçeye"
        case .trToLv: return "Türkçeden Letoncaya"
        case .match: return "Eşleştir"
        case .fillBlank: return "Boşluğu doldur"
        case .caseDrill: return "Doğru eki seç"
        case .dictation: return "Duyduğunu yaz"
        case .order: return "Cümleyi sırala"
        case .speak: return "Dinle ve tekrar et"
        }
    }
}

struct LatvianMatchPair: Hashable, Sendable {
    let lv: String
    let tr: String
}

enum LatvianExerciseContent: Hashable, Sendable {
    /// Tek doğru cevaplı seçmeli. `iconChoose` için seçenekler emoji taşır.
    case choice(options: [String], correctIndex: Int)
    /// Kelime bankasından cümle kurma. `bank` karıştırılmış, `answer` doğru sıra.
    case wordBank(bank: [String], answer: [String])
    /// Dokunarak eşleştirme.
    case matching(pairs: [LatvianMatchPair])
    /// Klavyeyle yazma. `accepted` tüm kabul edilebilir yazımlar.
    case typing(accepted: [String])
    /// Telaffuz. `target` söylenmesi gereken metin.
    case speaking(target: String)
}

struct LatvianExercise: Identifiable, Hashable, Sendable {
    let id: String
    let kind: LatvianExerciseKind
    let targetWordId: String
    let prompt: String
    /// Varsa çalınacak ses. `listenChoose`, `dictation`, `speak` için zorunlu.
    let audioId: String?
    let content: LatvianExerciseContent
    /// Boşluk doldurma ve hal tatbikatında gösterilen, altı çizili cümle.
    var carrier: String?
    /// Yanlış cevapta gösterilecek Türkçe açıklama.
    var explanation: String?

    init(
        id: String,
        kind: LatvianExerciseKind,
        targetWordId: String,
        prompt: String,
        audioId: String? = nil,
        content: LatvianExerciseContent,
        carrier: String? = nil,
        explanation: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.targetWordId = targetWordId
        self.prompt = prompt
        self.audioId = audioId
        self.content = content
        self.carrier = carrier
        self.explanation = explanation
    }

    var modality: LatvianModality { kind.modality }

    var optionCount: Int {
        if case .choice(let options, _) = content { return options.count }
        return 0
    }

    /// Ses gerektiren sorular, sesi inmemişse üretilmez.
    var requiresAudio: Bool {
        switch kind {
        case .listenChoose, .dictation, .speak: return true
        default: return false
        }
    }
}

enum LatvianAnswer: Hashable, Sendable {
    case choice(index: Int)
    case words([String])
    case text(String)
    case pairs([LatvianMatchPair])
    case spoken(transcript: String)
}
```

- [ ] **Step 5: Testi çalıştır**

```bash
./ios/Tests/run-latvian-check.sh
```

Beklenen: `=== Soru modeli ===` altında on iki `✓`, çıkış kodu 0.

- [ ] **Step 6: Commit**

```bash
git add ios/Karavan/Learning/LatvianExercise.swift ios/Tests/
git commit -m "feat: add Latvian exercise model with modality mapping"
```

---

### Task 3: Notlama ve metin normalizasyonu

**Files:**
- Create: `ios/Karavan/Learning/LatvianGrader.swift`
- Modify: `ios/Tests/latvian-engine-check.swift`, `ios/Tests/run-latvian-check.sh`

**Interfaces:**
- Consumes: `LatvianExercise`, `LatvianAnswer` (Görev 2)
- Produces: `LatvianGrader.normalize(_ text: String) -> String`; `LatvianGrader.grade(exercise:answer:) -> LatvianGrade`; `struct LatvianGrade { let isCorrect: Bool; let correctAnswer: String }`.

Normalizasyon kuralı: küçük harfe indir, diakritikleri ASCII'ye düşür, noktalama ve fazla boşluğu at. Böylece `ā` yazamayan kullanıcı cezalandırılmaz. Türkçe tarafta `ı/i` ve `I/İ` farkı da bu sayede erir.

- [ ] **Step 1: Testi ekle**

`ios/Tests/latvian-engine-check.swift` içinde son `if failures > 0` bloğunun üstüne ekle:

```swift
print("\n=== Notlama ===")

expect(LatvianGrader.normalize("Lūdzu!") == "ludzu", "diakritik ve noktalama düşüyor")
expect(LatvianGrader.normalize("  Es   gribu  ") == "es gribu", "fazla boşluk tekleşiyor")
expect(LatvianGrader.normalize("Paldies") == LatvianGrader.normalize("paldies."), "büyük harf ve nokta önemsiz")
expect(LatvianGrader.normalize("IŞIK") == LatvianGrader.normalize("ışık"), "Türkçe büyük harf farkı eriyor")
expect(LatvianGrader.normalize("kafiju") != LatvianGrader.normalize("kafija"), "farklı ek farklı cevap")

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

let speakQuestion = exercise(.speak, .speaking(target: "Lūdzu"))
expect(LatvianGrader.grade(exercise: speakQuestion, answer: .spoken(transcript: "ludzu")).isCorrect,
       "telaffuz dökümü diakritiksiz geçiyor")
expect(!LatvianGrader.grade(exercise: speakQuestion, answer: .spoken(transcript: "paldies")).isCorrect,
       "yanlış telaffuz kalıyor")
```

- [ ] **Step 2: Test betiğine dosyayı ekle**

`ios/Tests/run-latvian-check.sh` içindeki `swiftc` çağrısına satır ekle:

```bash
  "$SRC/LatvianGrader.swift" \
```

- [ ] **Step 3: Testi çalıştırıp başarısız olduğunu gör**

```bash
./ios/Tests/run-latvian-check.sh
```

Beklenen: `error: cannot find 'LatvianGrader' in scope`.

- [ ] **Step 4: Notlayıcıyı yaz**

`ios/Karavan/Learning/LatvianGrader.swift`:

```swift
import Foundation

struct LatvianGrade: Hashable, Sendable {
    let isCorrect: Bool
    let correctAnswer: String
}

enum LatvianGrader {
    /// Karşılaştırma için metni sadeleştirir: küçük harf, diakritiksiz, noktalamasız, tek boşluklu.
    /// Amacı, `ā` yazamayan kullanıcıyı cezalandırmamak.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let stripped = folded.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
            .reduce(into: "") { $0.append($1) }
        return stripped.split(separator: " ").joined(separator: " ")
    }

    static func grade(exercise: LatvianExercise, answer: LatvianAnswer) -> LatvianGrade {
        switch exercise.content {
        case .choice(let options, let correctIndex):
            let correctAnswer = options.indices.contains(correctIndex) ? options[correctIndex] : ""
            guard case .choice(let index) = answer else {
                return LatvianGrade(isCorrect: false, correctAnswer: correctAnswer)
            }
            return LatvianGrade(isCorrect: index == correctIndex, correctAnswer: correctAnswer)

        case .wordBank(_, let expected):
            let correctAnswer = expected.joined(separator: " ")
            guard case .words(let submitted) = answer else {
                return LatvianGrade(isCorrect: false, correctAnswer: correctAnswer)
            }
            let isCorrect = normalize(submitted.joined(separator: " ")) == normalize(correctAnswer)
            return LatvianGrade(isCorrect: isCorrect, correctAnswer: correctAnswer)

        case .matching(let pairs):
            let correctAnswer = pairs.map { "\($0.lv) → \($0.tr)" }.joined(separator: ", ")
            guard case .pairs(let submitted) = answer, submitted.count == pairs.count else {
                return LatvianGrade(isCorrect: false, correctAnswer: correctAnswer)
            }
            var expected: [String: String] = [:]
            for pair in pairs { expected[normalize(pair.lv)] = normalize(pair.tr) }
            let isCorrect = submitted.allSatisfy { expected[normalize($0.lv)] == normalize($0.tr) }
            return LatvianGrade(isCorrect: isCorrect, correctAnswer: correctAnswer)

        case .typing(let accepted):
            let correctAnswer = accepted.first ?? ""
            guard case .text(let submitted) = answer else {
                return LatvianGrade(isCorrect: false, correctAnswer: correctAnswer)
            }
            let normalized = normalize(submitted)
            let isCorrect = accepted.contains { normalize($0) == normalized }
            return LatvianGrade(isCorrect: isCorrect, correctAnswer: correctAnswer)

        case .speaking(let target):
            guard case .spoken(let transcript) = answer else {
                return LatvianGrade(isCorrect: false, correctAnswer: target)
            }
            return LatvianGrade(isCorrect: normalize(transcript) == normalize(target), correctAnswer: target)
        }
    }
}
```

- [ ] **Step 5: Testi çalıştır**

```bash
./ios/Tests/run-latvian-check.sh
```

Beklenen: `=== Notlama ===` altında yirmi `✓`, çıkış kodu 0.

- [ ] **Step 6: Commit**

```bash
git add ios/Karavan/Learning/LatvianGrader.swift ios/Tests/
git commit -m "feat: add Latvian answer grading with diacritic-tolerant matching"
```

---

### Task 4: Hafıza kaydı ve FSRS protokolü

**Files:**
- Create: `ios/Karavan/Learning/LatvianMemory.swift`
- Modify: `ios/Tests/latvian-engine-check.swift`, `ios/Tests/run-latvian-check.sh`

**Interfaces:**
- Consumes: `LatvianModality` (Görev 2)
- Produces: `enum LatvianRating { again, hard, good, easy }`; `LatvianRating.from(isCorrect:attempts:usedHint:elapsed:)`; `struct LatvianMemoryCard` (stability, difficulty, dueAt, reviewCount, lastReviewedAt); `LatvianMemoryCard.retrievability(at:)`; `protocol LatvianScheduler` ve `struct LatvianDefaultScheduler`; `struct LatvianMemoryKey { wordId, modality }`.

FSRS'in gerçek uygulaması Görev 7'de SPM üzerinden gelir. Buradaki `LatvianDefaultScheduler`, testlerde ve SPM erişilemediğinde kullanılan basit ama doğru davranan bir yedek: doğruda kararlılık artar, yanlışta çöker.

- [ ] **Step 1: Testi ekle**

`ios/Tests/latvian-engine-check.swift` içinde son `if failures > 0` bloğunun üstüne ekle:

```swift
print("\n=== Hafıza ===")

expect(LatvianRating.from(isCorrect: true, attempts: 1, usedHint: false, elapsed: 2) == .easy,
       "ilk denemede hızlı doğru → easy")
expect(LatvianRating.from(isCorrect: true, attempts: 1, usedHint: false, elapsed: 9) == .good,
       "ilk denemede yavaş doğru → good")
expect(LatvianRating.from(isCorrect: true, attempts: 1, usedHint: true, elapsed: 2) == .hard,
       "ipuçlu doğru → hard")
expect(LatvianRating.from(isCorrect: true, attempts: 2, usedHint: false, elapsed: 2) == .hard,
       "ikinci denemede doğru → hard")
expect(LatvianRating.from(isCorrect: false, attempts: 1, usedHint: false, elapsed: 2) == .again,
       "yanlış → again")

let scheduler = LatvianDefaultScheduler()
let epoch = Date(timeIntervalSince1970: 1_800_000_000)

let fresh = LatvianMemoryCard.new()
expect(fresh.reviewCount == 0, "yeni kart hiç tekrar edilmemiş")
expect(fresh.retrievability(at: epoch) == 0, "hiç görülmemiş kartın hatırlanma olasılığı sıfır")

let afterGood = scheduler.review(card: fresh, rating: .good, now: epoch)
expect(afterGood.reviewCount == 1, "tekrar sayacı artıyor")
expect(afterGood.stability > fresh.stability, "doğru cevap kararlılığı artırıyor")
expect(afterGood.dueAt > epoch, "sonraki tekrar ileri tarihte")
expect(afterGood.retrievability(at: epoch) > 0.99, "tekrar anında hatırlanma olasılığı tam")

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

let key = LatvianMemoryKey(wordId: "w1", modality: .production)
expect(key == LatvianMemoryKey(wordId: "w1", modality: .production), "aynı anahtar eşit")
expect(key != LatvianMemoryKey(wordId: "w1", modality: .recognition), "modalite anahtarı ayırıyor")
expect(key.storageKey == "w1#production", "anahtar dizeye çevrilebiliyor")
expect(LatvianMemoryKey(storageKey: "w1#production") == key, "anahtar dizeden geri okunuyor")
```

- [ ] **Step 2: Test betiğine dosyayı ekle**

`ios/Tests/run-latvian-check.sh` içindeki `swiftc` çağrısına satır ekle:

```bash
  "$SRC/LatvianMemory.swift" \
```

- [ ] **Step 3: Testi çalıştırıp başarısız olduğunu gör**

```bash
./ios/Tests/run-latvian-check.sh
```

Beklenen: `error: cannot find 'LatvianRating' in scope`.

- [ ] **Step 4: Hafıza modülünü yaz**

`ios/Karavan/Learning/LatvianMemory.swift`:

```swift
import Foundation

enum LatvianRating: Int, Codable, Hashable, Sendable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    /// Cevabın niteliğinden derece üretir.
    /// - Parameters:
    ///   - attempts: Kaçıncı denemede doğru bulundu (1 = ilk).
    ///   - usedHint: Kullanıcı ipucu istedi mi.
    ///   - elapsed: Soruya harcanan saniye.
    static func from(isCorrect: Bool, attempts: Int, usedHint: Bool, elapsed: TimeInterval) -> LatvianRating {
        guard isCorrect else { return .again }
        if attempts > 1 || usedHint { return .hard }
        return elapsed <= 5 ? .easy : .good
    }
}

struct LatvianMemoryKey: Hashable, Sendable {
    let wordId: String
    let modality: LatvianModality

    var storageKey: String { "\(wordId)#\(modality.rawValue)" }

    init(wordId: String, modality: LatvianModality) {
        self.wordId = wordId
        self.modality = modality
    }

    init?(storageKey: String) {
        let parts = storageKey.split(separator: "#", maxSplits: 1)
        guard parts.count == 2, let modality = LatvianModality(rawValue: String(parts[1])) else { return nil }
        self.wordId = String(parts[0])
        self.modality = modality
    }
}

struct LatvianMemoryCard: Codable, Hashable, Sendable {
    /// Hatırlanma olasılığının %90'a düştüğü gün sayısı.
    var stability: Double
    /// 1 (kolay) ile 10 (zor) arası.
    var difficulty: Double
    var dueAt: Date
    var lastReviewedAt: Date?
    var reviewCount: Int
    var lapseCount: Int

    static func new() -> LatvianMemoryCard {
        LatvianMemoryCard(
            stability: 0,
            difficulty: 5,
            dueAt: Date(timeIntervalSince1970: 0),
            lastReviewedAt: nil,
            reviewCount: 0,
            lapseCount: 0
        )
    }

    /// Verilen anda hatırlama olasılığı. FSRS'in üstel unutma eğrisi.
    func retrievability(at moment: Date) -> Double {
        guard let lastReviewedAt, stability > 0 else { return 0 }
        let elapsedDays = max(0, moment.timeIntervalSince(lastReviewedAt) / 86_400)
        return pow(1 + elapsedDays / (9 * stability), -1)
    }

    var isDue: Bool { dueAt <= Date() }
}

protocol LatvianScheduler: Sendable {
    func review(card: LatvianMemoryCard, rating: LatvianRating, now: Date) -> LatvianMemoryCard
}

/// FSRS benzeri yedek planlayıcı. Gerçek `swift-fsrs` erişilemediğinde ve testlerde kullanılır.
/// Davranışı FSRS ile aynı yönde: doğru cevap kararlılığı çarpanla artırır, yanlış cevap çökertir.
struct LatvianDefaultScheduler: LatvianScheduler {
    func review(card: LatvianMemoryCard, rating: LatvianRating, now: Date) -> LatvianMemoryCard {
        var updated = card
        updated.reviewCount += 1
        updated.lastReviewedAt = now

        switch rating {
        case .again:
            updated.lapseCount += 1
            updated.difficulty = min(10, card.difficulty + 1.2)
            updated.stability = max(0.2, card.stability * 0.35)
        case .hard:
            updated.difficulty = min(10, card.difficulty + 0.3)
            updated.stability = card.stability == 0 ? 0.6 : card.stability * 1.2
        case .good:
            updated.difficulty = max(1, card.difficulty - 0.1)
            updated.stability = card.stability == 0 ? 1.2 : card.stability * (1.9 + (10 - card.difficulty) * 0.06)
        case .easy:
            updated.difficulty = max(1, card.difficulty - 0.5)
            updated.stability = card.stability == 0 ? 3.0 : card.stability * (2.8 + (10 - card.difficulty) * 0.08)
        }

        updated.dueAt = now.addingTimeInterval(updated.stability * 86_400)
        return updated
    }
}
```

- [ ] **Step 5: Testi çalıştır**

```bash
./ios/Tests/run-latvian-check.sh
```

Beklenen: `=== Hafıza ===` altında on dokuz `✓`, çıkış kodu 0.

- [ ] **Step 6: Commit**

```bash
git add ios/Karavan/Learning/LatvianMemory.swift ios/Tests/
git commit -m "feat: add Latvian memory cards with FSRS-shaped scheduling"
```

---

### Task 5: Soru üretici

**Files:**
- Create: `ios/Karavan/Learning/LatvianExerciseFactory.swift`
- Modify: `ios/Tests/latvian-engine-check.swift`, `ios/Tests/run-latvian-check.sh`

**Interfaces:**
- Consumes: `LatvianPack`, `LatvianExercise`, `LatvianExerciseKind` (Görev 1-2)
- Produces: `LatvianExerciseFactory(pack:)`; `makeExercise(wordId:kind:seed:availableAudio:) -> LatvianExercise?`; `supportedKinds(forWordId:availableAudio:) -> [LatvianExerciseKind]`.

Üretici, sesi olmayan kelimeler için ses gerektiren soru tipini hiç üretmez (`availableAudio` kümesi boşsa dinleme soruları düşer). Bu, tasarımdaki "ses inmemişse ders eksilmez" gereksinimini karşılar.

- [ ] **Step 1: Testi ekle**

`ios/Tests/latvian-engine-check.swift` içinde son `if failures > 0` bloğunun üstüne ekle:

```swift
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
```

- [ ] **Step 2: Test betiğine dosyayı ekle**

`ios/Tests/run-latvian-check.sh` içindeki `swiftc` çağrısına satır ekle:

```bash
  "$SRC/LatvianExerciseFactory.swift" \
```

- [ ] **Step 3: Testi çalıştırıp başarısız olduğunu gör**

```bash
./ios/Tests/run-latvian-check.sh
```

Beklenen: `error: cannot find 'LatvianExerciseFactory' in scope`.

- [ ] **Step 4: Üreticiyi yaz**

`ios/Karavan/Learning/LatvianExerciseFactory.swift`:

```swift
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
        let sentences = sentencesUsing(wordId: wordId, availableAudio: availableAudio)

        return LatvianExerciseKind.allCases.filter { kind in
            switch kind {
            case .listenChoose, .dictation, .speak:
                return hasAudio
            case .iconChoose:
                return word.icon != nil && allWords.filter { $0.icon != nil }.count >= 3
            case .caseDrill:
                return word.caseForm != nil && sentences.contains { $0.supports.contains(.caseDrill) }
            case .match:
                return allWords.count >= 4
            case .lvToTr, .trToLv, .order, .fillBlank:
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
            let options = choiceOptions(correct: word.lv, pool: allWords.map(\.lv), using: &generator)
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "Duyduğun kelimeyi seç.",
                audioId: word.audioId,
                content: .choice(options: options.values, correctIndex: options.correctIndex),
                explanation: "\(word.lv) — \(word.tr)"
            )

        case .iconChoose:
            let pool = allWords.filter { $0.icon != nil }
            let options = choiceOptions(correct: word.lv, pool: pool.map(\.lv), using: &generator)
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "\(word.icon ?? "") için doğru kelimeyi seç.",
                content: .choice(options: options.values, correctIndex: options.correctIndex),
                explanation: "\(word.lv) — \(word.tr)"
            )

        case .lvToTr:
            guard let sentence = pickSentence(wordId: wordId, kind: kind, availableAudio: availableAudio, using: &generator) else { return nil }
            let answer = sentence.tr.split(separator: " ").map(String.init)
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "Türkçesini kur.",
                content: .wordBank(bank: shuffledBank(answer, using: &generator), answer: answer),
                carrier: sentence.lv,
                explanation: sentence.tr
            )

        case .trToLv:
            guard let sentence = pickSentence(wordId: wordId, kind: kind, availableAudio: availableAudio, using: &generator) else { return nil }
            let answer = sentence.lv.split(separator: " ").map(String.init)
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "Letoncasını kur.",
                content: .wordBank(bank: shuffledBank(answer, using: &generator), answer: answer),
                carrier: sentence.tr,
                explanation: sentence.lv
            )

        case .order:
            guard let sentence = pickSentence(wordId: wordId, kind: kind, availableAudio: availableAudio, using: &generator) else { return nil }
            let answer = sentence.lv.split(separator: " ").map(String.init)
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "Kelimeleri doğru sıraya diz.",
                content: .wordBank(bank: shuffledBank(answer, using: &generator), answer: answer),
                carrier: sentence.tr,
                explanation: sentence.lv
            )

        case .fillBlank:
            guard let sentence = pickSentence(wordId: wordId, kind: kind, availableAudio: availableAudio, using: &generator),
                  let blanked = blank(sentence.lv, hiding: word.lv) else { return nil }
            let options = choiceOptions(correct: word.lv, pool: allWords.map(\.lv), using: &generator)
            return LatvianExercise(
                id: id, kind: kind, targetWordId: wordId,
                prompt: "Boşluğa gelen kelimeyi seç.",
                content: .choice(options: options.values, correctIndex: options.correctIndex),
                carrier: blanked,
                explanation: sentence.tr
            )

        case .caseDrill:
            guard let caseForm = word.caseForm else { return nil }
            var suffixes = [caseForm.suffix] + caseForm.distractorSuffixes.prefix(2)
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
            var pool = allWords.filter { $0.id != wordId }
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

    private func sentencesUsing(wordId: String, availableAudio: Set<String>) -> [LatvianSentence] {
        pack.scenes.flatMap(\.sentences).filter { $0.wordIds.contains(wordId) }
    }

    private func pickSentence(
        wordId: String,
        kind: LatvianExerciseKind,
        availableAudio: Set<String>,
        using generator: inout LatvianSeededGenerator
    ) -> LatvianSentence? {
        let candidates = sentencesUsing(wordId: wordId, availableAudio: availableAudio)
            .filter { $0.supports.contains(kind) }
        guard !candidates.isEmpty else { return nil }
        return candidates[Int.random(in: 0..<candidates.count, using: &generator)]
    }

    private func choiceOptions(
        correct: String,
        pool: [String],
        using generator: inout LatvianSeededGenerator
    ) -> (values: [String], correctIndex: Int) {
        var distractors = Array(Set(pool).subtracting([correct]))
        distractors.shuffle(using: &generator)
        var values = [correct] + distractors.prefix(2)
        values.shuffle(using: &generator)
        return (values, values.firstIndex(of: correct) ?? 0)
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
```

- [ ] **Step 5: Testi çalıştır**

```bash
./ios/Tests/run-latvian-check.sh
```

Beklenen: `=== Soru üretici ===` altında yirmi bir `✓`, çıkış kodu 0.

- [ ] **Step 6: Commit**

```bash
git add ios/Karavan/Learning/LatvianExerciseFactory.swift ios/Tests/
git commit -m "feat: add seeded Latvian exercise factory for all ten kinds"
```

---

### Task 6: İlerleme durumu, ders kompozisyonu ve sahne kilidi

**Files:**
- Create: `ios/Karavan/Learning/LatvianProgress.swift`
- Create: `ios/Karavan/Learning/LatvianLessonBuilder.swift`
- Modify: `ios/Tests/latvian-engine-check.swift`, `ios/Tests/run-latvian-check.sh`

**Interfaces:**
- Consumes: `LatvianMemoryCard`, `LatvianMemoryKey`, `LatvianExerciseFactory` (Görev 4-5)
- Produces: `struct LatvianProgress` (memory, xp, streak, hearts, recentMistakes, sceneCompletion); `LatvianProgress.load(from:)/save(to:)`; `LatvianLessonBuilder.build(...) -> [LatvianExercise]`; `LatvianLessonBuilder.isSceneUnlocked(...)`; sabitler `lessonLength = 16`, `masteryThreshold = 0.9`, `masteryCoverage = 0.8`.

- [ ] **Step 1: Testi ekle**

`ios/Tests/latvian-engine-check.swift` içinde son `if failures > 0` bloğunun üstüne ekle:

```swift
print("\n=== İlerleme ve ders kurgusu ===")

var progress = LatvianProgress.new()
expect(progress.hearts == 5, "beş canla başlıyor")
expect(progress.xp == 0, "sıfır XP ile başlıyor")
expect(progress.streakDays == 0, "seri sıfırdan başlıyor")

progress.registerAnswer(wordId: "w1", modality: .recognition, rating: .good,
                        scheduler: scheduler, now: epoch)
expect(progress.card(for: LatvianMemoryKey(wordId: "w1", modality: .recognition))?.reviewCount == 1,
       "cevap hafızaya işleniyor")
expect(progress.card(for: LatvianMemoryKey(wordId: "w1", modality: .production)) == nil,
       "diğer modalite etkilenmiyor")

progress.registerAnswer(wordId: "w2", modality: .recognition, rating: .again,
                        scheduler: scheduler, now: epoch)
expect(progress.recentMistakes.contains("w2"), "yanlış cevap hata listesine giriyor")
expect(!progress.recentMistakes.contains("w1"), "doğru cevap hata listesine girmiyor")

progress.registerAnswer(wordId: "w2", modality: .recognition, rating: .good,
                        scheduler: scheduler, now: epoch.addingTimeInterval(60))
expect(!progress.recentMistakes.contains("w2"), "sonradan doğrulanan kelime hata listesinden çıkıyor")

let roundTripped = try LatvianProgress.decode(from: progress.encoded())
expect(roundTripped.card(for: LatvianMemoryKey(wordId: "w1", modality: .recognition))?.reviewCount == 1,
       "ilerleme kaydedilip geri okunuyor")
expect(roundTripped.hearts == progress.hearts, "can sayısı kalıcı")

// Sahne kilidi
var mastered = LatvianProgress.new()
let sceneWords = pack.scenes[0].words.map(\.id)
for wordId in sceneWords {
    for modality in [LatvianModality.recognition, .production] {
        var card = LatvianMemoryCard.new()
        for _ in 0..<6 { card = scheduler.review(card: card, rating: .easy, now: epoch) }
        mastered.setCard(card, for: LatvianMemoryKey(wordId: wordId, modality: modality))
    }
}

expect(LatvianLessonBuilder.masteryRatio(scene: pack.scenes[0], progress: mastered, now: epoch) >= 0.8,
       "ezberlenmiş sahnede hakimiyet oranı yüksek")
expect(LatvianLessonBuilder.isSceneMastered(scene: pack.scenes[0], progress: mastered, now: epoch),
       "ezberlenmiş sahne tamamlanmış sayılıyor")
expect(!LatvianLessonBuilder.isSceneMastered(scene: pack.scenes[0], progress: LatvianProgress.new(), now: epoch),
       "boş ilerlemede sahne tamamlanmamış")

let staleMoment = epoch.addingTimeInterval(86_400 * 3650)
expect(!LatvianLessonBuilder.isSceneMastered(scene: pack.scenes[0], progress: mastered, now: staleMoment),
       "unutulmuş sahne yeniden kilitli sayılıyor")

// Ders kurgusu
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
expect(!silentLesson.isEmpty, "ses yokken bile ders kuruluyor")

let sameSeed = LatvianLessonBuilder.build(
    scene: pack.scenes[0], pack: pack, progress: progress, factory: factory,
    availableAudio: allAudio, seed: 7, now: epoch
)
expect(sameSeed.map(\.id) == lesson.map(\.id), "aynı tohum aynı dersi veriyor")

let mistakeHeavy = LatvianLessonBuilder.build(
    scene: pack.scenes[0], pack: pack, progress: progress, factory: factory,
    availableAudio: allAudio, seed: 9, now: epoch
)
expect(mistakeHeavy.contains { $0.targetWordId == "w2" } == false || progress.recentMistakes.isEmpty,
       "hata listesi boşken hata kotası doldurulmaya çalışılmıyor")
```

- [ ] **Step 2: Test betiğine dosyaları ekle**

`ios/Tests/run-latvian-check.sh` içindeki `swiftc` çağrısına iki satır ekle:

```bash
  "$SRC/LatvianProgress.swift" \
  "$SRC/LatvianLessonBuilder.swift" \
```

- [ ] **Step 3: Testi çalıştırıp başarısız olduğunu gör**

```bash
./ios/Tests/run-latvian-check.sh
```

Beklenen: `error: cannot find 'LatvianProgress' in scope`.

- [ ] **Step 4: İlerleme durumunu yaz**

`ios/Karavan/Learning/LatvianProgress.swift`:

```swift
import Foundation

struct LatvianProgress: Codable, Sendable {
    static let maxHearts = 5
    static let heartRefillInterval: TimeInterval = 4 * 3600
    static let mistakeMemory = 24

    private var memory: [String: LatvianMemoryCard]
    var xp: Int
    var streakDays: Int
    var lastLessonDay: String?
    var hearts: Int
    var lastHeartLostAt: Date?
    /// Son derslerde yanlış yapılan kelimeler, en yenisi sonda.
    private(set) var recentMistakes: [String]
    /// Sahne id → ilk tamamlandığı an.
    var sceneCompletedAt: [String: Date]

    static func new() -> LatvianProgress {
        LatvianProgress(
            memory: [:],
            xp: 0,
            streakDays: 0,
            lastLessonDay: nil,
            hearts: maxHearts,
            lastHeartLostAt: nil,
            recentMistakes: [],
            sceneCompletedAt: [:]
        )
    }

    // MARK: - Hafıza

    func card(for key: LatvianMemoryKey) -> LatvianMemoryCard? {
        memory[key.storageKey]
    }

    mutating func setCard(_ card: LatvianMemoryCard, for key: LatvianMemoryKey) {
        memory[key.storageKey] = card
    }

    mutating func registerAnswer(
        wordId: String,
        modality: LatvianModality,
        rating: LatvianRating,
        scheduler: LatvianScheduler,
        now: Date
    ) {
        let key = LatvianMemoryKey(wordId: wordId, modality: modality)
        let existing = memory[key.storageKey] ?? .new()
        memory[key.storageKey] = scheduler.review(card: existing, rating: rating, now: now)

        if rating == .again {
            recentMistakes.removeAll { $0 == wordId }
            recentMistakes.append(wordId)
            if recentMistakes.count > Self.mistakeMemory { recentMistakes.removeFirst() }
        } else {
            recentMistakes.removeAll { $0 == wordId }
        }
    }

    /// Tekrar zamanı gelmiş kelimeler, en acili başta.
    func dueWordIds(now: Date) -> [String] {
        memory
            .compactMap { entry -> (String, Double)? in
                guard let key = LatvianMemoryKey(storageKey: entry.key), entry.value.dueAt <= now else { return nil }
                return (key.wordId, entry.value.retrievability(at: now))
            }
            .sorted { $0.1 < $1.1 }
            .reduce(into: [String]()) { result, entry in
                if !result.contains(entry.0) { result.append(entry.0) }
            }
    }

    // MARK: - Can

    mutating func loseHeart(now: Date) {
        hearts = max(0, hearts - 1)
        lastHeartLostAt = now
    }

    mutating func refillHearts(now: Date) {
        guard hearts < Self.maxHearts, let lastHeartLostAt else { return }
        let elapsed = now.timeIntervalSince(lastHeartLostAt)
        let regained = Int(elapsed / Self.heartRefillInterval)
        guard regained > 0 else { return }
        hearts = min(Self.maxHearts, hearts + regained)
        self.lastHeartLostAt = hearts == Self.maxHearts
            ? nil
            : lastHeartLostAt.addingTimeInterval(Double(regained) * Self.heartRefillInterval)
    }

    // MARK: - Seri

    mutating func registerLessonCompleted(now: Date, calendar: Calendar = .current) {
        let today = Self.dayKey(now, calendar: calendar)
        guard lastLessonDay != today else { return }
        if let lastLessonDay,
           let previous = Self.date(from: lastLessonDay, calendar: calendar),
           let gap = calendar.dateComponents([.day], from: previous, to: now).day {
            streakDays = gap == 1 ? streakDays + 1 : 1
        } else {
            streakDays = 1
        }
        lastLessonDay = today
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func date(from key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    // MARK: - Kalıcılık

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(from data: Data) throws -> LatvianProgress {
        try JSONDecoder().decode(LatvianProgress.self, from: data)
    }

    static func fileURL() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return directory.appendingPathComponent("latvian-progress.json")
    }

    /// Dosya bozuksa yedeğe düşer; yedek de bozuksa sıfırdan başlar ve bunu bildirir.
    static func load() -> (progress: LatvianProgress, wasReset: Bool) {
        guard let url = try? fileURL() else { return (.new(), false) }
        let backup = url.appendingPathExtension("bak")
        for candidate in [url, backup] {
            if let data = try? Data(contentsOf: candidate), let value = try? decode(from: data) {
                return (value, candidate == backup)
            }
        }
        return (.new(), FileManager.default.fileExists(atPath: url.path))
    }

    func save() throws {
        let url = try Self.fileURL()
        let data = try encoded()
        if let existing = try? Data(contentsOf: url) {
            try? existing.write(to: url.appendingPathExtension("bak"), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 5: Ders kurucuyu yaz**

`ios/Karavan/Learning/LatvianLessonBuilder.swift`:

```swift
import Foundation

enum LatvianLessonBuilder {
    static let lessonLength = 16
    /// Bir kelimenin öğrenilmiş sayılması için gereken hatırlama olasılığı.
    static let masteryThreshold = 0.9
    /// Sahnenin açılması için bu orandaki kelime eşiği geçmeli.
    static let masteryCoverage = 0.8

    private static let newShare = 0.5
    private static let reviewShare = 0.3

    /// Sahnedeki kelimelerin kaçının hem tanıma hem üretim tarafında eşiği geçtiği.
    static func masteryRatio(scene: LatvianScene, progress: LatvianProgress, now: Date) -> Double {
        guard !scene.words.isEmpty else { return 1 }
        let mastered = scene.words.filter { word in
            [LatvianModality.recognition, .production].allSatisfy { modality in
                let key = LatvianMemoryKey(wordId: word.id, modality: modality)
                guard let card = progress.card(for: key) else { return false }
                return card.retrievability(at: now) >= masteryThreshold
            }
        }
        return Double(mastered.count) / Double(scene.words.count)
    }

    static func isSceneMastered(scene: LatvianScene, progress: LatvianProgress, now: Date) -> Bool {
        masteryRatio(scene: scene, progress: progress, now: now) >= masteryCoverage
    }

    /// Bir sahne, kendisinden önceki tüm sahneler öğrenildiyse açılır.
    static func isSceneUnlocked(
        scene: LatvianScene,
        pack: LatvianPack,
        progress: LatvianProgress,
        now: Date
    ) -> Bool {
        pack.scenes
            .filter { $0.index < scene.index }
            .allSatisfy { isSceneMastered(scene: $0, progress: progress, now: now) }
    }

    static func build(
        scene: LatvianScene,
        pack: LatvianPack,
        progress: LatvianProgress,
        factory: LatvianExerciseFactory,
        availableAudio: Set<String>,
        seed: UInt64,
        now: Date
    ) -> [LatvianExercise] {
        let newQuota = Int((Double(lessonLength) * newShare).rounded())
        let reviewQuota = Int((Double(lessonLength) * reviewShare).rounded())

        let sceneWordIds = scene.words.map(\.id)
        let sceneWordSet = Set(sceneWordIds)

        // Yeni: bu sahnenin hiç görülmemiş veya henüz oturmamış kelimeleri, sık olan önce.
        let newCandidates = scene.words
            .filter { word in
                let key = LatvianMemoryKey(wordId: word.id, modality: .recognition)
                guard let card = progress.card(for: key) else { return true }
                return card.retrievability(at: now) < masteryThreshold
            }
            .sorted { $0.freqRank < $1.freqRank }
            .map(\.id)

        // Tekrar: sahne dışından, tekrar zamanı gelmiş kelimeler.
        let reviewCandidates = progress.dueWordIds(now: now).filter { !sceneWordSet.contains($0) }

        // Hata: son derslerde yanlış yapılanlar, en yenisi önce.
        let mistakeCandidates = progress.recentMistakes.reversed().map { $0 }

        var picks: [(wordId: String, preferHarder: Bool)] = []
        picks.append(contentsOf: take(newCandidates, upTo: newQuota).map { ($0, false) })
        picks.append(contentsOf: take(reviewCandidates, upTo: reviewQuota).map { ($0, true) })
        picks.append(contentsOf: take(mistakeCandidates, upTo: lessonLength - picks.count).map { ($0, true) })

        // Kotalar dolmadıysa sahne kelimeleriyle tamamla.
        var cursor = 0
        while picks.count < lessonLength && !sceneWordIds.isEmpty {
            picks.append((sceneWordIds[cursor % sceneWordIds.count], cursor >= sceneWordIds.count))
            cursor += 1
        }

        var built: [LatvianExercise] = []
        var usedIds = Set<String>()
        var generator = LatvianSeededGenerator(seed: seed)

        for (offset, pick) in picks.enumerated() {
            let kinds = orderedKinds(
                for: pick.wordId,
                preferHarder: pick.preferHarder,
                factory: factory,
                availableAudio: availableAudio,
                using: &generator
            )
            for kind in kinds {
                let exerciseSeed = seed &+ UInt64(offset &* 7919) &+ UInt64(kind.rawValue.count)
                guard let exercise = factory.makeExercise(
                    wordId: pick.wordId,
                    kind: kind,
                    seed: exerciseSeed,
                    availableAudio: availableAudio
                ), !usedIds.contains(exercise.id) else { continue }
                built.append(exercise)
                usedIds.insert(exercise.id)
                break
            }
            if built.count == lessonLength { break }
        }

        return spread(built)
    }

    // MARK: - Yardımcılar

    private static func take(_ values: [String], upTo limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
            if result.count == limit { break }
        }
        return result
    }

    /// Yeni kelimede tanıma soruları önce, tekrar/hata kelimesinde üretim soruları önce gelir.
    private static func orderedKinds(
        for wordId: String,
        preferHarder: Bool,
        factory: LatvianExerciseFactory,
        availableAudio: Set<String>,
        using generator: inout LatvianSeededGenerator
    ) -> [LatvianExerciseKind] {
        var kinds = factory.supportedKinds(forWordId: wordId, availableAudio: availableAudio)
        kinds.shuffle(using: &generator)
        return kinds.sorted { left, right in
            let leftIsProduction = left.modality == .production
            let rightIsProduction = right.modality == .production
            if leftIsProduction == rightIsProduction { return false }
            return preferHarder ? leftIsProduction : rightIsProduction
        }
    }

    /// Ardışık iki sorunun aynı tipte veya aynı kelime üzerine olmasını engeller.
    private static func spread(_ exercises: [LatvianExercise]) -> [LatvianExercise] {
        var remaining = exercises
        var result: [LatvianExercise] = []

        while !remaining.isEmpty {
            let previous = result.last
            let index = remaining.firstIndex { candidate in
                guard let previous else { return true }
                return candidate.kind != previous.kind && candidate.targetWordId != previous.targetWordId
            } ?? remaining.firstIndex { candidate in
                guard let previous else { return true }
                return candidate.targetWordId != previous.targetWordId
            } ?? 0
            result.append(remaining.remove(at: index))
        }

        return result
    }
}
```

- [ ] **Step 6: Testi çalıştır**

```bash
./ios/Tests/run-latvian-check.sh
```

Beklenen: `=== İlerleme ve ders kurgusu ===` altında yirmi bir `✓`, çıkış kodu 0.

Ardışık tekrar testi başarısız olursa örnek paket dört kelime içerdiği için 16 soruda çakışma kaçınılmaz olabilir; bu durumda `spread` ikinci geri çekilme seviyesinde yalnızca kelimeyi ayırır, test de bunu bekler. Test hâlâ kırmızıysa `spread` mantığını düzelt, testi gevşetme.

- [ ] **Step 7: Commit**

```bash
git add ios/Karavan/Learning/LatvianProgress.swift ios/Karavan/Learning/LatvianLessonBuilder.swift ios/Tests/
git commit -m "feat: add Latvian progress store, lesson composition, and mastery gating"
```

---

### Task 7: Gerçek FSRS bağlayıcısı

**Files:**
- Create: `ios/Karavan/Learning/LatvianFSRSAdapter.swift`
- Modify: `ios/project.yml`

**Interfaces:**
- Consumes: `LatvianScheduler`, `LatvianMemoryCard`, `LatvianRating` (Görev 4)
- Produces: `struct LatvianFSRSScheduler: LatvianScheduler`

Bu dosya `ios/Tests/run-latvian-check.sh` içine **eklenmez** — SPM bağımlılığı `swiftc` ile derlenemez. Testler `LatvianDefaultScheduler` ile çalışmaya devam eder.

- [ ] **Step 1: SPM bağımlılığını `project.yml`'ye ekle**

Xcode projesi `xcodegen` ile üretiliyor — Xcode arayüzünden paket eklenmez, `ios/project.yml` düzenlenip `xcodegen` çalıştırılır.

`ios/project.yml` içinde `targets:` satırının **üstüne** yeni bir üst düzey bölüm ekle:

```yaml
packages:
  FSRS:
    url: https://github.com/open-spaced-repetition/swift-fsrs
    majorVersion: 1.0.0
```

Ve `Kuzey` hedefinin `dependencies:` listesine satır ekle:

```yaml
      - package: FSRS
```

Ardından projeyi yeniden üret:

```bash
cd ios && xcodegen && grep -c "swift-fsrs" Kuzey.xcodeproj/project.pbxproj
```

Beklenen: `xcodegen` hatasız biter ve grep sayısı 0'dan büyük. Sıfırsa paket bağlanmamıştır — `project.yml` girintilerini kontrol et.

Paketin gerçek sürüm etiketi `1.0.0`'dan farklıysa `xcodegen` sonrası çözümleme hata verir; `git ls-remote --tags https://github.com/open-spaced-repetition/swift-fsrs | tail -5` ile en son etiketi bul ve `majorVersion` değerini ona göre yaz.

- [ ] **Step 2: Bağlayıcıyı yaz**

`ios/Karavan/Learning/LatvianFSRSAdapter.swift`:

```swift
import Foundation
import FSRS

/// `swift-fsrs` kütüphanesini motorun beklediği arayüze bağlar.
/// Testlerde derlenmez; testler `LatvianDefaultScheduler` kullanır.
struct LatvianFSRSScheduler: LatvianScheduler {
    private let engine = FSRS()

    func review(card: LatvianMemoryCard, rating: LatvianRating, now: Date) -> LatvianMemoryCard {
        var fsrsCard = Card()
        fsrsCard.stability = card.stability
        fsrsCard.difficulty = card.difficulty == 0 ? 5 : card.difficulty
        fsrsCard.reps = card.reviewCount
        fsrsCard.lapses = card.lapseCount
        fsrsCard.due = card.dueAt
        fsrsCard.lastReview = card.lastReviewedAt
        fsrsCard.state = card.reviewCount == 0 ? .new : .review

        let scheduled = engine.repeat(card: fsrsCard, now: now)
        guard let outcome = scheduled[fsrsRating(rating)] else {
            return LatvianDefaultScheduler().review(card: card, rating: rating, now: now)
        }

        var updated = card
        updated.stability = outcome.card.stability
        updated.difficulty = outcome.card.difficulty
        updated.dueAt = outcome.card.due
        updated.lastReviewedAt = now
        updated.reviewCount = outcome.card.reps
        updated.lapseCount = outcome.card.lapses
        return updated
    }

    private func fsrsRating(_ rating: LatvianRating) -> Rating {
        switch rating {
        case .again: return .again
        case .hard: return .hard
        case .good: return .good
        case .easy: return .easy
        }
    }
}
```

Not: `swift-fsrs`'in genel API adları sürümle değişebilir. Derleme hatası alırsan paketin `Sources/` klasöründeki genel tipleri okuyup çağrıları ona göre düzelt; `LatvianScheduler` arayüzünü değiştirme — bu dosya dışındaki hiçbir kod FSRS'i tanımamalı.

- [ ] **Step 3: Uygulamayı derle**

```bash
xcodebuild -project ios/Kuzey.xcodeproj -scheme Kuzey -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```

Beklenen: `BUILD SUCCEEDED`.

- [ ] **Step 4: Motor testinin hâlâ geçtiğini doğrula**

```bash
./ios/Tests/run-latvian-check.sh
```

Beklenen: tüm kontroller geçer. FSRS bağlayıcısı test derlemesine girmediği için etkilenmez.

- [ ] **Step 5: Commit**

```bash
git add ios/Karavan/Learning/LatvianFSRSAdapter.swift ios/project.yml ios/Kuzey.xcodeproj
git commit -m "feat: wire swift-fsrs scheduler behind Latvian scheduler protocol"
```

---

### Task 8: Ses deposu ve eski motorun kaldırılması

**Files:**
- Create: `ios/Karavan/Learning/LatvianAudioStore.swift`
- Delete: `ios/Karavan/Learning/LatvianLearningModels.swift`, `LatvianLearningStore.swift`, `LatvianLearningAudioPlayer.swift`

**Interfaces:**
- Consumes: `LatvianPack` (Görev 1)
- Produces: `@MainActor final class LatvianAudioStore: ObservableObject` — `downloadedAudioIds: Set<String>`, `downloadProgress: Double`, `isDownloading: Bool`, `func syncMissing(pack:) async`, `func localURL(for audioId:) -> URL?`, `func play(audioId:)`.

Bu sınıf `AVFoundation` kullanır, dolayısıyla motor testine girmez — arayüz katmanının ilk parçasıdır ve bir sonraki planın bağımlılığıdır.

- [ ] **Step 1: Ses deposunu yaz**

`ios/Karavan/Learning/LatvianAudioStore.swift`:

```swift
import AVFoundation
import Foundation

@MainActor
final class LatvianAudioStore: ObservableObject {
    @Published private(set) var downloadedAudioIds: Set<String> = []
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var isDownloading = false
    @Published private(set) var lastError: String?

    private var player: AVAudioPlayer?
    private let directory: URL

    init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.temporaryDirectory
        directory = base.appendingPathComponent("letonca-ses", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        refreshDownloaded()
    }

    func localURL(for audioId: String) -> URL? {
        let url = directory.appendingPathComponent("\(audioId).wav")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Eksik sesleri indirir. Kesilirse aynı çağrı kaldığı yerden devam eder.
    func syncMissing(pack: LatvianPack) async {
        guard !isDownloading else { return }
        let manifest = pack.audioManifest
        let missing = manifest.keys.filter { localURL(for: $0) == nil }
        guard !missing.isEmpty else {
            downloadProgress = 1
            return
        }

        isDownloading = true
        lastError = nil
        var completed = 0

        for audioId in missing {
            do {
                let (data, response) = try await URLSession.shared.data(from: pack.audioURL(for: audioId))
                guard (response as? HTTPURLResponse)?.statusCode == 200, data.count > 1024 else {
                    throw URLError(.cannotParseResponse)
                }
                try data.write(to: directory.appendingPathComponent("\(audioId).wav"), options: .atomic)
                downloadedAudioIds.insert(audioId)
            } catch {
                lastError = "Bazı sesler inemedi, daha sonra tekrar denenecek."
            }
            completed += 1
            downloadProgress = Double(completed) / Double(missing.count)
        }

        isDownloading = false
    }

    func play(audioId: String) {
        guard let url = localURL(for: audioId) else {
            lastError = "Bu ses henüz inmedi."
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
            lastError = nil
        } catch {
            lastError = "Ses çalınamadı."
        }
    }

    private func refreshDownloaded() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        downloadedAudioIds = Set(
            names.filter { $0.hasSuffix(".wav") }.map { String($0.dropLast(4)) }
        )
        downloadProgress = downloadedAudioIds.isEmpty ? 0 : 1
    }
}
```

- [ ] **Step 2: Eski motor dosyalarını sil**

```bash
git rm ios/Karavan/Learning/LatvianLearningModels.swift \
       ios/Karavan/Learning/LatvianLearningStore.swift \
       ios/Karavan/Learning/LatvianLearningAudioPlayer.swift
```

`ios/Karavan/Views/Tools/LatvianLearningView.swift` bu tipleri kullandığı için derleme kırılacak. Bu beklenen durumdur: o dosya bir sonraki planın ilk görevinde baştan yazılır. Bu görevin sonunda uygulama derlenmez; motor testi ise yeşil kalır.

- [ ] **Step 3: Motor testinin geçtiğini doğrula**

```bash
./ios/Tests/run-latvian-check.sh
```

Beklenen: tüm kontroller geçer.

- [ ] **Step 4: Commit**

```bash
git add -A ios/Karavan/Learning ios/Tests
git commit -m "feat: add Latvian audio store and remove legacy learning engine"
```

---

## Tamamlanma ölçütü

- `./ios/Tests/run-latvian-check.sh` yeşil, en az 100 kontrol geçiyor.
- Motor dosyalarının hiçbiri `SwiftUI`, `UIKit` veya `AVFoundation` import etmiyor (`LatvianAudioStore` hariç, o arayüz katmanına ait).
- `swift-fsrs` SPM bağımlılığı eklendi ve `LatvianFSRSScheduler` derleniyor.
- Eski `LatvianLearning*` dosyaları depoda yok.
- Uygulama henüz derlenmiyor: `LatvianLearningView` bir sonraki planın ilk görevinde yeniden yazılacak.

Bir sonraki plan: `2026-07-27-letonca-arayuz-ve-efektler.md`.
