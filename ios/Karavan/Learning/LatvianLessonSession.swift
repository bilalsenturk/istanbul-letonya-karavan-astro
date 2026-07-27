import Foundation

/// Tek bir cevabın oturuma yansıması. Arayüz cevap panelini bununla çiziyor:
/// doğru muydu, doğrusu neydi, kaç can kaldı, kombo kaçta, kaç XP geldi.
///
/// `rating` oturumun kendi işi değil — çağıran bunu `LatvianProgress.registerAnswer`
/// üzerinden planlayıcıya geçiriyor. Oturum hafızaya yazmıyor; sadece dereceyi üretiyor.
struct LatvianSubmissionResult: Hashable, Sendable {
    let grade: LatvianGrade
    let rating: LatvianRating
    let heartsLeft: Int
    let comboCount: Int
    let xpGained: Int
    let isComboMilestone: Bool
}

/// Bir dersin akışını yönetir: soru sırası, can, kombo, XP.
///
/// `SwiftUI` bilmez ve **saat okumaz** — geçen süre her cevapla birlikte dışarıdan
/// veriliyor (`submit(_:elapsed:usedHint:)`). İkisi de bilerek: akışın tamamı bu yüzden
/// arayüz açmadan, gerçek zamanı beklemeden sınanabiliyor.
///
/// ## Temel kural
///
/// Yanlış cevaplanan soru **kuyruğun sonuna** geri gider ve ders o soru doğru
/// cevaplanmadan bitmez. Dolayısıyla biten bir derste her soru tam olarak bir kez
/// "tamamlanmış" sayılır, ama gönderilen cevap sayısı soru sayısından fazla olabilir.
///
/// ## İki uçlu geçiş: `submit` ve `advance`
///
/// `submit` notlar ve durumu günceller, **sırayı ilerletmez**; `advance` ilerletir.
/// Ayrı olmalarının sebebi arayüz: cevap paneli açıkken soru ekranda kalmalı. Ayrılığın
/// bedeli, ikisinin yanlış sırada ya da iki kez çağrılabilmesi (çift dokunuş, geri gelen
/// ekran). Bu yüzden:
///
/// - Bekleyen bir sonuç varken gelen ikinci `submit` **yeniden notlamaz**, kayıtlı
///   sonucu aynen döner. Yoksa tek soru iki XP, iki can ve iki deneme sayardı.
/// - Cevap gönderilmeden ya da iki kez çağrılan `advance` hiçbir şey yapmaz.
///
/// ## Ders bitince ve can bitince oturum donar
///
/// Can sıfırlandığı anda ders başarısız olur; `submit` ve `advance` o andan sonra
/// hiçbir sayacı değiştirmez. Kuyruğun dönmeye devam etmemesi bunun bir parçası:
/// başarısız ders bitmiş ders değil, ama sonsuza kadar oynanan ders de değil.
final class LatvianLessonSession {
    static let maxHearts = 5
    static let baseXP = 10
    static let comboBonusXP = 5

    /// Bonus veren kombo eşikleri. Ders başına her eşik **bir kez** ödüllendiriliyor
    /// (bkz. `awardedMilestones`). Ondan sonrası bonussuz: eşikler sabit bir liste,
    /// "her 10'da bir" gibi tekrar eden bir kural değil — 16 soruluk bir derste 10'un
    /// üstünde ikinci bir eşiğe yer yok.
    static let comboMilestones: [Int] = [3, 5, 10]

    /// Ders başındaki sorular, sırası değişmeden. Kuyruk bunlara indeksle bakıyor.
    private let exercises: [LatvianExercise]

    /// Cevaplanmayı bekleyen soruların `exercises` içindeki indeksleri (kısaca "yuva").
    ///
    /// Sorunun kendisi ya da kimliği değil indeksi tutuluyor. `init` aynı kimliği
    /// taşıyan iki soruyu yasaklamıyor (ders kurucusu üretmiyor ama sözleşme bunu
    /// garanti etmiyor); kimliğe dayalı sayaçlar öyle bir derste iki soruyu tek soru
    /// sanar, deneme sayısını karıştırır ve ilerlemeyi eksik gösterirdi.
    private var queue: [Int]

    /// Yuva başına gönderilen cevap sayısı. `LatvianRating.from`'un `attempts` girdisi:
    /// ikinci denemede bulunan doğru, ne kadar hızlı olursa olsun `hard` sayılıyor.
    private var attemptsBySlot: [Int]

    /// Bu derste bonusu verilmiş kombo eşikleri.
    private var awardedMilestones: Set<Int> = []

    private(set) var heartsLeft: Int
    private(set) var comboCount = 0
    private(set) var xpEarned = 0
    /// Doğru notlanan cevap sayısı. Her soru tam olarak bir kez doğru cevaplandığı için
    /// bu aynı zamanda tamamlanan soru sayısıdır.
    private(set) var correctCount = 0
    /// Oturumun **kabul ettiği** cevap sayısı. Yok sayılan gönderimler (bekleyen sonuç
    /// varken, ders bitince, can bitince) buraya girmiyor.
    private(set) var answerCount = 0
    /// Doğru cevaplanıp kuyruktan düşen soru sayısı.
    private(set) var completedCount = 0

