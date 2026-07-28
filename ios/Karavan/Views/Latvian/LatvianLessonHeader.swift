import SwiftUI

/// Ders ekranının üst şeridi: çıkış düğmesi, maskot, ilerleme çubuğu ve kalan can.
///
/// Ayrı dosyada, çünkü kabuk (`LatvianLessonView`) 250 satır sınırını bununla
/// birlikte aşıyordu. Durumu yok: hepsi dışarıdan veriliyor, dolayısıyla
/// oturumla ayrışması mümkün değil.
struct LatvianLessonHeader: View {
    let mood: LatvianMascotMood
    /// `0...1`. Oturum zaten bu aralıkta üretiyor; yine de kırpılıyor çünkü
    /// negatif ya da 1'i aşan bir değer çubuğu görünür biçimde bozardı.
    let progress: Double
    let heartsLeft: Int
    /// Çıkış düğmesi. Onayı **soran** taraf değil: bu şerit yalnızca haber
    /// veriyor, "gerçekten çıkılsın mı" sorusu kabukta (bkz. `LatvianLessonView`).
    let onQuit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clampedProgress: Double { min(max(progress, 0), 1) }

    var body: some View {
        HStack(spacing: 12) {
            quitButton
            LatvianMascot(mood: mood, size: 48)
            progressBar
            hearts
        }
        // Baştaki pay 20 değil 8: çıkış düğmesinin 44 pt'lik dokunma kutusu
        // simgesinden geniş, 20 pt eklenince simge kenardan görünür biçimde
        // içeri kaçıyordu. Kutu 8'den başlayınca simgenin ekseni ~30 pt'ye
        // oturuyor, yani alttaki içeriğin 20 pt'lik kenarıyla hizalı duruyor.
        .padding(.leading, 8)
        .padding(.trailing, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    // MARK: - Çıkış

    /// Simge 17 pt ama kutu 44×44: dokunma hedefi Apple'ın alt sınırının altına
    /// düşerse ders ekranından çıkmak yeniden zorlaşır.
    private var quitButton: some View {
        Button(action: onQuit) {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.muted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dersten çık")
        .accessibilityHint("Dersi yarıda bırakmayı sorar.")
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
        LatvianLessonHeader(mood: .idle, progress: 0, heartsLeft: 5, onQuit: {})
        LatvianLessonHeader(mood: .thinking, progress: 0.45, heartsLeft: 3, onQuit: {})
        LatvianLessonHeader(mood: .wrong, progress: 0.9, heartsLeft: 0, onQuit: {})
    }
    .padding(.vertical, 40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.bg)
}
