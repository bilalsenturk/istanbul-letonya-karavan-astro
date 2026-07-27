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

    /// Kartın **hafıza durumunu** taze bir kartınkine döndürür; **geçmişini korur**.
    ///
    /// Sıfırlanan yalnızca iki alan: `stability` ve `difficulty`. Planlayıcı bir sonraki
    /// cevabı böylece ilk karşılaşma gibi işler — gerçek FSRS'te `stability <= 0` olan kart
    /// `.new` sayılıp zorluğu dereceden yeniden türetilir (bkz. `LatvianFSRSScheduler`),
    /// yer tutucuda da `stability == 0` dalları devreye girer.
    ///
    /// Korunanlar ve sebepleri:
    ///
    /// - **`lapseCount`.** Sıfırlanırsa kart bir sonraki dört unutmada yeniden sıfırlanır ve
    ///   bu sonsuza kadar sürer: sıfırlama kendi tetiğini siler. Sayaç ayrıca takılma
    ///   teşhisinin (`LatvianLessonBuilder.isLeech`) yarısı; silmek kelimeyi kurtarma
    ///   havuzundan da düşürürdü.
    /// - **`reviewCount`.** Hakimiyet kapısı `reviewCount >= minimumReviews` istiyor.
    ///   Sayacı sıfırlamak, hafıza durumuyla hiç ilgisi olmayan **ikinci bir engel** eklerdi:
    ///   kartın kaç kez görüldüğü zaten biliniyor ve o bilgi yanlış değil — yanlış olan,
    ///   biriken zorluğun kartı öğrenilemez hale getirmesi. `minimumReviews` "tek şanslı
    ///   cevaptan hakimiyet çıkarma" diye var; defalarca unutulmuş bir kartta o şüphe zaten
    ///   yok. Sonuç: sıfırlanan kart, kararlılığı eşiği geçtiği anda kapıdan geçebilecek
    ///   durumda kalıyor.
    /// - **`dueAt` ve `lastReviewedAt`.** Sıfırlama unutmanın hemen ardından uygulanıyor;
    ///   planlayıcının o cevap için verdiği kısa vade zaten "yakında yeniden öğret" demek.
    func resettingMemoryState() -> LatvianMemoryCard {
        let fresh = LatvianMemoryCard.new()
        var reset = self
        reset.stability = fresh.stability
        reset.difficulty = fresh.difficulty
        return reset
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

/// Takılan kartın sıfırlanma kuralı. Anki'nin "Forget"i, planlayıcı tarafında.
///
/// ## Neden ders kurgusu değil de planlayıcı
///
/// FSRS'te zorluk tek yönlü bir mandal: her unutma `+1.72`, doğru cevabın ortalamaya
/// dönüş ağırlığı ise `0.01`. Kart `D = 10`'a dayandığında kararlılık kazancındaki
/// `(11 − D)` çarpanı 1'e iniyor ve kart doğru cevaplandıkça milimetre büyüyüp her
/// yanlışta 1-2 güne düşerek orada kalıyor. **Hangi soruyu sorduğumuz `D`'yi
/// düşürmüyor** — ders kurgusundaki kurtarma payı ölçüldü, kapsamayı 0.61'den 0.74'e
/// taşıdı ve orada tıkandı (bkz. `.superpowers/sdd/p2-task-7-report.md`). Mandalı
/// açabilecek tek yer planlayıcının kendisi.
///
/// ## Teşhis ödünç alınıyor, yeniden yazılmıyor
///
/// Takılma tanımı tek bir yerde duruyor: `LatvianLessonBuilder.isLeech(card:)`
/// (defalarca unutulmuş **ve** hâlâ kalıcı olamamış). Buraya ikinci bir tanım yazmak,
/// zamanla ders kurgusunun kurtarmaya aldığı kartlarla planlayıcının sıfırladığı
/// kartların ayrışması demek olurdu.
///
/// ## Tetik: sıfırlama yalnızca **yeni bir unutmayla** geliyor
///
/// İki koşul birden: kart bu cevaptan **önce** zaten takılmış olmalı ve bu cevap
/// gerçekten yeni bir unutma kaydetmeli (`lapseCount` artmalı). Sebepleri ayrı ayrı:
///
/// - **Doğru cevapta sıfırlanmıyor**, çünkü sıfırlama kararlılığı sıfıra çeker;
///   öğrencinin az önce kazandığı kararlılığı geri almak açık bir zarar olurdu.
/// - **Teşhis cevaptan öncesine bakıyor**, çünkü her unutma kararlılığı zaten eşiğin
///   altına çökertir; sonraki duruma bakmak, iyi öğrenilmiş (S = 30 gün) ama geçmişte
///   dört kez unutulmuş bir kartı da tek bir hatayla sıfırlardı. Öncesine bakmak,
///   ders kurgusunun soruyu sorarken gördüğü durumla aynı: "zaten takılmıştı ve bir
///   kez daha unutuldu".
///
/// ## Mandala karşı mandal: sıfırlamalar aralıklı
///
/// Her unutmada sıfırlamak, kartı kalıcı olarak taze durumda tutar ve öğrenmenin
/// kendisini silerdi — biriken kararlılık asla kalıcılığa dönüşemezdi. Kural bu yüzden
/// unutma sayacına bağlı: kart, takılma eşiğinden sonra **her `lapseSpacing` unutmada
/// bir** sıfırlanabiliyor. Sayaç sıfırlamada korunduğu için (bkz.
/// `resettingMemoryState`) aralık kendiliğinden ilerliyor; ayrı bir "son sıfırlama"
/// alanı gerekmiyor, dolayısıyla kalıcı kayıt biçimi de değişmiyor.
enum LatvianLeechReset {
    /// İki sıfırlama arasında geçmesi gereken unutma sayısı: iki, yani "her unutmada
    /// değil, unutmaların yarısında".
    ///
    /// Alt sınır tasarım gereği: bire indirmek sıfırlamayı takılan kartın **her**
    /// unutmasına bağlar ve o kartın zorluğunu kalıcı olarak taze değerde dondurur —
    /// yani FSRS'in zorluk sinyali o kart için tamamen silinir. Benzetim bu bedeli
    /// göremez (benzetilen öğrencinin hata oranı kartın zorluğundan bağımsız, sabit bir
    /// sayı), gerçek öğrencide ise zor kelime gerçekten zordur. İki, kartın iki sıfırlama
    /// arasında tam bir unutma-toparlanma turunu kendi başına geçirmesini şart koşuyor.
    ///
    /// Üst sınır ölçümle: 20 tohumluk taramada gerçek FSRS altında ikinci sahnenin
    /// açıldığı koşu sayısı (%17 hata) aralık 2'de 20/20, 3'te 12/20, 4'te 8/20, 8'de
    /// 1/20'ye iniyor. Aralık büyüdükçe mandal ikinci kez kapanmaya vakit buluyor ve
    /// sıfırlama tek seferlik bir müdahaleye dönüşüyor.
    static let lapseSpacing = 2

    /// Bu cevabın ardından kartın hafıza durumu sıfırlanmalı mı.
    static func isDue(previous: LatvianMemoryCard, updated: LatvianMemoryCard) -> Bool {
        guard updated.lapseCount > previous.lapseCount else { return false }
        guard LatvianLessonBuilder.isLeech(card: previous) else { return false }
        // `isLeech` zaten eşiği garantiliyor; negatif kalan üretilemesin diye açık.
        let sinceThreshold = previous.lapseCount - LatvianLessonBuilder.leechLapseThreshold
        return sinceThreshold >= 0 && sinceThreshold % lapseSpacing == 0
    }

    /// Gerekiyorsa sıfırlanmış kartı, gerekmiyorsa kartı olduğu gibi döner.
    /// Her `LatvianScheduler` gerçeklemesi sonucunu buradan geçirmek zorunda.
    static func applied(previous: LatvianMemoryCard, updated: LatvianMemoryCard) -> LatvianMemoryCard {
        isDue(previous: previous, updated: updated) ? updated.resettingMemoryState() : updated
    }
}

/// Bir cevabı kartın yeni hafıza durumuna çeviren planlayıcı.
///
/// **Sözleşme:** her gerçekleme, döndürmeden hemen önce sonucu
/// `LatvianLeechReset.applied(previous:updated:)` üzerinden geçirir. Kural planlayıcının
/// kendi içinde durduğu için çağıranın bir şey yapması gerekmiyor ve iki planlayıcı da
/// aynı davranışı gösteriyor; testler yalnızca yer tutucuyu bağladığından bu, kuralın
/// sınanabilir olmasının da şartı.
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
        return LatvianLeechReset.applied(previous: card, updated: updated)
    }
}
