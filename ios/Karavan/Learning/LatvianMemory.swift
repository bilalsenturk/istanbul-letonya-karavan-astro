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
    ///   - fastThreshold: Bu sürenin altındaki cevap "easy" sayılır; soru tipine göre değişir
    ///     (bkz. `LatvianExerciseKind.fastThresholdSeconds`).
    static func from(isCorrect: Bool, attempts: Int, usedHint: Bool, elapsed: TimeInterval, fastThreshold: TimeInterval) -> LatvianRating {
        guard isCorrect else { return .again }
        if attempts > 1 || usedHint { return .hard }
        return elapsed <= fastThreshold ? .easy : .good
    }
}

struct LatvianMemoryKey: Hashable, Sendable {
    let wordId: String
    let modality: LatvianModality

    var storageKey: String { "\(wordId)#\(modality.rawValue)" }

    /// Boş `wordId` anlamsızdır ve `storageKey`'e kodlanıp geri çözülemez; bu yüzden burada da reddedilir.
    init?(wordId: String, modality: LatvianModality) {
        guard !wordId.isEmpty else { return nil }
        self.wordId = wordId
        self.modality = modality
    }

    /// `wordId` teorik olarak `#` içerebileceğinden, ayırıcının SON geçtiği yerden bölünür;
    /// böylece modalite her zaman doğru ayrıştırılır ve dize dönüşü tersine çevrilebilir kalır.
    init?(storageKey: String) {
        guard let separatorRange = storageKey.range(of: "#", options: .backwards) else { return nil }
        let wordPart = storageKey[storageKey.startIndex..<separatorRange.lowerBound]
        let modalityPart = storageKey[separatorRange.upperBound...]
        guard !wordPart.isEmpty, let modality = LatvianModality(rawValue: String(modalityPart)) else { return nil }
        self.wordId = String(wordPart)
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
    /// Hiç tekrar edilmemiş (ya da kararlılığı sıfır/negatif olan) kartlar için 0 döner;
    /// aksi halde inceleme anından itibaren geçen günle birlikte monoton azalır.
    func retrievability(at moment: Date) -> Double {
        guard let lastReviewedAt, stability > 0 else { return 0 }
        let elapsedDays = max(0, moment.timeIntervalSince(lastReviewedAt) / 86_400)
        return pow(1 + elapsedDays / (9 * stability), -1)
    }

    func isDue(at moment: Date) -> Bool { dueAt <= moment }
}

protocol LatvianScheduler: Sendable {
    func review(card: LatvianMemoryCard, rating: LatvianRating, now: Date) -> LatvianMemoryCard
}

/// FSRS benzeri yedek planlayıcı. Gerçek `swift-fsrs` erişilemediğinde ve testlerde kullanılır.
/// Davranışı FSRS ile aynı yönde: doğru cevap kararlılığı çarpanla artırır, yanlış cevap çökertir.
/// Kararlılık her yol için (sıfırdan başlayan sabitler ya da pozitif çarpanlar sayesinde) hep pozitif
/// kalır, böylece `retrievability(at:)` asla sıfıra bölme veya negatif üstel durumuyla karşılaşmaz.
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
