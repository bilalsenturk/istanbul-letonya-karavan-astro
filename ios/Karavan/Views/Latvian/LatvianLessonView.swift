import SwiftUI

/// Öğrencinin bütün ders boyunca içinde kaldığı ekran: ilerleme çubuğu, canlar,
/// maskot, sıradaki soru ve cevaptan sonra alttan gelen panel.
///
/// Akışın kuralları burada **değil** — hepsi `LatvianLessonSession`'da (yanlış
/// cevap kuyruğun sonuna döner, can biterse ders başarısız olur, kombo eşiği
/// ders başına bir kez öder). Bu ekran yalnızca çiziyor ve `LatvianLessonModel`
/// üzerinden tek kapıdan soruyor.
///
/// ## İki çıkış, tek sonuç
///
/// `onFinish` ya cevap panelinin düğmesinden (`advance()`) ya da üst şeritteki
/// çarpıdan (`abandon()`) çağrılıyor. İkisi de sonucu `LatvianLessonModel`'den
/// alıyor ve model `isOver` sayesinde onu **toplamda bir kez** veriyor;
/// dolayısıyla iki kapı da olsa çağıran hiçbir dersi iki kez işlemiyor.
///
/// Kapak `fullScreenCover`, `sheet` değil: soru alanı zaten bir `ScrollView`,
/// yaprakta aşağı doğru bir kaydırma dersi soru ortasında kapatırdı. Çıkış
/// bilerek yalnızca çarpıdan ve bilerek onaylı.
struct LatvianLessonView: View {
    @ObservedObject var audio: LatvianAudioStore
    @ObservedObject var feedback: LatvianFeedback
    let onFinish: (LatvianLessonOutcome) -> Void

    @StateObject private var model: LatvianLessonModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pendingAnswer: LatvianAnswer?
    @State private var questionStartedAt = Date()
    /// Çıkış onayı ekranda mı.
    @State private var isQuitAsked = false

