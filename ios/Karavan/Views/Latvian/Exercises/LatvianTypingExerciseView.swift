import SwiftUI

/// `dictation` için yazma görünümü.
///
/// Türkçe klavyede `ā ē ī ū č ģ ķ ļ ņ š ž` yok. Notlayıcı diakritikleri katladığı
/// için `latviesu` yazan öğrenci ceza yemiyor; bunu söyleyen not ve isteyenin
/// doğru yazabilmesi için klavye üstündeki harf şeridi ortak bileşende
/// (`LatvianDiacriticInput`). Not alanın **üstünde**: altındayken klavye açıkken
/// kaydırılabilir alanın dışında kalıyordu.
///
/// Cevap paneli açılınca klavye bilerek kapanıyor: açık kalsaydı ekranın alt
/// yarısını kaplayıp panelin kendisini gizlerdi.
struct LatvianTypingExerciseView: View {
    let exercise: LatvianExercise
    @ObservedObject var audio: LatvianAudioStore
    @ObservedObject var feedback: LatvianFeedback
    let isLocked: Bool
    let onAnswerReady: (LatvianAnswer?) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var text = ""
    @State private var loadedId: String?
    @State private var shakeTrigger = 0
    @FocusState private var isFocused: Bool

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isAnswerCorrect: Bool {
        LatvianGrader.grade(exercise: exercise, answer: .text(text)).isCorrect
    }

    private var fieldBorder: Color {
        guard isLocked else { return isFocused ? Theme.c3 : Theme.line }
        return isAnswerCorrect ? Theme.ok : Theme.bad
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LatvianPromptText(text: exercise.prompt)

            if let audioId = exercise.audioId {
                LatvianListenButton(audioId: audioId, audio: audio, feedback: feedback, title: "Tekrar dinle")
            }

            if let carrier = exercise.carrier {
                LatvianCarrierCard(text: carrier, size: 22)
            }

            // Not ve alan tek bir öbek: aradaki 8 pt, notun alanın başlığı gibi
            // okunmasını sağlıyor. 18 pt'lik gövde aralığı ikisini ayırırdı.
            VStack(alignment: .leading, spacing: 8) {
                LatvianDiacriticInput(text: $text, feedback: feedback)
                field
            }
        }
        .latvianShake(trigger: shakeTrigger)
        .task(id: exercise.id) { await focusAfterAppearing() }
        .onAppear(perform: syncExercise)
        .onChange(of: exercise.id) { _, _ in syncExercise() }
        .onChange(of: text) { _, value in
            onAnswerReady(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .text(value))
        }
        .onChange(of: isLocked) { _, locked in
            guard locked else { return }
            isFocused = false
            if !isAnswerCorrect { shakeTrigger += 1 }
        }
    }

    // MARK: - Alan

    private var field: some View {
        HStack(spacing: 10) {
            TextField("Letonca yaz", text: $text)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
                .tint(Theme.c3)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isFocused)
                .disabled(isLocked)
                .accessibilityLabel("Cevabını yaz")

            if isLocked {
                Image(systemName: isAnswerCorrect ? LatvianAnswerMark.correct.symbol : LatvianAnswerMark.wrong.symbol)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(isAnswerCorrect ? Theme.ok : Theme.bad)
                    .accessibilityLabel(isAnswerCorrect ? LatvianAnswerMark.correct.label : LatvianAnswerMark.wrong.label)
            }
        }
        .padding(16)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(fieldBorder, lineWidth: 2)
        )
        .animation(LatvianMotion.adaptive(LatvianMotion.snap, reduceMotion: reduceMotion), value: isLocked)
    }

    // MARK: - Soru değişimi

    private func syncExercise() {
        guard loadedId != exercise.id else { return }
        let hadAnswer = !trimmed.isEmpty
        loadedId = exercise.id
        text = ""
        if hadAnswer { onAnswerReady(nil) }
    }

    /// Odak, görünüm yerleşmeden verilirse klavye açılmıyor. Gecikme `Task` ile:
    /// ekran kapanınca iptal olur, `DispatchQueue.asyncAfter` gibi arkada
    /// iptal edilemez bir zamanlayıcı bırakmaz.
    private func focusAfterAppearing() async {
        guard !isLocked else { return }
        try? await Task.sleep(for: .milliseconds(320))
        guard !Task.isCancelled, !isLocked else { return }
        isFocused = true
    }
}
