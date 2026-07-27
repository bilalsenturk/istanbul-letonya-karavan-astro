# Letonca Arayüz ve Efektler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Öğrenme motorunun üstüne Duolingo kalitesinde bir arayüz kurmak: rota haritası, ders akışı, on soru görünümü, cevap efektleri, kombo, maskot, ders sonu kutlaması ve bildirimler.

**Architecture:** Tek bir `LatvianLessonSession` görünüm modeli ders akışını yönetir (soru sırası, can, XP, kombo, yanlışın sona eklenmesi); her soru tipi kendi küçük `View` dosyasında durur ve yalnızca `LatvianExercise` + bir `onAnswer` geri çağrısı bilir. Efekt katmanı (haptic, ses, animasyon) ayrı bir `LatvianFeedback` nesnesinde toplanır, görünümler onu çağırır. Maskot saf SwiftUI şekilleriyle çizilir, durum makinesi bir `enum`.

**Tech Stack:** SwiftUI, AVFoundation, [ConfettiSwiftUI](https://github.com/simibac/ConfettiSwiftUI) (MIT), [lottie-ios](https://github.com/airbnb/lottie-ios) (Apache-2.0), `UNUserNotificationCenter`.

## Global Constraints

- Renkler yalnızca `Theme` üzerinden gelir: `Theme.bg`, `Theme.panel`, `Theme.line`, `Theme.text`, `Theme.dim`, `Theme.muted`, `Theme.ok`, `Theme.warn`, `Theme.bad`, `Theme.c1`-`c4`, `Theme.grad`, `Theme.gradWarm`, `Theme.gradCool`. Yeni ham renk tanımlanmaz.
- Kullanıcıya görünen tüm metinler Türkçe.
- Hiçbir görünüm dosyası 250 satırı geçmez. Geçiyorsa alt görünüme bölünür.
- Tüm animasyonlar `.spring(response:dampingFraction:)` ile; süre sabitleri `LatvianMotion` içinde tek yerde tanımlı.
- Ses efektleri Kenney.nl CC0 paketlerinden gelir; Duolingo sesleri kullanılmaz.
- Ders akışının saf mantığı (sıra, can, kombo, yanlışın sona eklenmesi) `LatvianLessonSession` içinde `SwiftUI` kullanmadan test edilebilir kalır ve `ios/Tests/run-latvian-check.sh` ile test edilir.
- Bildirimler `NotifKind`'a yeni bir `case` ekleyerek mevcut bütçe sistemine kaydolur; sessiz saat 23:00-08:00.
- Erişilebilirlik: her etkileşimli öğe `accessibilityLabel` taşır, animasyonlar `.accessibilityReduceMotion` açıkken sadeleşir.

---

## File Structure

**Oluşturulacak (`ios/Karavan/Learning/` altında):**

- `LatvianLessonSession.swift` — Ders akışının saf mantığı (test edilir).
- `LatvianFeedback.swift` — Haptic + ses efekti çalar.
- `LatvianNotifications.swift` — Bildirim planlama, saf karar fonksiyonlarıyla.

**Oluşturulacak (`ios/Karavan/Views/Latvian/` altında):**

- `LatvianHomeView.swift` — Rota haritası, üst çubuk, sahne durakları.
- `LatvianTopBar.swift` — Seri, can, XP, günlük hedef halkası.
- `LatvianRouteMap.swift` — İstanbul→Riga rotası üzerinde 12 durak.
- `LatvianLessonView.swift` — Ders kabuğu: ilerleme çubuğu, soru alanı, cevap paneli.
- `LatvianAnswerPanel.swift` — Alttan gelen doğru/yanlış paneli.
- `LatvianLessonCompleteView.swift` — Konfeti, sayaçlar, seri alevi.
- `LatvianMascot.swift` — SwiftUI ile çizilen maskot ve durum makinesi.
- `LatvianMotion.swift` — Animasyon sabitleri.
- `Exercises/LatvianChoiceExerciseView.swift` — `listenChoose`, `iconChoose`, `fillBlank`, `caseDrill`.
- `Exercises/LatvianWordBankExerciseView.swift` — `lvToTr`, `trToLv`, `order`.
- `Exercises/LatvianMatchExerciseView.swift` — `match`.
- `Exercises/LatvianTypingExerciseView.swift` — `dictation`.
- `Exercises/LatvianSpeakExerciseView.swift` — `speak`.

**Değiştirilecek:**

- `ios/Karavan/Views/Tools/LatvianLearningView.swift` — İçi boşaltılıp `LatvianHomeView`'a yönlendiren ince bir kabuğa dönüşür.
- `ios/Karavan/Notifications/NotificationRules.swift` — `NotifKind`'a Letonca kategorileri eklenir.

**Eklenecek varlıklar:**

- `ios/Karavan/Resources/Sounds/` — 8 CC0 ses dosyası.

---

### Task 1: Ders oturumu mantığı

Arayüzden önce akışın kendisi. Bu dosya `SwiftUI` import etmez ve testle doğrulanır.

**Files:**
- Create: `ios/Karavan/Learning/LatvianLessonSession.swift`
- Modify: `ios/Tests/latvian-engine-check.swift`, `ios/Tests/run-latvian-check.sh`

**Interfaces:**
- Consumes: `LatvianExercise`, `LatvianAnswer`, `LatvianGrade`, `LatvianGrader`, `LatvianRating` (önceki plan)
- Produces: `final class LatvianLessonSession`; `init(exercises:)`; `var current: LatvianExercise?`; `func submit(_ answer: LatvianAnswer, elapsed: TimeInterval, usedHint: Bool) -> LatvianSubmissionResult`; `func advance()`; `var isFinished: Bool`; `var isFailed: Bool`; `var progress: Double`; `var xpEarned: Int`; `var comboCount: Int`; `var accuracy: Double`; `struct LatvianSubmissionResult { grade, rating, heartsLeft, comboCount, xpGained, isComboMilestone }`.

Kurallar: yanlış cevaplanan soru dersin sonuna geri eklenir ve ders o soru doğru cevaplanmadan bitmez; can biterse ders başarısız olur; kombo 3/5/10'da kilometre taşı verir.

- [ ] **Step 1: Testi ekle**

`ios/Tests/latvian-engine-check.swift` içinde son `if failures > 0` bloğunun üstüne ekle:

```swift
print("\n=== Ders oturumu ===")

func choice(_ id: String, correct: Int = 0) -> LatvianExercise {
    LatvianExercise(
        id: id, kind: .listenChoose, targetWordId: "w-\(id)", prompt: "p",
        content: .choice(options: ["a", "b"], correctIndex: correct)
    )
}

let session = LatvianLessonSession(exercises: [choice("q1"), choice("q2"), choice("q3")])

expect(session.current?.id == "q1", "ilk soru sırada")
expect(session.progress == 0, "başlangıçta ilerleme sıfır")
expect(session.heartsLeft == 5, "beş canla başlıyor")

let correctResult = session.submit(.choice(index: 0), elapsed: 2, usedHint: false)
expect(correctResult.grade.isCorrect, "doğru cevap doğru notlanıyor")
expect(correctResult.rating == .easy, "hızlı doğru easy veriyor")
expect(correctResult.comboCount == 1, "kombo başlıyor")
expect(correctResult.xpGained == 10, "doğru cevap 10 XP veriyor")
expect(correctResult.heartsLeft == 5, "doğru cevapta can gitmiyor")

session.advance()
expect(session.current?.id == "q2", "sonraki soruya geçiliyor")

let wrongResult = session.submit(.choice(index: 1), elapsed: 3, usedHint: false)
expect(!wrongResult.grade.isCorrect, "yanlış cevap yanlış notlanıyor")
expect(wrongResult.rating == .again, "yanlış cevap again veriyor")
expect(wrongResult.heartsLeft == 4, "yanlış cevapta bir can gidiyor")
expect(wrongResult.comboCount == 0, "yanlış cevap komboyu sıfırlıyor")
expect(wrongResult.xpGained == 0, "yanlış cevap XP vermiyor")

session.advance()
expect(session.current?.id == "q3", "yanlış sorudan sonra sıradaki soruya geçiliyor")
expect(session.remainingCount == 2, "yanlış soru sona geri eklendi")

_ = session.submit(.choice(index: 0), elapsed: 2, usedHint: false)
session.advance()
expect(session.current?.id == "q2", "yanlış yapılan soru tekrar sorulıyor")
expect(!session.isFinished, "yanlış soru doğrulanmadan ders bitmiyor")

_ = session.submit(.choice(index: 0), elapsed: 2, usedHint: false)
session.advance()
expect(session.isFinished, "tüm sorular doğrulanınca ders bitiyor")
expect(session.current == nil, "ders bitince sıra boş")

// Kombo kilometre taşları
let comboSession = LatvianLessonSession(exercises: (1...12).map { choice("c\($0)") })
var milestones: [Int] = []
for _ in 1...12 {
    let outcome = comboSession.submit(.choice(index: 0), elapsed: 2, usedHint: false)
    if outcome.isComboMilestone { milestones.append(outcome.comboCount) }
    comboSession.advance()
}
expect(milestones == [3, 5, 10], "kombo 3, 5 ve 10'da kilometre taşı veriyor")
expect(comboSession.xpEarned > 120, "kombo bonusu XP'ye ekleniyor")
expect(comboSession.accuracy == 1, "hatasız derste doğruluk yüzde yüz")

// Can bitişi
let failing = LatvianLessonSession(exercises: (1...8).map { choice("f\($0)") })
for _ in 1...5 {
    _ = failing.submit(.choice(index: 1), elapsed: 2, usedHint: false)
    failing.advance()
}
expect(failing.isFailed, "beş yanlıştan sonra ders başarısız")
expect(failing.heartsLeft == 0, "canlar tükendi")
expect(!failing.isFinished, "başarısız ders tamamlanmış sayılmıyor")

// İlerleme
let progressSession = LatvianLessonSession(exercises: (1...4).map { choice("p\($0)") })
_ = progressSession.submit(.choice(index: 0), elapsed: 2, usedHint: false)
progressSession.advance()
expect(abs(progressSession.progress - 0.25) < 0.001, "ilerleme tamamlanan soru oranı")
```

- [ ] **Step 2: Test betiğine dosyayı ekle**

`ios/Tests/run-latvian-check.sh` içindeki `swiftc` çağrısına satır ekle:

```bash
  "$SRC/LatvianLessonSession.swift" \
```

- [ ] **Step 3: Testi çalıştırıp başarısız olduğunu gör**

```bash
./ios/Tests/run-latvian-check.sh
```

Beklenen: `error: cannot find 'LatvianLessonSession' in scope`.

- [ ] **Step 4: Oturumu yaz**

`ios/Karavan/Learning/LatvianLessonSession.swift`:

```swift
import Foundation

struct LatvianSubmissionResult: Sendable {
    let grade: LatvianGrade
    let rating: LatvianRating
    let heartsLeft: Int
    let comboCount: Int
    let xpGained: Int
    let isComboMilestone: Bool
}

/// Bir dersin akışını yönetir: soru sırası, can, kombo, XP.
/// `SwiftUI` bilmez; arayüz bunu gözlemler.
final class LatvianLessonSession {
    static let maxHearts = 5
    static let baseXP = 10
    static let comboBonusXP = 5
    static let comboMilestones: Set<Int> = [3, 5, 10]

    private var queue: [LatvianExercise]
    private var attemptsByExerciseId: [String: Int] = [:]
    private let totalPlanned: Int

    private(set) var heartsLeft = maxHearts
    private(set) var comboCount = 0
    private(set) var xpEarned = 0
    private(set) var correctCount = 0
    private(set) var answerCount = 0
    private(set) var completedIds: Set<String> = []
    private(set) var lastResult: LatvianSubmissionResult?

    init(exercises: [LatvianExercise]) {
        queue = exercises
        totalPlanned = exercises.count
    }

    var current: LatvianExercise? { queue.first }
    var remainingCount: Int { queue.count }
    var isFailed: Bool { heartsLeft == 0 }
    var isFinished: Bool { queue.isEmpty && !isFailed }

    var progress: Double {
        guard totalPlanned > 0 else { return 1 }
        return Double(completedIds.count) / Double(totalPlanned)
    }

    var accuracy: Double {
        guard answerCount > 0 else { return 0 }
        return Double(correctCount) / Double(answerCount)
    }

    /// Cevabı notlar, can ve komboyu günceller. Sıra ilerlemez — bunun için `advance()` çağrılır.
    /// Böylece arayüz cevap panelini gösterirken soru ekranda kalır.
    @discardableResult
    func submit(_ answer: LatvianAnswer, elapsed: TimeInterval, usedHint: Bool) -> LatvianSubmissionResult {
        guard let exercise = queue.first else {
            let empty = LatvianSubmissionResult(
                grade: LatvianGrade(isCorrect: false, correctAnswer: ""),
                rating: .again, heartsLeft: heartsLeft, comboCount: comboCount,
                xpGained: 0, isComboMilestone: false
            )
            lastResult = empty
            return empty
        }

        let attempts = (attemptsByExerciseId[exercise.id] ?? 0) + 1
        attemptsByExerciseId[exercise.id] = attempts

        let grade = LatvianGrader.grade(exercise: exercise, answer: answer)
        let rating = LatvianRating.from(
            isCorrect: grade.isCorrect, attempts: attempts, usedHint: usedHint, elapsed: elapsed
        )

        answerCount += 1
        var xpGained = 0
        var isMilestone = false

        if grade.isCorrect {
            correctCount += 1
            comboCount += 1
            xpGained = Self.baseXP
            if Self.comboMilestones.contains(comboCount) {
                xpGained += Self.comboBonusXP
                isMilestone = true
            }
            xpEarned += xpGained
        } else {
            comboCount = 0
            heartsLeft = max(0, heartsLeft - 1)
        }

        let result = LatvianSubmissionResult(
            grade: grade, rating: rating, heartsLeft: heartsLeft,
            comboCount: comboCount, xpGained: xpGained, isComboMilestone: isMilestone
        )
        lastResult = result
        return result
    }

    /// Cevap paneli kapandığında çağrılır. Doğruysa soru düşer, yanlışsa sona geri gider.
    func advance() {
        guard !queue.isEmpty, let result = lastResult else { return }
        let exercise = queue.removeFirst()
        if result.grade.isCorrect {
            completedIds.insert(exercise.id)
        } else if !isFailed {
            queue.append(exercise)
        }
        lastResult = nil
    }
}
```

- [ ] **Step 5: Testi çalıştır**

```bash
./ios/Tests/run-latvian-check.sh
```

Beklenen: `=== Ders oturumu ===` altında yirmi altı `✓`, çıkış kodu 0.

- [ ] **Step 6: Commit**

```bash
git add ios/Karavan/Learning/LatvianLessonSession.swift ios/Tests/
git commit -m "feat: add Latvian lesson session flow with hearts and combo"
```

---

### Task 2: Hareket sabitleri, geri bildirim ve maskot

**Files:**
- Create: `ios/Karavan/Views/Latvian/LatvianMotion.swift`
- Create: `ios/Karavan/Learning/LatvianFeedback.swift`
- Create: `ios/Karavan/Views/Latvian/LatvianMascot.swift`
- Create: `ios/Karavan/Resources/Sounds/` (8 ses dosyası)

**Interfaces:**
- Consumes: yok
- Produces: `enum LatvianMotion` (`snap`, `pop`, `slide`, `shakeOffsets`); `@MainActor final class LatvianFeedback` (`correct()`, `wrong()`, `combo()`, `heartLost()`, `lessonComplete()`, `streakUp()`, `tap()`, `xpTick()`, `var soundsEnabled: Bool`); `enum LatvianMascotMood { idle, thinking, correct, wrong, celebrate }`; `struct LatvianMascot: View`.

- [ ] **Step 1: Ses efektlerini üret**

Sesler indirilmiyor, üretiliyor. Arayüz efektleri kısa sentezlenmiş tonlardır; kendimiz üretmek lisans sorununu tamamen kaldırır, dosyaları birkaç KB'de tutar ve tonları uygulamanın hissine göre ayarlamamızı sağlar.

`tools/generate-ui-sounds.mjs` dosyasını oluştur:

```javascript
#!/usr/bin/env node
// Letonca kursunun 8 arayüz sesini üretir. Girdi yok, ağ yok.
//
//   node tools/generate-ui-sounds.mjs
//
// Çıktı: ios/Karavan/Resources/Sounds/lv-*.wav (mono, 44.1 kHz, 16-bit)

import fs from 'node:fs/promises';
import path from 'node:path';

const SAMPLE_RATE = 44_100;
const OUT_DIR = path.join(process.cwd(), 'ios/Karavan/Resources/Sounds');

/** Bir nota: frekans (Hz), başlangıç (s), süre (s), yükseklik, dalga biçimi. */
const SOUNDS = {
  // Yükselen iki nota — onay.
  'lv-correct': [
    { freq: 784, start: 0, duration: 0.09, gain: 0.5, wave: 'triangle' },
    { freq: 1175, start: 0.07, duration: 0.16, gain: 0.5, wave: 'triangle' },
  ],
  // Alçalan boğuk ikili — hata. Sert değil, cezalandırıcı değil.
  'lv-wrong': [
    { freq: 220, start: 0, duration: 0.14, gain: 0.45, wave: 'square' },
    { freq: 165, start: 0.1, duration: 0.2, gain: 0.4, wave: 'square' },
  ],
  // Dört notalı yükselen arpej — ders bitişi.
  'lv-complete': [
    { freq: 523, start: 0, duration: 0.12, gain: 0.42, wave: 'triangle' },
    { freq: 659, start: 0.09, duration: 0.12, gain: 0.42, wave: 'triangle' },
    { freq: 784, start: 0.18, duration: 0.12, gain: 0.42, wave: 'triangle' },
    { freq: 1047, start: 0.27, duration: 0.34, gain: 0.5, wave: 'triangle' },
  ],
  // Çok kısa tık — XP sayacı.
  'lv-xp': [{ freq: 1568, start: 0, duration: 0.045, gain: 0.3, wave: 'sine' }],
  // Kalp kaybı: hızlı düşen kayma.
  'lv-heart': [
    { freq: 440, start: 0, duration: 0.06, gain: 0.4, wave: 'sine' },
    { freq: 294, start: 0.05, duration: 0.13, gain: 0.36, wave: 'sine' },
  ],
  // Seri uzadı: parlak, yükselen üçlü.
  'lv-streak': [
    { freq: 659, start: 0, duration: 0.08, gain: 0.4, wave: 'triangle' },
    { freq: 880, start: 0.07, duration: 0.08, gain: 0.4, wave: 'triangle' },
    { freq: 1319, start: 0.14, duration: 0.26, gain: 0.46, wave: 'triangle' },
  ],
  // Dokunuş: neredeyse duyulmayan tık.
  'lv-tap': [{ freq: 1046, start: 0, duration: 0.028, gain: 0.18, wave: 'sine' }],
  // Kombo: iki hızlı yüksek nota.
  'lv-combo': [
    { freq: 1047, start: 0, duration: 0.06, gain: 0.4, wave: 'triangle' },
    { freq: 1568, start: 0.055, duration: 0.14, gain: 0.44, wave: 'triangle' },
  ],
};

await fs.mkdir(OUT_DIR, { recursive: true });

for (const [name, notes] of Object.entries(SOUNDS)) {
  const samples = render(notes);
  const file = path.join(OUT_DIR, `${name}.wav`);
  await fs.writeFile(file, encodeWav(samples));
  const ms = Math.round((samples.length / SAMPLE_RATE) * 1000);
  console.log(`✓ ${name}.wav — ${ms} ms, ${Math.round(encodeWav(samples).length / 1024)} KB`);
}

console.log(`\n${Object.keys(SOUNDS).length} ses üretildi: ${path.relative(process.cwd(), OUT_DIR)}`);

function render(notes) {
  const totalSeconds = Math.max(...notes.map(note => note.start + note.duration)) + 0.02;
  const samples = new Float32Array(Math.ceil(totalSeconds * SAMPLE_RATE));

  for (const note of notes) {
    const startSample = Math.floor(note.start * SAMPLE_RATE);
    const length = Math.floor(note.duration * SAMPLE_RATE);
    for (let index = 0; index < length; index += 1) {
      const position = index / length;
      const time = index / SAMPLE_RATE;
      samples[startSample + index] += oscillator(note.wave, note.freq, time)
        * note.gain
        * envelope(position);
    }
  }

  // Kırpılmayı önlemek için tepe değerine göre normalize et.
  let peak = 0;
  for (const value of samples) peak = Math.max(peak, Math.abs(value));
  if (peak > 0.92) {
    const scale = 0.92 / peak;
    for (let index = 0; index < samples.length; index += 1) samples[index] *= scale;
  }
  return samples;
}

function oscillator(wave, freq, time) {
  const phase = 2 * Math.PI * freq * time;
  switch (wave) {
    case 'square':
      return Math.sin(phase) >= 0 ? 0.6 : -0.6;
    case 'triangle':
      return (2 / Math.PI) * Math.asin(Math.sin(phase));
    default:
      return Math.sin(phase);
  }
}

/** Hızlı atak, üstel sönüm — arayüz sesleri için doğru zarf. */
function envelope(position) {
  const attack = 0.02;
  if (position < attack) return position / attack;
  return Math.exp(-4.2 * ((position - attack) / (1 - attack)));
}

function encodeWav(samples) {
  const buffer = Buffer.alloc(44 + samples.length * 2);
  buffer.write('RIFF', 0, 'ascii');
  buffer.writeUInt32LE(36 + samples.length * 2, 4);
  buffer.write('WAVE', 8, 'ascii');
  buffer.write('fmt ', 12, 'ascii');
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20);
  buffer.writeUInt16LE(1, 22);
  buffer.writeUInt32LE(SAMPLE_RATE, 24);
  buffer.writeUInt32LE(SAMPLE_RATE * 2, 28);
  buffer.writeUInt16LE(2, 32);
  buffer.writeUInt16LE(16, 34);
  buffer.write('data', 36, 'ascii');
  buffer.writeUInt32LE(samples.length * 2, 40);

  for (let index = 0; index < samples.length; index += 1) {
    const clamped = Math.max(-1, Math.min(1, samples[index]));
    buffer.writeInt16LE(Math.round(clamped * 32_767), 44 + index * 2);
  }
  return buffer;
}
```

`package.json` `scripts` bölümüne ekle:

```json
    "generate:sounds": "node tools/generate-ui-sounds.mjs",
```

Çalıştır:

```bash
npm run generate:sounds && ls -la ios/Karavan/Resources/Sounds/
```

Beklenen: sekiz `✓` satırı ve sekiz `.wav` dosyası. Her biri 4-60 KB arası.

Sesleri dinleyerek doğrula:

```bash
for f in ios/Karavan/Resources/Sounds/*.wav; do echo "$f"; afplay "$f"; done
```

`lv-correct` yukarı doğru neşeli, `lv-wrong` aşağı doğru boğuk ama sert değil, `lv-tap` neredeyse duyulmaz olmalı. Değilse `SOUNDS` tablosundaki frekans ve `gain` değerlerini ayarlayıp tekrar üret.

Ses dosyaları `Karavan/` altında olduğu için `ios/project.yml`'deki `sources: - path: Karavan` kuralıyla otomatik paketlenir; ayrıca bir kaynak tanımı gerekmez.

- [ ] **Step 2: Hareket sabitlerini yaz**

`ios/Karavan/Views/Latvian/LatvianMotion.swift`:

```swift
import SwiftUI

enum LatvianMotion {
    /// Kart seçimi, buton basımı.
    static let snap = Animation.spring(response: 0.3, dampingFraction: 0.6)
    /// Doğru cevapta büyüyüp yerine oturma.
    static let pop = Animation.spring(response: 0.35, dampingFraction: 0.55)
    /// Alttan gelen panel.
    static let slide = Animation.spring(response: 0.4, dampingFraction: 0.8)
    /// Sayaçların sayması.
    static let count = Animation.easeOut(duration: 0.9)

    /// Yanlış cevapta yatay sarsılma karesi.
    static let shakeOffsets: [CGFloat] = [0, -10, 9, -6, 3, 0]
    static let shakeStep: TimeInterval = 0.055
}

/// Yanlış cevapta kartı yatay sarsan değiştirici.
struct LatvianShake: ViewModifier {
    let trigger: Int
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .onChange(of: trigger) { _, _ in
                guard !UIAccessibility.isReduceMotionEnabled else { return }
                for (index, value) in LatvianMotion.shakeOffsets.enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * LatvianMotion.shakeStep) {
                        withAnimation(.linear(duration: LatvianMotion.shakeStep)) { offset = value }
                    }
                }
            }
    }
}

extension View {
    func latvianShake(trigger: Int) -> some View {
        modifier(LatvianShake(trigger: trigger))
    }
}
```

- [ ] **Step 3: Geri bildirim katmanını yaz**

`ios/Karavan/Learning/LatvianFeedback.swift`:

```swift
import AVFoundation
import Foundation
import UIKit

/// Haptic ve ses efektlerini tek yerde toplar. Görünümler doğrudan `AVAudioPlayer` kullanmaz.
@MainActor
final class LatvianFeedback: ObservableObject {
    @AppStorage("letonca.soundsEnabled") var soundsEnabled = true

    private var players: [String: AVAudioPlayer] = [:]
    private let notification = UINotificationFeedbackGenerator()
    private let impact = UIImpactFeedbackGenerator(style: .light)

    func correct() {
        notification.notificationOccurred(.success)
        play("lv-correct")
    }

    func wrong() {
        notification.notificationOccurred(.error)
        play("lv-wrong")
    }

    func combo() {
        impact.impactOccurred(intensity: 0.8)
        play("lv-combo")
    }

    func heartLost() {
        impact.impactOccurred(intensity: 1.0)
        play("lv-heart")
    }

    func lessonComplete() {
        notification.notificationOccurred(.success)
        play("lv-complete")
    }

    func streakUp() { play("lv-streak") }
    func xpTick() { play("lv-xp") }

    func tap() {
        impact.impactOccurred(intensity: 0.4)
        play("lv-tap")
    }

    private func play(_ name: String) {
        guard soundsEnabled else { return }
        if players[name] == nil {
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return }
            players[name] = try? AVAudioPlayer(contentsOf: url)
            players[name]?.prepareToPlay()
        }
        players[name]?.currentTime = 0
        players[name]?.play()
    }
}
```

- [ ] **Step 4: Maskotu yaz**

`ios/Karavan/Views/Latvian/LatvianMascot.swift`:

```swift
import SwiftUI

enum LatvianMascotMood: Equatable {
    case idle
    case thinking
    case correct
    case wrong
    case celebrate
}

/// Kuzey'in yol arkadaşı: SwiftUI şekilleriyle çizilen özgün maskot.
/// Harici varlık veya paralı editör gerektirmez.
struct LatvianMascot: View {
    let mood: LatvianMascotMood
    var size: CGFloat = 88

    @State private var breathing = false
    @State private var blinking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            body_
            ears
            face
        }
        .frame(width: size, height: size)
        .scaleEffect(scale)
        .rotationEffect(.degrees(tilt))
        .offset(y: bounce)
        .animation(LatvianMotion.pop, value: mood)
        .onAppear(perform: startIdleLoop)
        .accessibilityLabel(accessibilityText)
    }

    private var body_: some View {
        Capsule(style: .continuous)
            .fill(Theme.gradWarm)
            .frame(width: size * 0.72, height: size * 0.8)
            .overlay(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .frame(width: size * 0.42, height: size * 0.46)
                    .offset(y: size * 0.12)
            )
    }

    private var ears: some View {
        HStack(spacing: size * 0.34) {
            ear.rotationEffect(.degrees(earAngle))
            ear.rotationEffect(.degrees(-earAngle))
        }
        .offset(y: -size * 0.38)
    }

    private var ear: some View {
        Capsule(style: .continuous)
            .fill(Theme.c1)
            .frame(width: size * 0.14, height: size * 0.3)
    }

    private var face: some View {
        VStack(spacing: size * 0.06) {
            HStack(spacing: size * 0.16) {
                eye
                eye
            }
            mouth
        }
        .offset(y: -size * 0.02)
    }

    private var eye: some View {
        Group {
            if mood == .correct || mood == .celebrate {
                // Gülen göz: ters çevrilmiş yay.
                Arc()
                    .stroke(Theme.bg, style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round))
                    .frame(width: size * 0.14, height: size * 0.09)
            } else {
                Capsule()
                    .fill(Theme.bg)
                    .frame(width: size * 0.09, height: blinking ? size * 0.02 : size * 0.13)
            }
        }
    }

    private var mouth: some View {
        Group {
            switch mood {
            case .correct, .celebrate:
                Arc()
                    .stroke(Theme.bg, style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round))
                    .frame(width: size * 0.24, height: size * 0.12)
            case .wrong:
                Arc()
                    .stroke(Theme.bg, style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round))
                    .frame(width: size * 0.2, height: size * 0.1)
                    .rotationEffect(.degrees(180))
            case .thinking, .idle:
                Capsule()
                    .fill(Theme.bg)
                    .frame(width: size * 0.14, height: size * 0.035)
            }
        }
    }

    // MARK: - Duruma bağlı dönüşümler

    private var scale: CGFloat {
        switch mood {
        case .celebrate: return 1.12
        case .correct: return 1.06
        case .wrong: return 0.96
        case .thinking, .idle: return breathing ? 1.02 : 1.0
        }
    }

    private var tilt: Double {
        switch mood {
        case .thinking: return -8
        case .wrong: return 6
        default: return 0
        }
    }

    private var bounce: CGFloat {
        switch mood {
        case .correct: return -size * 0.08
        case .celebrate: return -size * 0.14
        default: return 0
        }
    }

    private var earAngle: Double {
        switch mood {
        case .wrong: return 34
        case .celebrate: return -14
        default: return 12
        }
    }

    private var accessibilityText: String {
        switch mood {
        case .idle: return "Yol arkadaşın bekliyor"
        case .thinking: return "Yol arkadaşın seni izliyor"
        case .correct: return "Yol arkadaşın seviniyor"
        case .wrong: return "Yol arkadaşın üzgün"
        case .celebrate: return "Yol arkadaşın kutluyor"
        }
    }

    private func startIdleLoop() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
            breathing = true
        }
        Timer.scheduledTimer(withTimeInterval: 4.2, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.linear(duration: 0.09)) { blinking = true }
                try? await Task.sleep(nanoseconds: 110_000_000)
                withAnimation(.linear(duration: 0.09)) { blinking = false }
            }
        }
    }
}

/// Yukarı bakan yay — gülen göz ve ağız için.
private struct Arc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height)
        )
        return path
    }
}

#Preview {
    VStack(spacing: 28) {
        ForEach([LatvianMascotMood.idle, .thinking, .correct, .wrong, .celebrate], id: \.self) { mood in
            LatvianMascot(mood: mood)
        }
    }
    .padding(40)
    .background(Theme.bg)
}
```

- [ ] **Step 5: Maskotu önizlemede gör**

Xcode'da `LatvianMascot.swift` dosyasını aç, Canvas'ı çalıştır. Beş durumun da göründüğünü ve `idle` durumunda nefes alma/göz kırpma olduğunu doğrula.

Beğenmezsen bu adımda şekilleri değiştir — sonraki görevler maskotun görünümüne değil, yalnızca `LatvianMascotMood` arayüzüne bağlı.

- [ ] **Step 6: Commit**

```bash
git add ios/Karavan/Views/Latvian/LatvianMotion.swift ios/Karavan/Views/Latvian/LatvianMascot.swift ios/Karavan/Learning/LatvianFeedback.swift ios/Karavan/Resources/Sounds tools/generate-ui-sounds.mjs package.json
git commit -m "feat: add Latvian motion constants, feedback layer, and SwiftUI mascot"
```

---

### Task 3: Soru görünümleri

**Files:**
- Create: `ios/Karavan/Views/Latvian/Exercises/LatvianChoiceExerciseView.swift`
- Create: `ios/Karavan/Views/Latvian/Exercises/LatvianWordBankExerciseView.swift`
- Create: `ios/Karavan/Views/Latvian/Exercises/LatvianMatchExerciseView.swift`
- Create: `ios/Karavan/Views/Latvian/Exercises/LatvianTypingExerciseView.swift`
- Create: `ios/Karavan/Views/Latvian/Exercises/LatvianSpeakExerciseView.swift`

**Interfaces:**
- Consumes: `LatvianExercise`, `LatvianAnswer`, `LatvianAudioStore`, `LatvianFeedback`
- Produces: Beş görünüm. Hepsi aynı sözleşmeyi taşır: `init(exercise:audio:feedback:isLocked:onAnswerReady:)` — `onAnswerReady: (LatvianAnswer?) -> Void`, kullanıcı cevabı değiştirdikçe çağrılır; `nil` "henüz gönderilemez" demektir. Gönderme butonu ders kabuğunda.

`isLocked` cevap panelinin açık olduğu andır: görünüm etkileşimi keser ve doğru/yanlış rengini gösterir.

- [ ] **Step 1: Seçmeli görünümü yaz**

`ios/Karavan/Views/Latvian/Exercises/LatvianChoiceExerciseView.swift`:

```swift
import SwiftUI

/// listenChoose, iconChoose, fillBlank ve caseDrill için ortak seçmeli görünüm.
struct LatvianChoiceExerciseView: View {
    let exercise: LatvianExercise
    @ObservedObject var audio: LatvianAudioStore
    @ObservedObject var feedback: LatvianFeedback
    let isLocked: Bool
    let onAnswerReady: (LatvianAnswer?) -> Void

    @State private var selected: Int?
    @State private var shakeTrigger = 0

    private var options: [String] {
        if case .choice(let values, _) = exercise.content { return values }
        return []
    }

    private var correctIndex: Int {
        if case .choice(_, let index) = exercise.content { return index }
        return -1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(exercise.prompt)
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)

            if let audioId = exercise.audioId {
                audioButton(audioId)
            }

            if let carrier = exercise.carrier {
                Text(carrier)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 22)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            VStack(spacing: 11) {
                ForEach(options.indices, id: \.self) { index in
                    optionCard(index)
                }
            }
        }
        .latvianShake(trigger: shakeTrigger)
        .onChange(of: isLocked) { _, locked in
            if locked, selected != correctIndex { shakeTrigger += 1 }
        }
    }

    private func audioButton(_ audioId: String) -> some View {
        Button {
            feedback.tap()
            audio.play(audioId: audioId)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 19, weight: .bold))
                Text("Dinle")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.gradCool, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sesi dinle")
    }

    private func optionCard(_ index: Int) -> some View {
        Button {
            feedback.tap()
            selected = index
            onAnswerReady(.choice(index: index))
        } label: {
            HStack {
                Text(options[index])
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 17)
            .background(background(index), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(border(index), lineWidth: 2)
            )
            .scaleEffect(selected == index ? 1.03 : 1)
            .animation(LatvianMotion.snap, value: selected)
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .accessibilityLabel(options[index])
    }

    private func background(_ index: Int) -> Color {
        guard isLocked else { return selected == index ? Theme.c3.opacity(0.28) : Theme.panel }
        if index == correctIndex { return Theme.ok.opacity(0.24) }
        if index == selected { return Theme.bad.opacity(0.24) }
        return Theme.panel
    }

    private func border(_ index: Int) -> Color {
        guard isLocked else { return selected == index ? Theme.c3 : Theme.line }
        if index == correctIndex { return Theme.ok }
        if index == selected { return Theme.bad }
        return Theme.line
    }
}
```

- [ ] **Step 2: Kelime bankası görünümünü yaz**

`ios/Karavan/Views/Latvian/Exercises/LatvianWordBankExerciseView.swift`:

```swift
import SwiftUI

/// lvToTr, trToLv ve order için kelime bankası görünümü.
struct LatvianWordBankExerciseView: View {
    let exercise: LatvianExercise
    @ObservedObject var feedback: LatvianFeedback
    let isLocked: Bool
    let onAnswerReady: (LatvianAnswer?) -> Void

    @State private var chosen: [String] = []
    @State private var bank: [String] = []

    private var answer: [String] {
        if case .wordBank(_, let expected) = exercise.content { return expected }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(exercise.prompt)
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)

            if let carrier = exercise.carrier {
                Text(carrier)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.dim)
            }

            answerTray
            bankTray
        }
        .onAppear {
            if case .wordBank(let values, _) = exercise.content, bank.isEmpty { bank = values }
        }
    }

    private var answerTray: some View {
        LatvianChipFlow(items: chosen) { word, index in
            chip(word, tone: Theme.c3) {
                guard !isLocked else { return }
                feedback.tap()
                chosen.remove(at: index)
                bank.append(word)
                publish()
            }
        }
        .frame(minHeight: 68, alignment: .topLeading)
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isLocked ? trayBorder : Theme.line, lineWidth: 2)
        )
    }

    private var bankTray: some View {
        LatvianChipFlow(items: bank) { word, index in
            chip(word, tone: Theme.panel) {
                guard !isLocked else { return }
                feedback.tap()
                bank.remove(at: index)
                chosen.append(word)
                publish()
            }
        }
    }

    private var trayBorder: Color {
        chosen == answer ? Theme.ok : Theme.bad
    }

    private func chip(_ word: String, tone: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(word)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(tone, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(word)
    }

    private func publish() {
        withAnimation(LatvianMotion.snap) {}
        onAnswerReady(chosen.isEmpty ? nil : .words(chosen))
    }
}

/// Sarmalayan yatay yerleşim. `LazyVGrid` değişken genişlikli parçaları hizalayamadığı için elle yazıldı.
struct LatvianChipFlow<Content: View>: View {
    let items: [String]
    @ViewBuilder let content: (String, Int) -> Content

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items.indices, id: \.self) { index in
                content(items[index], index)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > width, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: totalHeight + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
```

- [ ] **Step 3: Eşleştirme görünümünü yaz**

`ios/Karavan/Views/Latvian/Exercises/LatvianMatchExerciseView.swift`:

```swift
import SwiftUI

struct LatvianMatchExerciseView: View {
    let exercise: LatvianExercise
    @ObservedObject var feedback: LatvianFeedback
    let isLocked: Bool
    let onAnswerReady: (LatvianAnswer?) -> Void

    @State private var selectedLv: String?
    @State private var matched: [LatvianMatchPair] = []
    @State private var lvColumn: [String] = []
    @State private var trColumn: [String] = []

    private var pairs: [LatvianMatchPair] {
        if case .matching(let values) = exercise.content { return values }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(exercise.prompt)
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)

            HStack(alignment: .top, spacing: 12) {
                column(lvColumn, isLeft: true)
                column(trColumn, isLeft: false)
            }
        }
        .onAppear {
            guard lvColumn.isEmpty else { return }
            lvColumn = pairs.map(\.lv).shuffled()
            trColumn = pairs.map(\.tr).shuffled()
        }
    }

    private func column(_ values: [String], isLeft: Bool) -> some View {
        VStack(spacing: 10) {
            ForEach(values, id: \.self) { value in
                Button {
                    guard !isLocked, !isMatched(value, isLeft: isLeft) else { return }
                    feedback.tap()
                    if isLeft {
                        selectedLv = value
                    } else if let lv = selectedLv {
                        matched.append(LatvianMatchPair(lv: lv, tr: value))
                        selectedLv = nil
                        onAnswerReady(matched.count == pairs.count ? .pairs(matched) : nil)
                    }
                } label: {
                    Text(value)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(tone(value, isLeft: isLeft), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(selectedLv == value ? Theme.c3 : Theme.line, lineWidth: 2)
                        )
                        .opacity(isMatched(value, isLeft: isLeft) ? 0.4 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(value)
            }
        }
    }

    private func isMatched(_ value: String, isLeft: Bool) -> Bool {
        matched.contains { isLeft ? $0.lv == value : $0.tr == value }
    }

    private func tone(_ value: String, isLeft: Bool) -> Color {
        guard isLocked, isMatched(value, isLeft: isLeft) else { return Theme.panel }
        let isRight = matched.contains { entry in
            pairs.contains { $0.lv == entry.lv && $0.tr == entry.tr }
                && (isLeft ? entry.lv == value : entry.tr == value)
        }
        return isRight ? Theme.ok.opacity(0.2) : Theme.bad.opacity(0.2)
    }
}
```

- [ ] **Step 4: Yazma ve telaffuz görünümlerini yaz**

`ios/Karavan/Views/Latvian/Exercises/LatvianTypingExerciseView.swift`:

```swift
import SwiftUI

struct LatvianTypingExerciseView: View {
    let exercise: LatvianExercise
    @ObservedObject var audio: LatvianAudioStore
    @ObservedObject var feedback: LatvianFeedback
    let isLocked: Bool
    let onAnswerReady: (LatvianAnswer?) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(exercise.prompt)
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)

            if let audioId = exercise.audioId {
                Button {
                    feedback.tap()
                    audio.play(audioId: audioId)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 19, weight: .bold))
                        Text("Tekrar dinle")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Theme.gradCool, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sesi tekrar dinle")
            }

            TextField("Letonca yaz", text: $text)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
                .disabled(isLocked)
                .padding(16)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isFocused ? Theme.c3 : Theme.line, lineWidth: 2)
                )
                .onChange(of: text) { _, value in
                    onAnswerReady(value.trimmingCharacters(in: .whitespaces).isEmpty ? nil : .text(value))
                }
        }
        .onAppear { isFocused = true }
    }
}
```

`ios/Karavan/Views/Latvian/Exercises/LatvianSpeakExerciseView.swift`:

```swift
import Speech
import SwiftUI

struct LatvianSpeakExerciseView: View {
    let exercise: LatvianExercise
    @ObservedObject var audio: LatvianAudioStore
    @ObservedObject var feedback: LatvianFeedback
    let isLocked: Bool
    let onAnswerReady: (LatvianAnswer?) -> Void

    @StateObject private var recognizer = LatvianSpeechRecognizer()

    private var target: String {
        if case .speaking(let value) = exercise.content { return value }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(exercise.prompt)
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)

            Text(target)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if let audioId = exercise.audioId {
                Button {
                    feedback.tap()
                    audio.play(audioId: audioId)
                } label: {
                    Label("Örneği dinle", systemImage: "speaker.wave.2.fill")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.gradCool, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button {
                feedback.tap()
                if recognizer.isRecording {
                    recognizer.stop()
                } else {
                    recognizer.start(onResult: { transcript in
                        onAnswerReady(.spoken(transcript: transcript))
                    })
                }
            } label: {
                Label(recognizer.isRecording ? "Dinliyorum…" : "Konuş", systemImage: "mic.fill")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(
                        recognizer.isRecording ? AnyShapeStyle(Theme.bad) : AnyShapeStyle(Theme.gradWarm),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isLocked || !recognizer.isAvailable)

            if !recognizer.isAvailable {
                Text("Konuşma tanıma kullanılamıyor. Bu soruyu geçebilirsin.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

@MainActor
final class LatvianSpeechRecognizer: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isAvailable = SFSpeechRecognizer(locale: Locale(identifier: "lv-LV"))?.isAvailable ?? false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "lv-LV"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start(onResult: @escaping (String) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard status == .authorized, let self, let recognizer = self.recognizer else {
                    self?.isAvailable = false
                    return
                }
                let request = SFSpeechAudioBufferRecognitionRequest()
                request.shouldReportPartialResults = true
                self.request = request

                let input = self.engine.inputNode
                input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                    request.append(buffer)
                }
                self.engine.prepare()
                try? self.engine.start()
                self.isRecording = true

                self.task = recognizer.recognitionTask(with: request) { result, _ in
                    if let text = result?.bestTranscription.formattedString {
                        Task { @MainActor in onResult(text) }
                    }
                }
            }
        }
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        isRecording = false
    }
}
```

- [ ] **Step 5: Mikrofon ve konuşma tanıma izinlerini doğrula**

`NSSpeechRecognitionUsageDescription` ve `NSMicrophoneUsageDescription` `ios/project.yml` içinde zaten tanımlı (sesli harcama özelliği için). Doğrula:

```bash
grep -n "NSSpeechRecognitionUsageDescription\|NSMicrophoneUsageDescription" ios/project.yml
```

Beklenen: iki satır da bulunur. Bulunmuyorsa `Support/Info.plist` altındaki `properties:` bloğuna ekle ve `cd ios && xcodegen` çalıştır. Metinler mevcut haliyle telaffuz alıştırmasını da kapsıyor; değiştirme.

- [ ] **Step 6: Derle**

```bash
xcodebuild -project ios/Kuzey.xcodeproj -scheme Kuzey -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```

`LatvianLearningView.swift` hâlâ eski tipleri kullandığı için hata verecek; yalnızca `Views/Latvian/Exercises/` altındaki dosyalarda hata olmadığını doğrula. O dosya Görev 5'te yeniden yazılıyor.

- [ ] **Step 7: Commit**

```bash
git add ios/Karavan/Views/Latvian/Exercises
git commit -m "feat: add five Latvian exercise views"
```

---

### Task 4: Ders kabuğu, cevap paneli ve ders sonu

**Files:**
- Create: `ios/Karavan/Views/Latvian/LatvianLessonView.swift`
- Create: `ios/Karavan/Views/Latvian/LatvianAnswerPanel.swift`
- Create: `ios/Karavan/Views/Latvian/LatvianLessonCompleteView.swift`
- Modify: `ios/Kuzey.xcodeproj` (SPM bağımlılıkları)

**Interfaces:**
- Consumes: `LatvianLessonSession`, `LatvianExercise`, Görev 2-3'teki her şey
- Produces: `struct LatvianLessonView: View` — `init(exercises:pack:audio:feedback:onFinish:)`, `onFinish: (LatvianLessonOutcome) -> Void`; `struct LatvianLessonOutcome { xp, accuracy, isFailed, ratings: [(wordId: String, modality: LatvianModality, rating: LatvianRating)] }`.

- [ ] **Step 1: SPM bağımlılıklarını `project.yml`'ye ekle**

Proje `xcodegen` ile üretiliyor; paketler Xcode arayüzünden değil `ios/project.yml`'den eklenir.

`packages:` bölümüne (önceki planda `FSRS` için oluşturuldu) iki giriş ekle:

```yaml
  ConfettiSwiftUI:
    url: https://github.com/simibac/ConfettiSwiftUI
    majorVersion: 2.0.0
  Lottie:
    url: https://github.com/airbnb/lottie-ios
    majorVersion: 4.0.0
```

Ve `Kuzey` hedefinin `dependencies:` listesine ekle:

```yaml
      - package: ConfettiSwiftUI
      - package: Lottie
```

Yeniden üret ve doğrula:

```bash
cd ios && xcodegen && grep -c "ConfettiSwiftUI" Kuzey.xcodeproj/project.pbxproj
```

Beklenen: grep sayısı 0'dan büyük. Sürüm çözümlemesi hata verirse `git ls-remote --tags <url> | tail -5` ile son etiketi bulup `majorVersion` değerini düzelt.

- [ ] **Step 2: Cevap panelini yaz**

`ios/Karavan/Views/Latvian/LatvianAnswerPanel.swift`:

```swift
import SwiftUI

/// Cevaptan sonra alttan gelen panel. Butona basılmadan sonraki soruya geçilmez —
/// kullanıcının doğru cevabı görmesi zorunlu.
struct LatvianAnswerPanel: View {
    let isCorrect: Bool
    let correctAnswer: String
    let explanation: String?
    let isLastQuestion: Bool
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(isCorrect ? Theme.ok : Theme.bad)
                Text(isCorrect ? "Doğru!" : "Doğru cevap")
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.text)
                Spacer()
            }

            if !isCorrect {
                Text(correctAnswer)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
            }

            if let explanation, !explanation.isEmpty {
                Text(explanation)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }

            Button(action: onContinue) {
                Text(isLastQuestion ? "Bitir" : "Devam")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(isCorrect ? Theme.bg : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        isCorrect ? AnyShapeStyle(Theme.ok) : AnyShapeStyle(Theme.bad),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isLastQuestion ? "Dersi bitir" : "Sonraki soruya geç")
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            (isCorrect ? Theme.ok : Theme.bad).opacity(0.13),
            in: UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(isCorrect ? Theme.ok : Theme.bad)
                .frame(height: 2)
        }
        .transition(.move(edge: .bottom))
    }
}
```

- [ ] **Step 3: Ders kabuğunu yaz**

`ios/Karavan/Views/Latvian/LatvianLessonView.swift`:

```swift
import SwiftUI

struct LatvianLessonOutcome {
    struct Answer {
        let wordId: String
        let modality: LatvianModality
        let rating: LatvianRating
    }

    let xp: Int
    let accuracy: Double
    let isFailed: Bool
    let answers: [Answer]
}

struct LatvianLessonView: View {
    @ObservedObject var audio: LatvianAudioStore
    @ObservedObject var feedback: LatvianFeedback
    let onFinish: (LatvianLessonOutcome) -> Void

    @State private var session: LatvianLessonSession
    @State private var pendingAnswer: LatvianAnswer?
    @State private var result: LatvianSubmissionResult?
    @State private var mood: LatvianMascotMood = .idle
    @State private var questionStartedAt = Date()
    @State private var answers: [LatvianLessonOutcome.Answer] = []
    @State private var comboFlash = false

    init(
        exercises: [LatvianExercise],
        audio: LatvianAudioStore,
        feedback: LatvianFeedback,
        onFinish: @escaping (LatvianLessonOutcome) -> Void
    ) {
        _session = State(initialValue: LatvianLessonSession(exercises: exercises))
        self.audio = audio
        self.feedback = feedback
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                if let exercise = session.current {
                    exerciseView(exercise)
                        .padding(20)
                        .id(exercise.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            Spacer(minLength: 0)
            footer
        }
        .background(Theme.bg.ignoresSafeArea())
        .onChange(of: session.current?.id) { _, _ in
            questionStartedAt = Date()
            mood = .idle
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                LatvianMascot(mood: mood, size: 48)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.panel)
                        Capsule()
                            .fill(Theme.gradWarm)
                            .frame(width: geometry.size.width * session.progress)
                    }
                }
                .frame(height: 12)
                .animation(LatvianMotion.slide, value: session.progress)

                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(Theme.bad)
                    Text("\(session.heartsLeft)")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.text)
                }
                .accessibilityLabel("\(session.heartsLeft) can kaldı")
            }

            if comboFlash {
                Text("\(session.comboCount) doğru üst üste!")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.c1)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func exerciseView(_ exercise: LatvianExercise) -> some View {
        let isLocked = result != nil
        switch exercise.content {
        case .choice:
            LatvianChoiceExerciseView(
                exercise: exercise, audio: audio, feedback: feedback,
                isLocked: isLocked, onAnswerReady: { pendingAnswer = $0 }
            )
        case .wordBank:
            LatvianWordBankExerciseView(
                exercise: exercise, feedback: feedback,
                isLocked: isLocked, onAnswerReady: { pendingAnswer = $0 }
            )
        case .matching:
            LatvianMatchExerciseView(
                exercise: exercise, feedback: feedback,
                isLocked: isLocked, onAnswerReady: { pendingAnswer = $0 }
            )
        case .typing:
            LatvianTypingExerciseView(
                exercise: exercise, audio: audio, feedback: feedback,
                isLocked: isLocked, onAnswerReady: { pendingAnswer = $0 }
            )
        case .speaking:
            LatvianSpeakExerciseView(
                exercise: exercise, audio: audio, feedback: feedback,
                isLocked: isLocked, onAnswerReady: { pendingAnswer = $0 }
            )
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let result {
            LatvianAnswerPanel(
                isCorrect: result.grade.isCorrect,
                correctAnswer: result.grade.correctAnswer,
                explanation: session.current?.explanation,
                isLastQuestion: session.remainingCount == 1 && result.grade.isCorrect,
                onContinue: continueAfterAnswer
            )
        } else {
            Button(action: submit) {
                Text("Kontrol et")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(pendingAnswer == nil ? Theme.muted : Theme.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(
                        pendingAnswer == nil ? AnyShapeStyle(Theme.panel) : AnyShapeStyle(Theme.ok),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(pendingAnswer == nil)
            .padding(20)
        }
    }

    private func submit() {
        guard let answer = pendingAnswer, let exercise = session.current else { return }
        let outcome = session.submit(
            answer,
            elapsed: Date().timeIntervalSince(questionStartedAt),
            usedHint: false
        )
        answers.append(.init(
            wordId: exercise.targetWordId, modality: exercise.modality, rating: outcome.rating
        ))

        if outcome.grade.isCorrect {
            feedback.correct()
            mood = .correct
            if outcome.isComboMilestone {
                feedback.combo()
                withAnimation(LatvianMotion.pop) { comboFlash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    withAnimation(LatvianMotion.snap) { comboFlash = false }
                }
            }
        } else {
            feedback.wrong()
            feedback.heartLost()
            mood = .wrong
        }

        withAnimation(LatvianMotion.slide) { result = outcome }
    }

    private func continueAfterAnswer() {
        withAnimation(LatvianMotion.slide) {
            session.advance()
            result = nil
            pendingAnswer = nil
        }
        if session.isFinished || session.isFailed {
            onFinish(LatvianLessonOutcome(
                xp: session.xpEarned,
                accuracy: session.accuracy,
                isFailed: session.isFailed,
                answers: answers
            ))
        }
    }
}
```

- [ ] **Step 4: Ders sonu ekranını yaz**

`ios/Karavan/Views/Latvian/LatvianLessonCompleteView.swift`:

```swift
import ConfettiSwiftUI
import SwiftUI

struct LatvianLessonCompleteView: View {
    let xp: Int
    let accuracy: Double
    let streakDays: Int
    let streakExtended: Bool
    @ObservedObject var feedback: LatvianFeedback
    let onDone: () -> Void

    @State private var confetti = 0
    @State private var shownXP = 0
    @State private var shownAccuracy = 0
    @State private var shownStreak = 0

    var body: some View {
        VStack(spacing: 26) {
            Spacer()

            LatvianMascot(mood: .celebrate, size: 132)
                .confettiCannon(trigger: $confetti, num: 42, colors: [Theme.c1, Theme.c3, Theme.c4, Theme.ok], radius: 320)

            Text("Ders tamam!")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(Theme.text)

            HStack(spacing: 12) {
                stat(value: "\(shownXP)", label: "XP", tone: Theme.c1)
                stat(value: "%\(shownAccuracy)", label: "Doğruluk", tone: Theme.c4)
                stat(value: "\(shownStreak)", label: "Gün seri", tone: Theme.c2)
            }
            .padding(.horizontal, 20)

            Spacer()

            Button(action: onDone) {
                Text("Devam")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Theme.ok, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(20)
        }
        .background(Theme.bg.ignoresSafeArea())
        .task { await runCelebration() }
    }

    private func stat(value: String, label: String, tone: Color) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 25, weight: .black, design: .rounded))
                .foregroundStyle(tone)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func runCelebration() async {
        feedback.lessonComplete()
        confetti += 1

        withAnimation(LatvianMotion.count) { shownXP = xp }
        feedback.xpTick()
        try? await Task.sleep(nanoseconds: 450_000_000)

        withAnimation(LatvianMotion.count) { shownAccuracy = Int((accuracy * 100).rounded()) }
        try? await Task.sleep(nanoseconds: 450_000_000)

        withAnimation(LatvianMotion.count) { shownStreak = streakDays }
        if streakExtended { feedback.streakUp() }
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add ios/Karavan/Views/Latvian ios/project.yml ios/Kuzey.xcodeproj
git commit -m "feat: add Latvian lesson shell, answer panel, and completion celebration"
```

---

### Task 5: Ana ekran ve rota haritası

**Files:**
- Create: `ios/Karavan/Views/Latvian/LatvianTopBar.swift`
- Create: `ios/Karavan/Views/Latvian/LatvianRouteMap.swift`
- Create: `ios/Karavan/Views/Latvian/LatvianHomeView.swift`
- Modify: `ios/Karavan/Views/Tools/LatvianLearningView.swift`

**Interfaces:**
- Consumes: `LatvianPack`, `LatvianProgress`, `LatvianLessonBuilder`, `LatvianAudioStore`, Görev 4
- Produces: `struct LatvianHomeView: View`; `@MainActor final class LatvianCourseModel: ObservableObject` (`pack`, `progress`, `unlockedScenes`, `startLesson(scene:)`, `finish(outcome:)`).

- [ ] **Step 1: Üst çubuğu yaz**

`ios/Karavan/Views/Latvian/LatvianTopBar.swift`:

```swift
import SwiftUI

struct LatvianTopBar: View {
    let streakDays: Int
    let hearts: Int
    let xp: Int
    /// Günlük hedefin tamamlanma oranı (0-1).
    let dailyProgress: Double

    var body: some View {
        HStack(spacing: 16) {
            badge(icon: "flame.fill", value: "\(streakDays)", tone: Theme.c1)
                .accessibilityLabel("\(streakDays) günlük seri")

            HStack(spacing: 3) {
                ForEach(0..<LatvianProgress.maxHearts, id: \.self) { index in
                    Image(systemName: index < hearts ? "heart.fill" : "heart")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(index < hearts ? Theme.bad : Theme.muted)
                        .scaleEffect(index < hearts ? 1 : 0.86)
                        .animation(LatvianMotion.pop, value: hearts)
                }
            }
            .accessibilityLabel("\(hearts) can")

            badge(icon: "bolt.fill", value: "\(xp)", tone: Theme.c4)
                .accessibilityLabel("\(xp) XP")

            Spacer()

            ZStack {
                Circle()
                    .stroke(Theme.panel, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: dailyProgress)
                    .stroke(Theme.ok, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(LatvianMotion.slide, value: dailyProgress)
            }
            .frame(width: 28, height: 28)
            .accessibilityLabel("Günlük hedef yüzde \(Int(dailyProgress * 100))")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func badge(icon: String, value: String, tone: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tone)
            Text(value)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText())
        }
    }
}
```

- [ ] **Step 2: Rota haritasını yaz**

`ios/Karavan/Views/Latvian/LatvianRouteMap.swift`:

```swift
import SwiftUI

struct LatvianRouteStop: Identifiable {
    let id: String
    let title: String
    let index: Int
    let isUnlocked: Bool
    let isMastered: Bool
    let masteryRatio: Double
}

/// İstanbul'dan Riga'ya uzanan yol üzerinde 12 durak.
/// Duolingo'nun patikasının bu uygulamaya ait karşılığı.
struct LatvianRouteMap: View {
    let stops: [LatvianRouteStop]
    let currentStopId: String?
    let onSelect: (LatvianRouteStop) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.element.id) { position, stop in
                HStack(spacing: 0) {
                    if position.isMultiple(of: 2) { Spacer(minLength: 0) }
                    stopNode(stop)
                        .frame(width: 210)
                    if !position.isMultiple(of: 2) { Spacer(minLength: 0) }
                }
                if position < stops.count - 1 {
                    connector(isDrawn: stop.isMastered)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func stopNode(_ stop: LatvianRouteStop) -> some View {
        Button {
            onSelect(stop)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(stop.isUnlocked ? AnyShapeStyle(Theme.gradWarm) : AnyShapeStyle(Theme.panel))
                        .frame(width: 54, height: 54)

                    Circle()
                        .trim(from: 0, to: stop.masteryRatio)
                        .stroke(Theme.ok, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 62, height: 62)
                        .animation(LatvianMotion.slide, value: stop.masteryRatio)

                    if stop.isMastered {
                        Image(systemName: "checkmark")
                            .font(.system(size: 21, weight: .black))
                            .foregroundStyle(.white)
                    } else if stop.isUnlocked {
                        Text("\(stop.index)")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.muted)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(stop.title)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(stop.isUnlocked ? Theme.text : Theme.muted)
                    Text(stop.isUnlocked ? "%\(Int(stop.masteryRatio * 100)) öğrenildi" : "Kilitli")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }

                Spacer(minLength: 0)
            }
            .overlay(alignment: .topLeading) {
                if stop.id == currentStopId {
                    LatvianMascot(mood: .idle, size: 38)
                        .offset(x: -26, y: -22)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!stop.isUnlocked)
        .accessibilityLabel("\(stop.title), \(stop.isUnlocked ? "açık" : "kilitli")")
    }

    private func connector(isDrawn: Bool) -> some View {
        Rectangle()
            .fill(isDrawn ? AnyShapeStyle(Theme.gradWarm) : AnyShapeStyle(Theme.line))
            .frame(width: 4, height: 34)
            .clipShape(Capsule())
            .animation(LatvianMotion.slide, value: isDrawn)
    }
}
```

- [ ] **Step 3: Ana ekranı ve kurs modelini yaz**

`ios/Karavan/Views/Latvian/LatvianHomeView.swift`:

```swift
import SwiftUI

@MainActor
final class LatvianCourseModel: ObservableObject {
    @Published private(set) var pack: LatvianPack?
    @Published private(set) var progress = LatvianProgress.new()
    @Published private(set) var loadError: String?
    @Published private(set) var progressWasReset = false
    @Published var activeLesson: [LatvianExercise]?
    @Published var completion: LatvianLessonOutcome?

    private let scheduler: LatvianScheduler = LatvianFSRSScheduler()
    private var factory: LatvianExerciseFactory?

    func load(audio: LatvianAudioStore) async {
        do {
            let pack = try LatvianPack.loadBundled()
            self.pack = pack
            factory = LatvianExerciseFactory(pack: pack)
            let loaded = LatvianProgress.load()
            progress = loaded.progress
            progressWasReset = loaded.wasReset
            progress.refillHearts(now: Date())
            await audio.syncMissing(pack: pack)
        } catch {
            loadError = error.localizedDescription
        }
    }

    func stops(now: Date = Date()) -> [LatvianRouteStop] {
        guard let pack else { return [] }
        return pack.scenes.map { scene in
            LatvianRouteStop(
                id: scene.id,
                title: scene.title,
                index: scene.index,
                isUnlocked: LatvianLessonBuilder.isSceneUnlocked(
                    scene: scene, pack: pack, progress: progress, now: now
                ),
                isMastered: LatvianLessonBuilder.isSceneMastered(
                    scene: scene, progress: progress, now: now
                ),
                masteryRatio: LatvianLessonBuilder.masteryRatio(
                    scene: scene, progress: progress, now: now
                )
            )
        }
    }

    var currentStopId: String? {
        stops().first { $0.isUnlocked && !$0.isMastered }?.id
    }

    func startLesson(sceneId: String, audio: LatvianAudioStore) {
        guard let pack, let scene = pack.scene(id: sceneId), let factory, progress.hearts > 0 else { return }
        activeLesson = LatvianLessonBuilder.build(
            scene: scene,
            pack: pack,
            progress: progress,
            factory: factory,
            availableAudio: audio.downloadedAudioIds,
            seed: UInt64(Date().timeIntervalSince1970),
            now: Date()
        )
    }

    func finish(_ outcome: LatvianLessonOutcome) {
        let now = Date()
        for answer in outcome.answers {
            progress.registerAnswer(
                wordId: answer.wordId,
                modality: answer.modality,
                rating: answer.rating,
                scheduler: scheduler,
                now: now
            )
            if answer.rating == .again { progress.loseHeart(now: now) }
        }
        if !outcome.isFailed {
            progress.xp += outcome.xp
            progress.registerLessonCompleted(now: now)
        }
        try? progress.save()
        activeLesson = nil
        completion = outcome.isFailed ? nil : outcome
    }
}

struct LatvianHomeView: View {
    @StateObject private var model = LatvianCourseModel()
    @StateObject private var audio = LatvianAudioStore()
    @StateObject private var feedback = LatvianFeedback()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            if let error = model.loadError {
                errorState(error)
            } else {
                content
            }
        }
        .task { await model.load(audio: audio) }
        .fullScreenCover(item: Binding(
            get: { model.activeLesson.map(LessonBox.init) },
            set: { if $0 == nil { model.activeLesson = nil } }
        )) { box in
            LatvianLessonView(
                exercises: box.exercises,
                audio: audio,
                feedback: feedback,
                onFinish: model.finish
            )
        }
        .fullScreenCover(item: Binding(
            get: { model.completion.map(CompletionBox.init) },
            set: { if $0 == nil { model.completion = nil } }
        )) { box in
            LatvianLessonCompleteView(
                xp: box.outcome.xp,
                accuracy: box.outcome.accuracy,
                streakDays: model.progress.streakDays,
                streakExtended: true,
                feedback: feedback,
                onDone: { model.completion = nil }
            )
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            LatvianTopBar(
                streakDays: model.progress.streakDays,
                hearts: model.progress.hearts,
                xp: model.progress.xp,
                dailyProgress: model.progress.lastLessonDay == LatvianProgress.dayKey(Date()) ? 1 : 0
            )

            if audio.isDownloading {
                downloadBanner
            }

            if model.progressWasReset {
                Text("İlerleme dosyası okunamadı, yedekten devam ediliyor.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.warn)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            ScrollView {
                LatvianRouteMap(
                    stops: model.stops(),
                    currentStopId: model.currentStopId,
                    onSelect: { stop in
                        feedback.tap()
                        model.startLesson(sceneId: stop.id, audio: audio)
                    }
                )
                .padding(.vertical, 24)
            }
        }
    }

    private var downloadBanner: some View {
        VStack(spacing: 6) {
            Text("Letonca sesleri hazırlanıyor")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.dim)
            ProgressView(value: audio.downloadProgress)
                .tint(Theme.c4)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            LatvianMascot(mood: .wrong, size: 88)
            Text(message)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

/// `fullScreenCover(item:)` `Identifiable` istediği için dizi ve sonuç sarmalanıyor.
private struct LessonBox: Identifiable {
    let exercises: [LatvianExercise]
    var id: String { exercises.first?.id ?? "empty" }
}

private struct CompletionBox: Identifiable {
    let outcome: LatvianLessonOutcome
    var id: String { "\(outcome.xp)-\(outcome.accuracy)" }
}
```

- [ ] **Step 4: Eski görünümü kabuğa indir**

`ios/Karavan/Views/Tools/LatvianLearningView.swift` dosyasının tamamını şununla değiştir:

```swift
import SwiftUI

/// Araçlar sekmesinden Letonca kursuna giriş.
struct LatvianLearningView: View {
    var body: some View {
        LatvianHomeView()
            .navigationTitle("Letonca")
            .navigationBarTitleDisplayMode(.inline)
    }
}
```

- [ ] **Step 5: Derle ve simülatörde çalıştır**

```bash
xcodebuild -project ios/Kuzey.xcodeproj -scheme Kuzey -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```

Beklenen: `BUILD SUCCEEDED`.

Ardından simülatörde uygulamayı aç, Araçlar → Letonca yolunu izle ve şunları gözle doğrula: ses indirme çubuğu görünüyor ve doluyor; rota haritasında 12 durak var, ilki açık kalanı kilitli; ilk durağa dokununca 16 soruluk ders başlıyor; doğru cevapta yeşil panel + maskot zıplıyor + ses çıkıyor; yanlış cevapta kırmızı panel + kart sarsılıyor + bir kalp gidiyor; dinleme sorusunda "Dinle" butonu gerçekten Letonca ses çalıyor; ders bitince konfeti patlıyor ve sayaçlar dolarak sayıyor.

Ses çalmıyorsa `data/lv-audio/` klasöründeki dosyaların Blob'a yüklendiğini ve `latvian-pack.json` içindeki `audioBaseUrl` değerinin doğru olduğunu kontrol et.

- [ ] **Step 6: Commit**

```bash
git add ios/Karavan/Views
git commit -m "feat: add Latvian course home with route map and lesson flow"
```

---

### Task 6: Bildirimler

**Files:**
- Create: `ios/Karavan/Learning/LatvianNotifications.swift`
- Modify: `ios/Karavan/Notifications/NotificationRules.swift`
- Modify: `ios/Tests/latvian-engine-check.swift`, `ios/Tests/run-latvian-check.sh`

**Interfaces:**
- Consumes: `LatvianProgress` (önceki plan)
- Produces: `NotifKind` içinde `latvianDaily`, `latvianStreakRescue`, `latvianMilestone`, `latvianDecay`; `enum LatvianNotificationRules` (saf kararlar); `@MainActor enum LatvianNotificationScheduler` (`reschedule(progress:pack:now:)`, `cancelAll()`).

- [ ] **Step 1: `NotifKind`'a kategorileri ekle**

`ios/Karavan/Notifications/NotificationRules.swift` içinde `enum NotifKind` gövdesine satır ekle:

```swift
    case latvianDaily, latvianStreakRescue, latvianMilestone, latvianDecay
```

`isCritical` içindeki `switch` değişmez — Letonca bildirimleri kritik değildir, dolayısıyla 45 dakikalık soğumaya tabidir ve sınır geçişi gibi kritik bildirimlerin önüne geçemez.

- [ ] **Step 2: Testi ekle**

`ios/Tests/latvian-engine-check.swift` içinde son `if failures > 0` bloğunun üstüne ekle:

```swift
print("\n=== Bildirim kuralları ===")

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!

func moment(_ hour: Int, day: Int = 15) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
}

expect(LatvianNotificationRules.isQuietHour(moment(2), calendar: calendar), "gece 02:00 sessiz saatte")
expect(LatvianNotificationRules.isQuietHour(moment(23), calendar: calendar), "23:00 sessiz saatte")
expect(!LatvianNotificationRules.isQuietHour(moment(9), calendar: calendar), "09:00 sessiz saatte değil")
expect(!LatvianNotificationRules.isQuietHour(moment(20), calendar: calendar), "20:00 sessiz saatte değil")

expect(LatvianNotificationRules.preferredHour(recentLessonHours: [], calendar: calendar) == 20,
       "geçmiş yoksa varsayılan saat 20:00")
expect(LatvianNotificationRules.preferredHour(recentLessonHours: [9, 9, 21], calendar: calendar) == 9,
       "en sık ders saati seçiliyor")
expect(LatvianNotificationRules.preferredHour(recentLessonHours: [2, 2, 2], calendar: calendar) == 20,
       "sessiz saate düşen alışkanlık varsayılana çekiliyor")

var streaking = LatvianProgress.new()
streaking.streakDays = 6
streaking.lastLessonDay = LatvianProgress.dayKey(moment(20, day: 14), calendar: calendar)

expect(LatvianNotificationRules.needsStreakRescue(progress: streaking, now: moment(21), calendar: calendar),
       "aktif seride, gün bitmeden ders yoksa kurtarma gerekiyor")
expect(!LatvianNotificationRules.needsStreakRescue(progress: streaking, now: moment(14), calendar: calendar),
       "günün erken saatinde kurtarma bildirimi yok")

var doneToday = streaking
doneToday.lastLessonDay = LatvianProgress.dayKey(moment(10), calendar: calendar)
expect(!LatvianNotificationRules.needsStreakRescue(progress: doneToday, now: moment(21), calendar: calendar),
       "bugün ders yapıldıysa kurtarma bildirimi yok")

var noStreak = LatvianProgress.new()
noStreak.streakDays = 0
expect(!LatvianNotificationRules.needsStreakRescue(progress: noStreak, now: moment(21), calendar: calendar),
       "seri yoksa kurtarma bildirimi yok")

expect(LatvianNotificationRules.isMilestone(7), "7 gün dönüm noktası")
expect(LatvianNotificationRules.isMilestone(30), "30 gün dönüm noktası")
expect(LatvianNotificationRules.isMilestone(100), "100 gün dönüm noktası")
expect(!LatvianNotificationRules.isMilestone(8), "8 gün dönüm noktası değil")

let decayed = LatvianNotificationRules.decayingScene(
    pack: pack, progress: LatvianProgress.new(), now: epoch, lastDecayNotice: nil
)
expect(decayed == nil, "hiç öğrenilmemiş sahne için unutma uyarısı yok")

expect(!LatvianNotificationRules.canSendDecayNotice(
    lastDecayNotice: epoch, now: epoch.addingTimeInterval(86_400 * 3)
), "unutma uyarısı üç günde bir gönderilmiyor")
expect(LatvianNotificationRules.canSendDecayNotice(
    lastDecayNotice: epoch, now: epoch.addingTimeInterval(86_400 * 8)
), "unutma uyarısı sekiz gün sonra gönderilebiliyor")
```

- [ ] **Step 3: Test betiğine dosyayı ekle**

`ios/Tests/run-latvian-check.sh` içindeki `swiftc` çağrısına satır ekle:

```bash
  "$SRC/LatvianNotifications.swift" \
```

- [ ] **Step 4: Testi çalıştırıp başarısız olduğunu gör**

```bash
./ios/Tests/run-latvian-check.sh
```

Beklenen: `error: cannot find 'LatvianNotificationRules' in scope`.

- [ ] **Step 5: Bildirim modülünü yaz**

`ios/Karavan/Learning/LatvianNotifications.swift`:

```swift
import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Saf karar fonksiyonları — cihazsız test edilebilir.
enum LatvianNotificationRules {
    static let quietStartHour = 23
    static let quietEndHour = 8
    static let defaultHour = 20
    static let streakRescueHour = 21
    static let decayCooldown: TimeInterval = 7 * 86_400
    static let milestones: Set<Int> = [7, 30, 100]

    static func isQuietHour(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= quietStartHour || hour < quietEndHour
    }

    /// Son derslerin en sık yapıldığı saat. Sessiz saate düşerse varsayılana çekilir.
    static func preferredHour(recentLessonHours: [Int], calendar: Calendar = .current) -> Int {
        guard !recentLessonHours.isEmpty else { return defaultHour }
        var counts: [Int: Int] = [:]
        for hour in recentLessonHours { counts[hour, default: 0] += 1 }
        let best = counts.max { left, right in
            left.value == right.value ? left.key > right.key : left.value < right.value
        }?.key ?? defaultHour
        return (best >= quietStartHour || best < quietEndHour) ? defaultHour : best
    }

    static func needsStreakRescue(
        progress: LatvianProgress,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard progress.streakDays > 0 else { return false }
        guard progress.lastLessonDay != LatvianProgress.dayKey(now, calendar: calendar) else { return false }
        let hour = calendar.component(.hour, from: now)
        return hour >= streakRescueHour && hour < quietStartHour
    }

    static func isMilestone(_ streakDays: Int) -> Bool {
        milestones.contains(streakDays)
    }

    static func canSendDecayNotice(lastDecayNotice: Date?, now: Date) -> Bool {
        guard let lastDecayNotice else { return true }
        return now.timeIntervalSince(lastDecayNotice) >= decayCooldown
    }

    /// Hatırlama olasılığı eşiğin altına düşmüş, daha önce öğrenilmiş sahne.
    static func decayingScene(
        pack: LatvianPack,
        progress: LatvianProgress,
        now: Date,
        lastDecayNotice: Date?
    ) -> LatvianScene? {
        guard canSendDecayNotice(lastDecayNotice: lastDecayNotice, now: now) else { return nil }
        return pack.scenes.first { scene in
            progress.sceneCompletedAt[scene.id] != nil
                && !LatvianLessonBuilder.isSceneMastered(scene: scene, progress: progress, now: now)
        }
    }
}

#if canImport(UserNotifications)
/// Planlanmış yerel bildirimleri kurar. Günde en fazla iki bildirim.
@MainActor
enum LatvianNotificationScheduler {
    private static let prefix = "letonca."

    static func reschedule(
        progress: LatvianProgress,
        pack: LatvianPack?,
        recentLessonHours: [Int],
        lastDecayNotice: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return }
        cancelAll()

        var budget = NotificationBudget()

        // 1. Günlük hatırlatma
        let hour = LatvianNotificationRules.preferredHour(recentLessonHours: recentLessonHours, calendar: calendar)
        if budget.allow(.latvianDaily, now: now) {
            schedule(
                id: "\(prefix)daily",
                title: "Letonca vakti",
                body: "Bugünün dersi seni bekliyor. Üç dakika yeter.",
                hour: hour,
                minute: 0
            )
        }

        // 2. Seri kurtarma — yalnızca aktif seri varsa
        if progress.streakDays > 0, budget.allow(.latvianStreakRescue, now: now) {
            schedule(
                id: "\(prefix)streak",
                title: "Serin \(progress.streakDays) gün",
                body: "Bugün henüz Letonca çalışmadın. Bir ders yeter.",
                hour: LatvianNotificationRules.streakRescueHour,
                minute: 30
            )
        }

        // 3. Unutma uyarısı — haftada en fazla bir kez
        if let pack,
           let scene = LatvianNotificationRules.decayingScene(
               pack: pack, progress: progress, now: now, lastDecayNotice: lastDecayNotice
           ) {
            schedule(
                id: "\(prefix)decay",
                title: "\(scene.title) unutulmaya başladı",
                body: "Üç dakikalık bir tekrar yeter.",
                hour: LatvianNotificationRules.defaultHour,
                minute: 30,
                daysFromNow: 1
            )
        }
    }

    static func celebrateMilestone(streakDays: Int) {
        guard LatvianNotificationRules.isMilestone(streakDays) else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(streakDays) gün!"
        content.body = "Letoncayı gerçekten öğreniyorsun."
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "\(prefix)milestone-\(streakDays)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
            )
        )
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private static func schedule(
        id: String,
        title: String,
        body: String,
        hour: Int,
        minute: Int,
        daysFromNow: Int = 0
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let trigger: UNNotificationTrigger = daysFromNow > 0
            ? UNTimeIntervalNotificationTrigger(
                timeInterval: Double(daysFromNow) * 86_400, repeats: false
              )
            : UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        )
    }
}
#endif
```

- [ ] **Step 6: Bildirimleri ders sonuna bağla**

`ios/Karavan/Views/Latvian/LatvianHomeView.swift` içinde `LatvianCourseModel.finish` fonksiyonunun `try? progress.save()` satırının hemen altına ekle:

```swift
        LatvianNotificationScheduler.celebrateMilestone(streakDays: progress.streakDays)
        Task {
            await LatvianNotificationScheduler.reschedule(
                progress: progress,
                pack: pack,
                recentLessonHours: recentLessonHours,
                lastDecayNotice: lastDecayNotice
            )
        }
```

Ve sınıfa iki saklama alanı ekle (`@Published private(set) var pack` satırının altına):

```swift
    @AppStorage("letonca.lastDecayNotice") private var lastDecayNoticeStamp: Double = 0
    @AppStorage("letonca.lessonHours") private var lessonHoursRaw: String = ""

    private var lastDecayNotice: Date? {
        lastDecayNoticeStamp == 0 ? nil : Date(timeIntervalSince1970: lastDecayNoticeStamp)
    }

    private var recentLessonHours: [Int] {
        lessonHoursRaw.split(separator: ",").compactMap { Int($0) }
    }

    private func recordLessonHour(_ date: Date) {
        var hours = recentLessonHours
        hours.append(Calendar.current.component(.hour, from: date))
        if hours.count > 7 { hours.removeFirst() }
        lessonHoursRaw = hours.map(String.init).joined(separator: ",")
    }
```

`finish` içinde `if !outcome.isFailed {` bloğuna `recordLessonHour(now)` satırını ekle.

- [ ] **Step 7: Testi çalıştır**

```bash
./ios/Tests/run-latvian-check.sh
```

Beklenen: `=== Bildirim kuralları ===` altında on dokuz `✓`, çıkış kodu 0.

- [ ] **Step 8: Derle ve tam akışı doğrula**

```bash
xcodebuild -project ios/Kuzey.xcodeproj -scheme Kuzey -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```

Beklenen: `BUILD SUCCEEDED`. Simülatörde bir ders tamamla, bildirim izni istendiğini ve `Settings > Notifications` altında planlanmış bildirimlerin göründüğünü doğrula.

- [ ] **Step 9: Commit**

```bash
git add ios/Karavan/Learning/LatvianNotifications.swift ios/Karavan/Notifications/NotificationRules.swift ios/Karavan/Views/Latvian/LatvianHomeView.swift ios/Tests/
git commit -m "feat: add Latvian learning notifications with quiet hours and streak rescue"
```

---

### Task 7: Ayarlar ve son doğrulama

**Files:**
- Modify: `ios/Karavan/Views/Latvian/LatvianHomeView.swift`
- Modify: `ios/Karavan/Views/Tools/ToolsView.swift`

**Interfaces:**
- Consumes: `LatvianFeedback`, `LatvianAudioStore`
- Produces: Ayar sayfası — ses efektleri, telaffuz sesi ve bildirim anahtarları.

- [ ] **Step 1: Ayar sayfasını ekle**

`ios/Karavan/Views/Latvian/LatvianHomeView.swift` dosyasının sonuna ekle:

```swift
struct LatvianSettingsView: View {
    @ObservedObject var feedback: LatvianFeedback
    @AppStorage("letonca.speechEnabled") private var speechEnabled = true
    @AppStorage("letonca.notificationsEnabled") private var notificationsEnabled = true

    var body: some View {
        List {
            Section("Ses") {
                Toggle("Ses efektleri", isOn: $feedback.soundsEnabled)
                Toggle("Telaffuz sesi", isOn: $speechEnabled)
            }
            Section("Bildirimler") {
                Toggle("Letonca hatırlatmaları", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, enabled in
                        if !enabled { LatvianNotificationScheduler.cancelAll() }
                    }
            }
            Section {
                Text("Hatırlatmalar 23:00-08:00 arasında gönderilmez ve günde en fazla iki tanedir.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
        }
        .navigationTitle("Letonca ayarları")
    }
}
```

Ve `LatvianHomeView`'in `content` görünümündeki `LatvianTopBar` çağrısını bir `NavigationLink` ile sar:

```swift
            HStack(spacing: 0) {
                LatvianTopBar(
                    streakDays: model.progress.streakDays,
                    hearts: model.progress.hearts,
                    xp: model.progress.xp,
                    dailyProgress: model.progress.lastLessonDay == LatvianProgress.dayKey(Date()) ? 1 : 0
                )
                NavigationLink {
                    LatvianSettingsView(feedback: feedback)
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(.trailing, 20)
                }
            }
```

- [ ] **Step 2: Telaffuz sesi anahtarını bağla**

`ios/Karavan/Learning/LatvianAudioStore.swift` içinde sınıfın başına ekle:

```swift
    @AppStorage("letonca.speechEnabled") private var speechEnabled = true
```

Ve `play(audioId:)` fonksiyonunun ilk satırı olarak ekle:

```swift
        guard speechEnabled else { return }
```

`import SwiftUI` satırını dosyanın başına ekle.

- [ ] **Step 3: Tüm testleri çalıştır**

```bash
./ios/Tests/run-latvian-check.sh && ./ios/Tests/run-notification-check.sh && ./ios/Tests/run-account-check.sh && npm run check:latvian-pack && npm run lint
```

Beklenen: hepsi yeşil.

- [ ] **Step 4: Uygulamayı derle ve tam turu at**

```bash
xcodebuild -project ios/Kuzey.xcodeproj -scheme Kuzey -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```

Simülatörde şu turu tamamla ve her adımı gözle doğrula:

1. Araçlar → Letonca. Ses indirme çubuğu dolup kayboluyor.
2. Rota haritası: 12 durak, ilki açık, kalanı kilitli, maskot ilk durakta.
3. İlk dersi tamamla. On soru tipinden gelenlerin hepsi çalışıyor, "Dinle" her seferinde ses veriyor.
4. Bilerek bir soruyu yanlış yap: kart sarsılıyor, kalp gidiyor, kırmızı panel doğru cevabı gösteriyor, soru dersin sonunda tekrar geliyor.
5. Üç doğru üst üste: kombo yazısı beliriyor.
6. Ders sonu: konfeti, maskot kutluyor, üç sayaç sırayla doluyor.
7. Ayarlar: ses efektlerini kapat, bir ders daha başlat, efekt sesi çıkmıyor ama telaffuz sesi çıkıyor.
8. Aynı sahneyi birkaç kez tamamla: durak halkası doluyor, %80'e ulaşınca ikinci durak açılıyor.

- [ ] **Step 5: Commit**

```bash
git add ios/Karavan
git commit -m "feat: add Latvian course settings and wire audio toggle"
```

---

## Tamamlanma ölçütü

- `./ios/Tests/run-latvian-check.sh` yeşil.
- `xcodebuild` başarılı, uygulama simülatörde çalışıyor.
- Görev 7 Adım 4'teki sekiz maddelik tur eksiksiz geçiyor.
- Ses her soru tipinde ya çalıyor ya da o soru tipi hiç üretilmiyor — sessizce başarısız olan buton kalmadı.
- Hiçbir görünüm dosyası 250 satırı geçmiyor.

## Tasarımdan bilerek ayrılan iki nokta

Tasarım belgesinde geçen ama bu üç planda uygulanmayan iki madde. İkisi de sonraki bir turda eklenir; şimdi eklenmemelerinin gerekçesi burada kayıtlı.

**Hızlı tekrar (11. soru tipi).** Tasarımda 11 soru tipi sayılmıştı; `LatvianExerciseKind` 10 tane içeriyor. Sebep: "hızlı tekrar" yeni bir soru *tipi* değil, var olan soruları süre baskısıyla sunan bir ders *modu*. Kendi içeriği, kendi doğru cevabı yok — sadece bilinen kelimelerden kurulmuş bir ders üstüne sayaç ekliyor. Soru tipi olarak modellemek `LatvianExerciseContent`'e karşılığı olmayan bir durum sokardı. Doğru yeri `LatvianLessonSession`'a bir `mode: .normal | .timed` alanı ve `LatvianLessonBuilder`'a yalnızca hatırlama olasılığı yüksek kelimelerden ders kuran bir yol eklemek. Ayrı ve küçük bir iş; bu planlara girmedi.

**Tekrar dersiyle can kazanma.** `LatvianProgress.refillHearts` canları 4 saatte bir dolduruyor, ama tasarımdaki "bir tekrar dersi oynayarak anında can kazan" yolu yok. Sebep: bu, can bitince gösterilecek ayrı bir ekran ve ödülü canla sınırlı (XP vermeyen) özel bir ders türü gerektiriyor — ders akışına ikinci bir sonuç yolu ekliyor. Görev 1'deki oturum mantığı bunu desteklemeye hazır (`LatvianLessonOutcome` zaten `isFailed` taşıyor), ama ekran ve ödül kuralı yazılmadı. Şimdilik can bitince ders yarıda kalıyor, toplanan FSRS verisi kaydediliyor ve kullanıcı 4 saat bekliyor.