    init(
        exercises: [LatvianExercise],
        audio: LatvianAudioStore,
        feedback: LatvianFeedback,
        onFinish: @escaping (LatvianLessonOutcome) -> Void
    ) {
        _model = StateObject(wrappedValue: LatvianLessonModel(exercises: exercises))
        self.audio = audio
        self.feedback = feedback
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            LatvianLessonHeader(
                mood: mood,
                progress: model.progress,
                heartsLeft: model.heartsLeft,
                onQuit: askQuit
            )
            questionArea
            footer
        }
        .background(Theme.bg.ignoresSafeArea())
        .task {
            feedback.prewarm()
            if let outcome = model.finishIfEmpty() { onFinish(outcome) }
        }
        .onChange(of: model.presentationIndex) { _, _ in
            // Yeni soru: bekleyen cevap ve süre ölçümü kesinlikle sıfırdan.
            pendingAnswer = nil
            questionStartedAt = Date()
        }
        // Muhasebe **soruda** yazıyor, sonucunda değil: "canların geri gelmez"
        // öğrencinin çıkmadan önce bilmesi gereken şey, çıktıktan sonra öğrenmesi
        // gereken şey değil.
        .confirmationDialog(
            "Dersten çıkılsın mı?",
            isPresented: $isQuitAsked,
            titleVisibility: .visible
        ) {
            Button("Çık", role: .destructive, action: quit)
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Verdiğin cevaplar kaydedilir, kaybettiğin canlar geri gelmez.")
        }
    }

    // MARK: - Soru

    private var questionArea: some View {
        ScrollView {
            if let exercise = model.current {
                exerciseView(exercise)
                    .padding(20)
                    // Kimlik soru kimliği değil gösterim sayısı: aynı soru arka
                    // arkaya iki kez sorulabiliyor ve o durumda görünüm sıfırdan
                    // kurulmalı (bkz. `LatvianLessonModel.presentationIndex`).
                    .id(model.presentationIndex)
                    .transition(exerciseTransition)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func exerciseView(_ exercise: LatvianExercise) -> some View {
        let isLocked = model.review != nil
        switch exercise.content {
        case .choice:
            LatvianChoiceExerciseView(
                exercise: exercise, audio: audio, feedback: feedback,
                isLocked: isLocked, onAnswerReady: accept
            )
        case .wordBank:
            LatvianWordBankExerciseView(
                exercise: exercise, audio: audio, feedback: feedback,
                isLocked: isLocked, onAnswerReady: accept
            )
        case .matching:
            LatvianMatchExerciseView(
                exercise: exercise, audio: audio, feedback: feedback,
                isLocked: isLocked, onAnswerReady: accept
            )
        case .typing:
            LatvianTypingExerciseView(
                exercise: exercise, audio: audio, feedback: feedback,
                isLocked: isLocked, onAnswerReady: accept
            )
        case .speaking:
            LatvianSpeakExerciseView(
                exercise: exercise, audio: audio, feedback: feedback,
                isLocked: isLocked, onAnswerReady: accept
            )
        }
    }

    /// Soru görünümünden gelen cevap. Panel açıkken gelen her şey düşüyor:
    /// giden görünüm kaybolurken haber verirse bekleyen cevabı bozmasın.
    private func accept(_ answer: LatvianAnswer?) {
        guard model.review == nil else { return }
        pendingAnswer = answer
    }

    // MARK: - Alt şerit

    @ViewBuilder
    private var footer: some View {
        if let review = model.review {
            LatvianAnswerPanel(
                isCorrect: review.result.grade.isCorrect,
                correctAnswer: review.result.grade.correctAnswer,
                explanation: review.explanation,
                comboMilestone: review.result.isComboMilestone ? review.result.comboCount : nil,
                isLastQuestion: review.isFinal,
                onContinue: advance
            )
            .transition(panelTransition)
        } else {
            submitButton
                .transition(.opacity)
        }
    }

    /// Reduce Motion açıkken yer değiştirme kalkıyor, sönme kalıyor: eğrinin
    /// yumuşaması yetmez, kayan nesnenin kendisi bu ayarın kapatmak istediği şey.
    private var exerciseTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private var panelTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private var submitButton: some View {
        let isReady = pendingAnswer != nil
        return Button(action: submit) {
            Text("Kontrol et")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(isReady ? Theme.bg : Theme.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    isReady ? AnyShapeStyle(Theme.ok) : AnyShapeStyle(Theme.panel),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                // Kapalı hâl `Theme.panel` (beyazın %4,5'i) — koyu zeminde tek
                // başına düğme gibi okunmuyordu, boş bir alan gibi duruyordu.
                // Kenarlık onu "henüz basılamaz bir düğme" yapıyor.
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isReady ? Color.clear : Theme.line, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(pendingAnswer == nil)
        .padding(20)
        .accessibilityLabel("Cevabı kontrol et")
        .accessibilityHint(pendingAnswer == nil ? "Önce bir cevap seç." : "")
    }

    // MARK: - Eylemler

    private func submit() {
        guard let answer = pendingAnswer else { return }
        let elapsed = Date().timeIntervalSince(questionStartedAt)

        // Mutasyon `withAnimation`'ın **içinde**: panel modelde açıldığı için
        // dışarıda sarmalamak animasyonsuz bir sıçrama demekti.
        let review = withAnimation(motion(LatvianMotion.slide)) {
            // Model gönderimi reddederse (hızlı ikinci dokunuş, bitmiş ders)
            // hiçbir ses çalmıyor ve hiçbir sayaç oynamıyor.
            model.submit(answer, elapsed: elapsed)
        }
        guard let review else { return }

        if review.result.grade.isCorrect {
            feedback.correct()
            // Rozetin kendisi panelde; burada yalnızca sesi/haptic'i var.
            if review.result.isComboMilestone { feedback.combo() }
        } else {
            feedback.wrong()
            feedback.heartLost()
        }
    }

    private func advance() {
        let outcome = withAnimation(motion(LatvianMotion.slide)) { model.advance() }
        if let outcome { onFinish(outcome) }
    }

    private func askQuit() {
        feedback.tap()
        isQuitAsked = true
    }

    /// Onaydan sonra. Model sonucu yalnızca ilk çağrıda döndürüyor; ikinci
    /// dokunuş `nil` alıyor ve hiçbir şey olmuyor.
    private func quit() {
        guard let outcome = model.abandon() else { return }
        onFinish(outcome)
    }

    // MARK: - Türetilenler

    /// Maskotun ruh hali durumdan türüyor; ayrı bir `@State` olsaydı soru
    /// değişiminde sıfırlanmayı unutabilir, ekranla ayrışabilirdi.
    private var mood: LatvianMascotMood {
        if let review = model.review {
            return review.result.grade.isCorrect ? .correct : .wrong
        }
        return pendingAnswer == nil ? .idle : .thinking
    }

    private func motion(_ base: Animation) -> Animation {
        LatvianMotion.adaptive(base, reduceMotion: reduceMotion)
    }
}
