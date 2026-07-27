import SwiftUI

/// Cevaptan sonra alttan gelen panel.
///
/// Panelin tek çıkışı düğmesi: sonraki soruya başka hiçbir yoldan geçilmiyor.
/// Kaydırarak kapatma, dışına dokunma, geri hareketi — hiçbiri yok. Sebebi
/// görgü değil muhasebe: kuyruğu yalnızca `LatvianLessonSession.advance()`
/// ilerletiyor, paneli ondan bağımsız kapatan her yol kuyrukla ekranı ayırırdı.
///
/// Panel oturuma bakmıyor; gönderim anında dondurulmuş `LatvianAnswerReview`'ü
/// çiziyor.
struct LatvianAnswerPanel: View {
    let isCorrect: Bool
    let correctAnswer: String
    let explanation: String?
    /// Kombo eşiği geçildiyse üst üste doğru sayısı.
    ///
    /// Rozet başta üst şeritte yüzüyordu ve orada sorunun ilk kartının üstüne
    /// biniyordu (ekran görüntüsüyle yakalandı). Buraya taşındı: öğrencinin
    /// zaten baktığı yer burası, çarpışacak bir şey yok ve panelle birlikte
    /// gidip geldiği için ayrıca bir zamanlayıcı gerekmiyor.
    let comboMilestone: Int?
    /// Bu cevap dersi bitiriyorsa düğme "Bitir" der.
    let isLastQuestion: Bool
    let onContinue: () -> Void

    private var tint: Color { isCorrect ? Theme.ok : Theme.bad }

    private var title: String { isCorrect ? "Doğru!" : "Doğru cevap" }

    private var buttonTitle: String { isLastQuestion ? "Bitir" : "Devam" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !isCorrect, !correctAnswer.isEmpty {
                Text(correctAnswer)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let explanation, !explanation.isEmpty, !isCorrect {
                Text(explanation)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            continueButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background { panelBackground }
        // Panel açılınca VoiceOver odağı buraya gelsin: doğru cevabı okumadan
        // "Devam"a basılmasın.
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(1)
    }

    // MARK: - Parçalar

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 11) {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.text)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isCorrect ? "Doğru cevap verdin" : "Yanlış. Doğrusu: \(correctAnswer)")
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)
            comboBadge
        }
    }

    @ViewBuilder
    private var comboBadge: some View {
        if let comboMilestone {
            VStack(spacing: 1) {
                Text("\(comboMilestone) üst üste")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                Text("+\(LatvianLessonSession.comboBonusXP) XP")
                    .font(.system(size: 13, weight: .black, design: .rounded))
            }
            .foregroundStyle(Theme.c1)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Theme.c1.opacity(0.16), in: Capsule())
            .overlay(Capsule().stroke(Theme.c1.opacity(0.45), lineWidth: 1))
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(comboMilestone) doğru üst üste, \(LatvianLessonSession.comboBonusXP) XP bonus"
            )
        }
    }

    private var continueButton: some View {
        Button(action: onContinue) {
            Text(buttonTitle)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                // Her iki dolgu da parlak; en yüksek kontrast koyu zemin rengi.
                .foregroundStyle(Theme.bg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(tint, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLastQuestion ? "Dersi bitir" : "Sonraki soruya geç")
        .accessibilityAddTraits(.isButton)
    }

    /// Alt kenara yapışan zemin. `ignoresSafeArea` yalnızca **zeminde**: içerik
    /// güvenli alanda kalıyor, yani "Devam" düğmesi ana ekran çubuğunun altına
    /// kaçmıyor, ama renk ekranın dibine kadar iniyor.
    private var panelBackground: some View {
        UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous)
            .fill(tint.opacity(0.13))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(tint)
                    .frame(height: 2)
            }
            .clipShape(
                UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous)
            )
            .ignoresSafeArea(edges: .bottom)
    }
}

#Preview("Cevap paneli") {
    VStack(spacing: 0) {
        Spacer()
        LatvianAnswerPanel(
            isCorrect: true, correctAnswer: "Labdien", explanation: nil,
            comboMilestone: 5, isLastQuestion: false, onContinue: {}
        )
        LatvianAnswerPanel(
            isCorrect: false, correctAnswer: "ātrā palīdzība",
            explanation: "ātrā palīdzība — ambulans",
            comboMilestone: nil, isLastQuestion: true, onContinue: {}
        )
    }
    .background(Theme.bg)
}