    /// Notlanmış ama henüz `advance()` ile kapatılmamış sonuç. Arayüzün açık cevap
    /// paneli bu.
    private(set) var pendingResult: LatvianSubmissionResult?

    init(exercises: [LatvianExercise]) {
        self.exercises = exercises
        queue = Array(exercises.indices)
        attemptsBySlot = Array(repeating: 0, count: exercises.count)
        heartsLeft = LatvianLessonSession.maxHearts
    }

    /// Ekranda olması gereken soru. Ders bitince ya da soru kalmayınca `nil`.
    /// Başarısız derste, canı bitiren soru sırada kalmaya devam eder.
    var current: LatvianExercise? {
        guard let slot = queue.first else { return nil }
        return exercises[slot]
    }

    var remainingCount: Int { queue.count }

    /// Arayüzün "cevap paneli açık mı" sorusu.
    var isAwaitingAdvance: Bool { pendingResult != nil }

    var isFailed: Bool { heartsLeft <= 0 }

    /// Başarısız ders **bitmiş sayılmaz**; ikisi ayrı sonuç ekranı.
    var isFinished: Bool { queue.isEmpty && !isFailed }

    /// Tamamlanan soruların oranı, `0...1`. Yanlış cevap ilerletmez (soru kuyrukta
    /// kalır), aynı soruyu ikinci kez doğru cevaplamak da ikinci kez ilerletmez.
    /// Soru verilmemiş ders baştan tamamdır.
    var progress: Double {
        guard !exercises.isEmpty else { return 1 }
        return Double(completedCount) / Double(exercises.count)
    }

    /// Doğruluk **gönderim başına** ölçülüyor: doğru cevaplar / kabul edilen cevaplar.
    /// Soru başına ölçmek anlamsız olurdu — biten derste her soru eninde sonunda doğru
    /// cevaplanıyor, yani soru başına doğruluk her zaman 1 çıkardı. Gönderim başına
    /// ölçüm "ilk denemede kaçını bildi"nin ta kendisi ve `0...1` aralığında kalıyor.
    /// Henüz cevap gönderilmemişse 0.
    var accuracy: Double {
        guard answerCount > 0 else { return 0 }
        return Double(correctCount) / Double(answerCount)
    }

    /// Cevabı notlar, can/kombo/XP'yi günceller. **Sırayı ilerletmez** — bunun için
    /// `advance()` çağrılır.
    ///
    /// Üç durumda hiçbir şeyi değiştirmez: ders başarısızsa, sırada soru yoksa (ders
    /// bitmişse) ve bekleyen bir sonuç varken. İlk ikisinde nötr bir sonuç döner
    /// (`grade.isCorrect == false`, `xpGained == 0`) — çağıran zaten bu durumlarda
    /// cevap ekranı göstermiyor. Üçüncüsünde kayıtlı sonucun kendisi döner.
    @discardableResult
    func submit(_ answer: LatvianAnswer, elapsed: TimeInterval, usedHint: Bool) -> LatvianSubmissionResult {
        guard !isFailed else { return ignoredResult() }
        if let pendingResult { return pendingResult }
        guard let slot = queue.first else { return ignoredResult() }

        let exercise = exercises[slot]
        attemptsBySlot[slot] += 1

        let grade = LatvianGrader.grade(exercise: exercise, answer: answer)
        let rating = LatvianRating.from(
            isCorrect: grade.isCorrect,
            attempts: attemptsBySlot[slot],
            usedHint: usedHint,
            elapsed: elapsed,
            fastThreshold: exercise.kind.fastThresholdSeconds
        )

        answerCount += 1
        var xpGained = 0
        var isMilestone = false

        if grade.isCorrect {
            correctCount += 1
            comboCount += 1
            xpGained = LatvianLessonSession.baseXP
            if LatvianLessonSession.comboMilestones.contains(comboCount),
               awardedMilestones.insert(comboCount).inserted {
                xpGained += LatvianLessonSession.comboBonusXP
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
        pendingResult = result
        return result
    }

    /// Cevap paneli kapandığında çağrılır. Doğru cevaplanan soru kuyruktan düşer,
    /// yanlış cevaplanan soru kuyruğun sonuna gider.
    ///
    /// Bekleyen sonuç yoksa (henüz cevap gönderilmedi ya da bu ikinci çağrı) ve ders
    /// başarısızsa hiçbir şey yapmaz.
    func advance() {
        guard !isFailed, let result = pendingResult, let slot = queue.first else { return }
        queue.removeFirst()
        if result.grade.isCorrect {
            completedCount += 1
        } else {
            queue.append(slot)
        }
        pendingResult = nil
    }

    /// Yok sayılan gönderimin cevabı. Hiçbir sayacı değiştirmez ve `pendingResult`'a
    /// yazılmaz; sadece imzanın istediği değeri üretir.
    private func ignoredResult() -> LatvianSubmissionResult {
        LatvianSubmissionResult(
            grade: LatvianGrade(isCorrect: false, correctAnswer: ""),
            rating: .again,
            heartsLeft: heartsLeft,
            comboCount: comboCount,
            xpGained: 0,
            isComboMilestone: false
        )
    }
}
