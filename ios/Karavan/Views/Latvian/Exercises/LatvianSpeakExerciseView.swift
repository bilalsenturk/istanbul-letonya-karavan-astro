import SwiftUI

/// `speak` için telaffuz görünümü.
///
/// Motor, sesi olmayan kelimeye telaffuz sorusu üretmiyor; ama **tanımanın**
/// hazır olması ayrı bir şey. Cihazda `lv-LV` tanıyıcısı olmayabilir, izin
/// kapalı olabilir, tanıma ders ortasında düşebilir. Üçünde de aynı şey oluyor:
/// hata Türkçe olarak görünüyor ve altında yazarak gönderme alanı açılıyor —
/// öğrenci cevaplayamadığı bir soruda kilitli kalmıyor.
struct LatvianSpeakExerciseView: View {
    let exercise: LatvianExercise
    @ObservedObject var audio: LatvianAudioStore
    @ObservedObject var feedback: LatvianFeedback
    let isLocked: Bool
    let onAnswerReady: (LatvianAnswer?) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var recognizer = LatvianSpeechRecognizer()
    @State private var typed = ""
    @State private var loadedId: String?
    @State private var shakeTrigger = 0

    private var target: String {
        if case .speaking(let value) = exercise.content { return value }
        return ""
    }

    /// Gönderilecek metin: mikrofon bir şey duyduysa o, yoksa yazılan.
    private var spoken: String {
        let heard = recognizer.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return heard.isEmpty ? typed.trimmingCharacters(in: .whitespacesAndNewlines) : heard
    }

    private var isAnswerCorrect: Bool {
        LatvianGrader.grade(exercise: exercise, answer: .spoken(transcript: spoken)).isCorrect
    }

    /// Mikrofon yolu kapalıysa yazma alanı açılıyor.
    private var needsFallback: Bool {
        !recognizer.isSupported || recognizer.errorText != nil
    }

    /// Kapalı bir mikrofon düğmesi tek başına sebebini söylemiyordu.
    private var noticeText: String? {
        if let errorText = recognizer.errorText { return errorText }
        guard !recognizer.isSupported else { return nil }
        return "Bu cihazda Letonca konuşma tanıma yok. Söyleyeceğini yazarak gönderebilirsin."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LatvianPromptText(text: exercise.prompt)

            LatvianCarrierCard(text: target, size: 30)

            if let audioId = exercise.audioId {
                LatvianListenButton(audioId: audioId, audio: audio, feedback: feedback, title: "Örneği dinle")
            }

            micButton

            if let noticeText {
                Label(noticeText, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if needsFallback { fallbackField }
            if !spoken.isEmpty { heardCard }
        }
        .latvianShake(trigger: shakeTrigger)
        .onAppear(perform: syncExercise)
        .onChange(of: exercise.id) { _, _ in syncExercise() }
        .onChange(of: recognizer.transcript) { _, _ in publish() }
        .onChange(of: typed) { _, _ in publish() }
        .onChange(of: isLocked) { _, locked in
            guard locked else { return }
            recognizer.stop()
            if !isAnswerCorrect { shakeTrigger += 1 }
        }
        // Ders ekranından çıkarken mikrofon açık kalmasın; `stop()` ses
        // oturumunu da eski hâline döndürüyor.
        .onDisappear { recognizer.stop() }
    }

    // MARK: - Mikrofon

    private var micButton: some View {
        Button {
            // `allowsHitTesting` dokunuşu keser ama VoiceOver'ın "etkinleştir"i
            // eyleme yine ulaşabiliyor; kilitliyken mikrofon açılmamalı.
            guard !isLocked, recognizer.isSupported else { return }
            feedback.tap()
            if recognizer.isRecording { recognizer.stop() } else { recognizer.start() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: recognizer.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 18, weight: .bold))
                Text(micTitle)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(recognizer.isSupported ? Color.white : Theme.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(micBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(recognizer.isRecording ? 1.02 : 1)
            .animation(
                LatvianMotion.adaptive(LatvianMotion.pop, reduceMotion: reduceMotion),
                value: recognizer.isRecording
            )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isLocked && recognizer.isSupported)
        .accessibilityLabel(recognizer.isRecording ? "Kaydı durdur" : "Konuşmaya başla")
    }

    private var micTitle: String {
        if !recognizer.isSupported { return "Konuşma tanıma yok" }
        return recognizer.isRecording ? "Dinliyorum… durdurmak için dokun" : "Konuş"
    }

    private var micBackground: AnyShapeStyle {
        guard recognizer.isSupported else { return AnyShapeStyle(Theme.panel) }
        return recognizer.isRecording ? AnyShapeStyle(Theme.bad) : AnyShapeStyle(Theme.gradWarm)
    }

    // MARK: - Duyulan

    private var heardCard: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Duyduğum")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Text(spoken)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isLocked {
                Image(systemName: isAnswerCorrect ? LatvianAnswerMark.correct.symbol : LatvianAnswerMark.wrong.symbol)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(isAnswerCorrect ? Theme.ok : Theme.bad)
            }
        }
        .padding(14)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(heardBorder, lineWidth: isLocked ? 2 : 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var heardBorder: Color {
        guard isLocked else { return Theme.line }
        return isAnswerCorrect ? Theme.ok : Theme.bad
    }

    // MARK: - Yazarak gönderme

    private var fallbackField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Söyleyeceğini yazabilirsin")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.dim)
            TextField("Letonca yaz", text: $typed)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
                .tint(Theme.c3)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .disabled(isLocked)
                .padding(14)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.line, lineWidth: 1)
                )
                .accessibilityLabel("Söyleyeceğini yaz")
        }
    }

    // MARK: - Cevap

    private func publish() {
        let value = spoken
        onAnswerReady(value.isEmpty ? nil : .spoken(transcript: value))
    }

    private func syncExercise() {
        guard loadedId != exercise.id else { return }
        loadedId = exercise.id
        typed = ""
        // `reset()` mikrofonu durduruyor ve metni siliyor; `transcript`
        // değişimi cevabı kendiliğinden `nil`'e çekiyor.
        recognizer.reset()
    }
}
