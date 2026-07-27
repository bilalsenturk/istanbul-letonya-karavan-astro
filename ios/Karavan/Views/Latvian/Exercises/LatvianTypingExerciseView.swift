import SwiftUI

/// `dictation` için yazma görünümü.
///
/// Türkçe klavyede `ā ē ī ū č ģ ķ ļ ņ š ž` yok. Notlayıcı diakritikleri katladığı
/// için `latviesu` yazan öğrenci ceza yemiyor; yine de klavyenin üstünde bir
/// harf şeridi duruyor — doğru yazmak isteyen yazabilsin. Şerit metnin **sonuna**
/// ekliyor: SwiftUI `TextField`'ı imleç konumunu dışarı vermiyor, soldan sağa
/// yazarken imleç zaten sonda oluyor.
///
/// Cevap paneli açılınca klavye bilerek kapanıyor: açık kalsaydı ekranın alt
/// yarısını kaplayıp panelin kendisini gizlerdi.
struct LatvianTypingExerciseView: View {
    let exercise: LatvianExercise
    @ObservedObject var audio: LatvianAudioStore
    @ObservedObject var feedback: LatvianFeedback
    let isLocked: Bool
    let onAnswerReady: (LatvianAnswer?) -> Void

    /// Letoncanın Türkçe klavyede bulunmayan harfleri.
    private static let diacritics = ["ā", "č", "ē", "ģ", "ī", "ķ", "ļ", "ņ", "š", "ū", "ž"]

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

            field

            Text("Diakritikleri yazamazsan sorun değil: \"a\" da \"ā\" sayılıyor.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .latvianShake(trigger: shakeTrigger)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                diacriticBar
            }
        }
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

    // MARK: - Harf şeridi

    /// On bir harf, 375 pt'lik ekrana kaydırmadan sığacak ölçüde.
    ///
    /// İlk denemede tuşlar 34 pt genişti ve son üçü (š ū ž) ekran dışında
    /// kalıyordu — kimse orada kaydırılacak bir şey olduğunu tahmin edemezdi.
    /// `maxWidth: .infinity` ile eşit paylaştırmak ise klavye çubuğunda
    /// çalışmıyor: `ToolbarItemGroup` genişlik teklif etmediği için şerit tek
    /// bir yumruya çöküyordu. Sabit ölçü + kaydırma, ikisinin de olmadığı hâl.
    private var diacriticBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(Self.diacritics, id: \.self) { letter in
                    Button {
                        feedback.tap()
                        text.append(letter)
                    } label: {
                        Text(letter)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.text)
                            .frame(width: 28, height: 40)
                            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Theme.line, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(letter) harfini ekle")
                }
            }
            .padding(.horizontal, 2)
        }
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
