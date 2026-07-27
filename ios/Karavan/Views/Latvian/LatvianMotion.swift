import SwiftUI

/// Letonca ders arayüzünün bütün zamanlamaları tek yerde.
///
/// Görünümlerde satır arası `.animation(.spring(response: 0.31…))` yazılmaz:
/// her hareket buradaki bir sabitten geçer. Böylece ritmi değiştirmek için tek
/// dosyaya dokunmak yeter ve ekranlar birbirinden farklı hızlarda oynamaz.
///
/// Reduce Motion (Ayarlar → Erişilebilirlik → Hareket) açıkken hareket
/// **kaybolmaz, sadeleşir**: yaylı ve sıçramalı eğrilerin yerini kısa bir
/// `easeOut` alır, yatay sarsılmanın yerini bir sönme alır. Hiçbir geri bildirim
/// büsbütün ortadan kalkmaz — yanlış cevabın görünür bir karşılığı hep olur.
enum LatvianMotion {

    // MARK: - Eğriler

    /// Kart seçimi, buton basımı — kısa ve kararlı.
    static let snap = Animation.spring(response: 0.30, dampingFraction: 0.62)

    /// Doğru cevapta büyüyüp yerine oturma — hafif sıçramalı.
    static let pop = Animation.spring(response: 0.34, dampingFraction: 0.55)

    /// Alttan gelen panel — sıçramasız, ağır.
    static let slide = Animation.spring(response: 0.42, dampingFraction: 0.82)

    /// XP/seri sayaçlarının sayması.
    static let count = Animation.easeOut(duration: 0.9)

    /// Reduce Motion açıkken yukarıdaki yaylı eğrilerin yerine geçen sade eğri.
    static let reduced = Animation.easeOut(duration: 0.22)

    /// Reduce Motion açıksa `reduced`, değilse verilen eğri.
    ///
    /// Kullanımı:
    /// ```swift
    /// @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// …
    /// .animation(LatvianMotion.adaptive(.pop, reduceMotion: reduceMotion), value: mood)
    /// ```
    static func adaptive(_ base: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : base
    }

    // MARK: - Sarsılma

    /// Yanlış cevapta kartın sırayla geçeceği yatay konumlar (pt).
    ///
    /// Son değerin 0 olması zorunlu: dizi yarıda kesilmese bile kartın kendi
    /// yerine dönmesini bu son kare sağlıyor.
    static let shakeOffsets: [CGFloat] = [-10, 9, -6, 3, 0]

    /// İki kare arası süre. Toplam sarsılma `shakeOffsets.count * shakeStep`.
    static let shakeStep: TimeInterval = 0.055

    /// Reduce Motion açıkken sarsılma yerine kullanılan sönmenin dip saydamlığı.
    static let reducedDimOpacity: Double = 0.45

    /// Sönmenin iniş süresi; kalkışı bunun iki katı (yumuşak dönüş).
    static let reducedDimDuration: TimeInterval = 0.11
}

/// Yanlış cevapta kartı yatay sarsan değiştirici.
///
/// Üç şeye dikkat edilerek yazıldı:
///
/// 1. **İlk görünüşte tetiklenmez.** `onChange(of:)` başlangıç değerini
///    dinlemediği için ekran açılır açılmaz kart titremez. (`task(id:)`
///    kullanılsaydı tetiklenirdi — bilerek `onChange`.)
/// 2. **Kesilebilir.** Hızlı cevap veren biri arka arkaya iki yanlış yapabilir;
///    yeni tetik önceki diziyi iptal eder, `DispatchQueue.asyncAfter` ile
///    üst üste binen ve iptal edilemeyen zamanlayıcılar bırakmaz.
/// 3. **Sızdırmaz.** Tek bir `Task` tutulur, görünüm kaybolunca iptal edilir ve
///    konum sıfırlanır.
struct LatvianShake: ViewModifier {
    /// Her artışta bir sarsılma. Genelde `session.wrongCount` gibi bir sayaç.
    let trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var dim: Double = 1
    @State private var runner: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .opacity(dim)
            .onChange(of: trigger) { _, _ in start() }
            .onDisappear {
                runner?.cancel()
                runner = nil
                offset = 0
                dim = 1
            }
    }

    private func start() {
        runner?.cancel()
        runner = Task { @MainActor in
            if reduceMotion {
                await fade()
            } else {
                await shake()
            }
        }
    }

    @MainActor
    private func shake() async {
        // Az önce Reduce Motion'dan çıkılmış olabilir: sönmüş kalmasın.
        dim = 1
        for value in LatvianMotion.shakeOffsets {
            withAnimation(.linear(duration: LatvianMotion.shakeStep)) { offset = value }
            do {
                try await Task.sleep(for: .seconds(LatvianMotion.shakeStep))
            } catch {
                // İptal: yerine geçen dizi ya da `onDisappear` konumu düzeltir.
                return
            }
        }
        offset = 0
    }

    @MainActor
    private func fade() async {
        // Az önce Reduce Motion'a girilmiş olabilir: kart yamuk kalmasın.
        offset = 0
        withAnimation(.easeOut(duration: LatvianMotion.reducedDimDuration)) {
            dim = LatvianMotion.reducedDimOpacity
        }
        do {
            try await Task.sleep(for: .seconds(LatvianMotion.reducedDimDuration))
        } catch {
            dim = 1
            return
        }
        withAnimation(.easeIn(duration: LatvianMotion.reducedDimDuration * 2)) { dim = 1 }
    }
}

extension View {
    /// `trigger` her arttığında kartı sarsar (Reduce Motion'da söndürür).
    func latvianShake(trigger: Int) -> some View {
        modifier(LatvianShake(trigger: trigger))
    }
}
