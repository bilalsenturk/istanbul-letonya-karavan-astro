import SwiftUI

/// `lvToTr`, `trToLv` ve `order` için kelime bankası görünümü.
///
/// Parçalar **indeksle değil kimlikle** taşınıyor. İki sebeple:
///
/// 1. Aynı kelime bir cümlede iki kez geçebilir ("Sveiki, sveiki!"). Metni
///    kimlik saymak iki parçayı tek parça sanardı; `ForEach` biri kaybolunca
///    yanlış olanı silerdi.
/// 2. Aynı parçaya hızlıca iki kez dokunmak, ilk dokunuşun taşımasından sonra
///    ikinci dokunuşu geçersiz bir indekse yollar. Kimlikle arandığında ikinci
///    dokunuş sessizce düşüyor: ne çift ekleme ne de dizi taşması.
struct LatvianWordBankExerciseView: View {
    let exercise: LatvianExercise
    @ObservedObject var audio: LatvianAudioStore
    @ObservedObject var feedback: LatvianFeedback
    let isLocked: Bool
    let onAnswerReady: (LatvianAnswer?) -> Void

    /// Bankadaki bir parça. `id` bankanın ilk sırasından bir kez veriliyor ve
    /// parça oraya geri döndüğünde de aynı kalıyor.
    private struct Token: Identifiable, Hashable {
        let id: Int
        let text: String
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bank: [Token] = []
    @State private var chosen: [Token] = []
    @State private var loadedId: String?
    @State private var shakeTrigger = 0

    private var motion: Animation {
        LatvianMotion.adaptive(LatvianMotion.snap, reduceMotion: reduceMotion)
    }

    private var isAnswerCorrect: Bool {
        // Kendi karşılaştırmasını yazmak yerine notlayıcının kendisi soruluyor:
        // noktalama ve diakritik katlaması iki yerde ayrışmasın.
        LatvianGrader.grade(exercise: exercise, answer: .words(chosen.map(\.text))).isCorrect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LatvianPromptText(text: exercise.prompt)

            if let audioId = exercise.audioId {
                LatvianListenButton(audioId: audioId, audio: audio, feedback: feedback)
            }

            if let carrier = exercise.carrier {
                Text(carrier)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            answerTray
            bankTray
        }
        .latvianShake(trigger: shakeTrigger)
        .onAppear(perform: syncExercise)
        .onChange(of: exercise.id) { _, _ in syncExercise() }
        .onChange(of: isLocked) { _, locked in
            guard locked, !isAnswerCorrect else { return }
            shakeTrigger += 1
        }
    }

    // MARK: - Tepsiler

    private var answerTray: some View {
        LatvianFlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(chosen) { token in
                chip(token, tone: Theme.c3.opacity(0.30), border: Theme.c3.opacity(0.7)) {
                    move(token, from: .answer)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(trayBorder, lineWidth: 2)
        )
        .overlay(alignment: .leading) {
            if chosen.isEmpty {
                Text("Kelimelere dokunarak cümleyi kur")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 18)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cevabın")
        .accessibilityValue(chosen.isEmpty ? "boş" : chosen.map(\.text).joined(separator: " "))
    }

    private var bankTray: some View {
        LatvianFlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(bank) { token in
                chip(token, tone: Theme.panel, border: Theme.line) {
                    move(token, from: .bank)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kelime bankası")
    }

    private var trayBorder: Color {
        guard isLocked else { return chosen.isEmpty ? Theme.line : Theme.c3.opacity(0.6) }
        return isAnswerCorrect ? Theme.ok : Theme.bad
    }

    private func chip(
        _ token: Token,
        tone: Color,
        border: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(token.text)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(tone, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(border, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isLocked)
        .accessibilityLabel(token.text)
        .accessibilityHint(isLocked ? "" : "Yerini değiştirmek için dokun.")
    }

    // MARK: - Taşıma

    private enum Tray { case bank, answer }

    private func move(_ token: Token, from tray: Tray) {
        guard !isLocked else { return }
        switch tray {
        case .bank:
            guard let index = bank.firstIndex(of: token) else { return }
            feedback.tap()
            withAnimation(motion) {
                bank.remove(at: index)
                chosen.append(token)
            }
        case .answer:
            guard let index = chosen.firstIndex(of: token) else { return }
            feedback.tap()
            withAnimation(motion) {
                chosen.remove(at: index)
                // Banka ilk sırasına dönsün; geri alınan kelime listenin
                // sonuna düşerse öğrenci onu yeniden aramak zorunda kalıyor.
                bank.insert(token, at: bank.firstIndex { $0.id > token.id } ?? bank.count)
            }
        }
        publish()
    }

    private func publish() {
        onAnswerReady(chosen.isEmpty ? nil : .words(chosen.map(\.text)))
    }

    // MARK: - Soru değişimi

    private func syncExercise() {
        guard loadedId != exercise.id else { return }
        let hadAnswer = !chosen.isEmpty
        loadedId = exercise.id
        chosen = []
        bank = []
        if case .wordBank(let values, _) = exercise.content {
            bank = values.enumerated().map { Token(id: $0.offset, text: $0.element) }
        }
        if hadAnswer { onAnswerReady(nil) }
    }
}
