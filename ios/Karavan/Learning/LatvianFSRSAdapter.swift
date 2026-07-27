import Foundation
import FSRS

/// `swift-fsrs` (open-spaced-repetition, MIT) kütüphanesini motorun beklediği
/// `LatvianScheduler` arayüzüne bağlar.
///
/// **Bu dosya `ios/Tests/run-latvian-check.sh` kaynak listesine eklenmez.** Test koşucusu
/// motoru çıplak `swiftc` ile derliyor ve paket çözümlemesi yok; testler bu yüzden
/// `LatvianDefaultScheduler` ile çalışmaya devam ediyor. `Learning/` altında FSRS'i tanıyan
/// tek dosya burası — kütüphane tipleri (`Card`, `Rating`, `Status`) bu dosyanın dışına çıkmaz.
///
/// ## Sürüm notu
///
/// Paket `4.1.0`'a sabitli. En son etiket `5.0.0` ama orada `public` işaretleri eksik kalmış:
/// `FSRS` sınıfının `init`'i, `repeat`/`next` metotları, `IPreview`'nun alt simgesi ve
/// `RecordLogItem.card` alanı `internal`. Modül dışından ne motor kurulabiliyor ne de sonuç
/// okunabiliyor. `4.1.0` tam `public` yüzeye sahip ve aynı FSRS v4.5 algoritmasını uyguluyor.
///
/// ## Durum (`Status`) neden saklanmıyor
///
/// `LatvianMemoryCard` kalıcı ve `swiftc` ile derlenen bir model; içine kütüphaneye ait bir
/// alan konamaz. FSRS'in `Status` değeri bu yüzden sakladığımız alanlardan geri türetiliyor
/// (bkz. `status(for:)`). Türetim `repeat()`'in davranışını birebir koruyor: kütüphanede
/// `.learning` ile `.relearning` aynı dalda işleniyor, aralarındaki tek fark taşınan etiket.
struct LatvianFSRSScheduler: LatvianScheduler {
    /// Hedeflenen hatırlama oranı vb. varsayılan FSRS parametreleri.
    /// Motor her çağrıda kuruluyor: `FSRS` tipi `Sendable` işaretli değil, saklanan bir kopya
    /// bu yapıyı da eşzamanlılık denetiminde şüpheli hale getirirdi. Kurulum maliyeti
    /// 17 elemanlı bir dizi kopyası, ölçülebilir değil.
    private var engine: FSRS { FSRS() }

    /// Bir cevabın ardından kartın yeni hafıza durumu.
    ///
    /// Gizli saat yok: `now` doğrudan kütüphaneye geçiyor, `Date()` çağrılmıyor.
    func review(card: LatvianMemoryCard, rating: LatvianRating, now: Date) -> LatvianMemoryCard {
        let outcomes = engine.repeat(card: fsrsCard(from: card, now: now), now: now)

        // Sonuç sözlüğünde derece bulunmalı; bulunmazsa ya da kütüphane bozuk bir hafıza
        // durumu döndürürse yedek planlayıcı devreye giriyor. Böylece `dueAt > now`,
        // `stability > 0` ve sonlu sayı güvenceleri her yolda korunuyor.
        guard let scheduled = outcomes[fsrsRating(rating)]?.card,
              scheduled.stability.isFinite, scheduled.stability > 0,
              scheduled.difficulty.isFinite,
              scheduled.due > now else {
            return LatvianDefaultScheduler().review(card: card, rating: rating, now: now)
        }

        var updated = card
        updated.stability = scheduled.stability
        updated.difficulty = scheduled.difficulty
        updated.dueAt = scheduled.due
        updated.lastReviewedAt = now
        // Kütüphane `reps`'i çağrı başına bir artırıyor; `max` yalnızca sayaçların hiçbir
        // durumda geri gitmemesini garantiliyor.
        updated.reviewCount = max(card.reviewCount + 1, scheduled.reps)
        // FSRS "lapse"i yalnızca `review` durumundaki bir kart unutulduğunda sayıyor;
        // öğrenme adımlarındaki yanlışlar sayaca girmiyor. Kütüphanenin tanımı korunuyor.
        updated.lapseCount = max(card.lapseCount, scheduled.lapses)
        return updated
    }

    // MARK: - Dönüşüm

    /// Kendi kartımızdan kütüphanenin kartını kurar.
    ///
    /// `elapsedDays` ve `scheduledDays` sıfır veriliyor: ilkini `repeat()` her çağrıda
    /// `lastReview`'dan yeniden hesaplıyor, ikincisi yalnızca kütüphanenin attığı
    /// `ReviewLog`'a yazılıyor ve planlama matematiğine girmiyor.
    private func fsrsCard(from card: LatvianMemoryCard, now: Date) -> Card {
        Card(
            due: card.dueAt,
            stability: card.stability,
            difficulty: card.difficulty.isFinite ? card.difficulty : 5,
            elapsedDays: 0,
            scheduledDays: 0,
            reps: max(0, card.reviewCount),
            lapses: max(0, card.lapseCount),
            status: status(for: card),
            // Yeni kartta kullanılmıyor (`repeat()` `elapsedDays`'i sıfırlıyor); yine de
            // kütüphanenin varsayılanı `Date()` olduğu için açıkça `now` veriliyor.
            lastReview: card.lastReviewedAt ?? now
        )
    }

    /// FSRS durumunu sakladığımız alanlardan türetir.
    ///
    /// - Hiç tekrar görmemiş ya da hafıza durumu anlamsız (kararlılık pozitif değil) kart: `.new`.
    /// - Son planlamada gün ölçeğinde aralık almış kart mezun olmuştur: `.review`.
    /// - Daha kısa aralık almışsa hâlâ öğrenme adımlarındadır: `.learning`.
    ///
    /// Türetim kendi kendini tutarlı kılıyor: kütüphane öğrenme adımlarına dakika ölçeğinde
    /// (`+1`, `+5`, `+10` dk), mezun kartlara gün ölçeğinde vade veriyor. Dolayısıyla bir
    /// sonraki okumada aynı durum geri çıkıyor. `.relearning` ayrı ayırt edilmiyor;
    /// `repeat()` içinde `.learning` ile aynı dalda işlendiğinden sonuç değişmiyor.
    private func status(for card: LatvianMemoryCard) -> Status {
        guard let lastReviewedAt = card.lastReviewedAt,
              card.reviewCount > 0,
              card.stability.isFinite, card.stability > 0 else { return .new }
        return card.dueAt.timeIntervalSince(lastReviewedAt) >= 86_400 ? .review : .learning
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
