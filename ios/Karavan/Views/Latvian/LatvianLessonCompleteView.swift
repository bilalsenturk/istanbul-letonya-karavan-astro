import ConfettiSwiftUI
import SwiftUI

/// Ders sonu ekranı. Üç sayı sırayla sayılıyor: XP, doğruluk, gün serisi.
///
/// Başarısız ders (can bitti) **bitmiş ders sayılmıyor**: konfeti yok, kutlama
/// sesi yok, seri yok — sayılar animasyonsuz yerine oturuyor. Aynı ekranın iki
/// hâli olması bilinçli; çağıranın iki ayrı ekran arasında seçim yapması
/// gerekmiyor, `LatvianLessonOutcome.isFailed` doğrudan buraya geçiyor.
struct LatvianLessonCompleteView: View {
    let xp: Int
    /// `0...1`.
    let accuracy: Double
    let streakDays: Int
    let streakExtended: Bool
    var isFailed: Bool = false
    @ObservedObject var feedback: LatvianFeedback
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var confetti = 0
    @State private var shownXP = 0
    @State private var shownAccuracy = 0
    @State private var shownStreak = 0
    /// "Devam"a iki kez dokunulursa çağıran ekranı iki kez değiştirmesin.
    @State private var didLeave = false

    /// Sayma bir kaydırıcı değil bir cırcır: adım sayısı sınırlı, çünkü XP tıkı
    /// puan başına çalıyor ve 160 XP'lik bir ders 160 ses demekti.
    private static let maxCountSteps = 14
    private static let countDuration: TimeInterval = 0.85

    private var accuracyPercent: Int { Int((min(max(accuracy, 0), 1) * 100).rounded()) }

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)

            mascot

            VStack(spacing: 8) {
                Text(isFailed ? "Canların bitti" : "Ders tamam!")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                if isFailed {
                    Text("Yanlış yaptığın kelimeler bir sonraki derste yeniden karşına çıkacak.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 32)
                }
            }

            stats

            Spacer(minLength: 12)

            doneButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
        .task { await runCelebration() }
    }

    // MARK: - Parçalar

    @ViewBuilder
    private var mascot: some View {
        let lynx = LatvianMascot(mood: isFailed ? .wrong : .celebrate, size: 132)
        if isFailed || reduceMotion {
            lynx
        } else {
            lynx.confettiCannon(
                trigger: $confetti,
                num: 42,
                colors: [Theme.c1, Theme.c2, Theme.c3, Theme.c4, Theme.ok, Theme.warn],
                confettiSize: 11,
                radius: 320,
                // Haptic bizde: paketinki kullanıcının "titreşim kapalı" ayarını
                // tanımıyor ve aynı çarpmayı iki kez tetikliyor.
                hapticFeedback: false
            )
            // Top, maskotu esnek yükseklikte bir `ZStack`'e sarıyor; sarmadan
            // bırakıldığında yerleşimdeki payı maskottan büyük çıkıyor ve
            // başlık aşağı kayıyordu. Çerçeve kırpmıyor: konfeti dışarı çıkıyor.
            .frame(width: 132, height: 132)
        }
    }

    private var stats: some View {
        HStack(spacing: 12) {
            stat(value: "\(shownXP)", label: "XP", symbol: "bolt.fill", tone: Theme.c1)
            stat(value: "%\(shownAccuracy)", label: "Doğruluk", symbol: "target", tone: Theme.c4)
            stat(value: "\(shownStreak)", label: "Gün seri", symbol: "flame.fill", tone: Theme.c2)
        }
        .padding(.horizontal, 20)
    }

    private func stat(value: String, label: String, symbol: String, tone: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tone)
            Text(value)
                .font(.system(size: 25, weight: .black, design: .rounded))
                .foregroundStyle(tone)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 6)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }

    private var doneButton: some View {
        Button(action: leave) {
            Text("Devam")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.bg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(Theme.ok, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(20)
        .accessibilityLabel("Derse devam et")
    }

    // MARK: - Kutlama

    private func leave() {
        guard !didLeave else { return }
        didLeave = true
        onDone()
    }

    /// `.task` görünüm kaybolunca iptal ediliyor. Her bekleme iptali **geri
    /// dönerek** karşılıyor: `try?` ile yutulsaydı zincir devam eder, öğrenci
    /// "Devam"a bastıktan sonra seri sesi çalardı.
    @MainActor
    private func runCelebration() async {
        guard !isFailed else {
            shownXP = xp
            shownAccuracy = accuracyPercent
            shownStreak = streakDays
            return
        }

        feedback.lessonComplete()

        if !reduceMotion {
            // Konfeti topu ilk görünüşünden önceki tetiği yok sayıyor; bir kare
            // beklemeden artırılan sayaç hiç patlamıyordu.
            guard await pause(0.12) else { return }
            confetti += 1
        }

        guard await countUp(to: xp, tick: true, set: { shownXP = $0 }) else { return }
        guard await pause(0.22) else { return }
        guard await countUp(to: accuracyPercent, tick: false, set: { shownAccuracy = $0 }) else { return }
        guard await pause(0.22) else { return }
        guard await countUp(to: streakDays, tick: false, set: { shownStreak = $0 }) else { return }

        if streakExtended { feedback.streakUp() }
    }

    /// - Returns: Tamamlandıysa `true`, iptal edildiyse `false`.
    @MainActor
    private func countUp(to target: Int, tick: Bool, set: (Int) -> Void) async -> Bool {
        guard target > 0 else {
            set(0)
            return true
        }
        guard !reduceMotion else {
            withAnimation(LatvianMotion.reduced) { set(target) }
            return true
        }

        let steps = min(target, Self.maxCountSteps)
        for index in 1...steps {
            // Adım başına yay yok: 60 ms arayla kurulan yaylar üst üste binip
            // sayıyı bulanıklaştırıyor. Sayının kendisi zaten hareket.
            set(target * index / steps)
            if tick { feedback.xpTick() }
            guard await pause(Self.countDuration / Double(steps)) else { return false }
        }
        return true
    }

    @MainActor
    private func pause(_ seconds: TimeInterval) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(seconds))
            return true
        } catch {
            return false
        }
    }
}

#Preview("Ders tamam") {
    LatvianLessonCompleteView(
        xp: 165, accuracy: 0.86, streakDays: 7, streakExtended: true,
        feedback: LatvianFeedback(), onDone: {}
    )
}

#Preview("Canlar bitti") {
    LatvianLessonCompleteView(
        xp: 40, accuracy: 0.44, streakDays: 3, streakExtended: false,
        isFailed: true, feedback: LatvianFeedback(), onDone: {}
    )
}
