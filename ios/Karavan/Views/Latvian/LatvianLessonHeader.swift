import SwiftUI

/// Ders ekranının üst şeridi: maskot, ilerleme çubuğu, kalan can ve kombo rozeti.
///
/// Ayrı dosyada, çünkü kabuk (`LatvianLessonView`) 250 satır sınırını bununla
/// birlikte aşıyordu. Durumu yok: dördü de dışarıdan veriliyor, dolayısıyla
/// oturumla ayrışması mümkün değil.
struct LatvianLessonHeader: View {
    let mood: LatvianMascotMood
    /// `0...1`. Oturum zaten bu aralıkta üretiyor; yine de kırpılıyor çünkü
    /// negatif ya da 1'i aşan bir değer çubuğu görünür biçimde bozardı.
    let progress: Double
    let heartsLeft: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clampedProgress: Double { min(max(progress, 0), 1) }

    var body: some View {
        HStack(spacing: 14) {
            LatvianMascot(mood: mood, size: 48)
            progressBar
            hearts
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    // MARK: - İlerleme

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.panel)
                Capsule()
                    .fill(Theme.gradWarm)
                    .frame(width: geometry.size.width * clampedProgress)
            }
        }
        .frame(height: 12)
        .animation(motion(LatvianMotion.slide), value: clampedProgress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ders ilerlemesi")
        .accessibilityValue("yüzde \(Int((clampedProgress * 100).rounded()))")
    }

    // MARK: - Can

    private var hearts: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(heartsLeft > 0 ? Theme.bad : Theme.muted)
            Text("\(heartsLeft)")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText(countsDown: true))
                .monospacedDigit()
        }
        .animation(motion(LatvianMotion.pop), value: heartsLeft)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(heartsLeft) can kaldı")
    }

    private func motion(_ base: Animation) -> Animation {
        LatvianMotion.adaptive(base, reduceMotion: reduceMotion)
    }
}

#Preview("Ders şeridi") {
    VStack(spacing: 30) {
        LatvianLessonHeader(mood: .idle, progress: 0, heartsLeft: 5)
        LatvianLessonHeader(mood: .thinking, progress: 0.45, heartsLeft: 3)
        LatvianLessonHeader(mood: .wrong, progress: 0.9, heartsLeft: 0)
    }
    .padding(.vertical, 40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.bg)
}
