import SwiftUI

/// `listenChoose`, `iconChoose`, `fillBlank` ve `caseDrill` için ortak seçmeli görünüm.
///
/// Kilitli haldeki iki kırmızı/yeşil kart birbirine karıştırılmasın diye üç şey
/// birden değişiyor: renk, simge ve Türkçe bir alt etiket ("Doğru" / "Seçtiğin").
/// Renk tek başına, hem renk körlüğünde hem de "hangisi benim cevabımdı"
/// sorusunda yetersiz kalıyordu.
struct LatvianChoiceExerciseView: View {
    let exercise: LatvianExercise
    @ObservedObject var audio: LatvianAudioStore
    @ObservedObject var feedback: LatvianFeedback
    let isLocked: Bool
    let onAnswerReady: (LatvianAnswer?) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: Int?
    /// Ekrandaki durumun hangi soruya ait olduğu. Kabuk aynı görünümü yeni bir
    /// soruyla yeniden kullanabilir; kimlik değişmeden seçim silinmemeli,
    /// değişince de kesinlikle silinmeli.
    @State private var loadedId: String?
    @State private var shakeTrigger = 0

    private var options: [String] {
        if case .choice(let values, _) = exercise.content { return values }
        return []
    }

    private var correctIndex: Int {
        if case .choice(_, let index) = exercise.content { return index }
        return -1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LatvianPromptText(text: exercise.prompt)

            if let audioId = exercise.audioId {
                LatvianListenButton(audioId: audioId, audio: audio, feedback: feedback)
            }

            if let carrier = exercise.carrier {
                LatvianCarrierCard(text: carrier)
            }

            VStack(spacing: 11) {
                ForEach(options.indices, id: \.self) { index in
                    optionCard(index)
                }
            }
        }
        .latvianShake(trigger: shakeTrigger)
        .onAppear(perform: syncExercise)
        .onChange(of: exercise.id) { _, _ in syncExercise() }
        .onChange(of: isLocked) { _, locked in
            guard locked, selected != correctIndex else { return }
            shakeTrigger += 1
        }
    }

    // MARK: - Şıklar

    private func optionCard(_ index: Int) -> some View {
        Button {
            guard !isLocked else { return }
            feedback.tap()
            withAnimation(LatvianMotion.adaptive(LatvianMotion.snap, reduceMotion: reduceMotion)) {
                selected = index
            }
            onAnswerReady(.choice(index: index))
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(options[index])
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                    // Uzun şıklar (paketteki en uzunu "ātrā palīdzība") kırpılmasın.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let mark = mark(index) {
                    Text(mark.caption)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(mark.color)
                    Image(systemName: mark.symbol)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(mark.color)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background(index), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(border(index), lineWidth: 2)
            )
            .opacity(dimmed(index) ? 0.5 : 1)
            .scaleEffect(!isLocked && selected == index ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        // `.disabled` yerine: kilitli kartlar soluklaştırılmamalı, cevap paneli
        // tam da onları okutuyor. Dokunuş hem burada hem eylemde kesiliyor.
        .allowsHitTesting(!isLocked)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(index))
        .accessibilityAddTraits(accessibilityTraits(index))
        .accessibilityHint(isLocked ? "" : "Seçmek için dokun.")
    }

    // MARK: - Renkler

    private func background(_ index: Int) -> Color {
        guard isLocked else { return selected == index ? Theme.c3.opacity(0.28) : Theme.panel }
        if index == correctIndex { return Theme.ok.opacity(0.24) }
        if index == selected { return Theme.bad.opacity(0.24) }
        return Theme.panel
    }

    private func border(_ index: Int) -> Color {
        guard isLocked else { return selected == index ? Theme.c3 : Theme.line }
        if index == correctIndex { return Theme.ok }
        if index == selected { return Theme.bad }
        return Theme.line
    }

    /// Kilitliyken işaretsiz kartlar geri çekiliyor: göz doğrudan iki işaretli
    /// karta gitsin.
    private func dimmed(_ index: Int) -> Bool {
        isLocked && index != correctIndex && index != selected
    }

    private func mark(_ index: Int) -> LatvianAnswerMark? {
        guard isLocked else { return nil }
        if index == correctIndex { return .correct }
        if index == selected { return .wrong }
        return nil
    }

    // MARK: - Erişilebilirlik

    private func accessibilityText(_ index: Int) -> String {
        var parts = ["\(index + 1). seçenek: \(options[index])"]
        if !isLocked, selected == index { parts.append("seçili") }
        if let mark = mark(index) { parts.append(mark.label) }
        return parts.joined(separator: ", ")
    }

    private func accessibilityTraits(_ index: Int) -> AccessibilityTraits {
        var traits: AccessibilityTraits = isLocked ? [] : [.isButton]
        if selected == index { traits.formUnion(.isSelected) }
        return traits
    }

    // MARK: - Soru değişimi

    private func syncExercise() {
        guard loadedId != exercise.id else { return }
        let hadAnswer = selected != nil
        loadedId = exercise.id
        selected = nil
        // Yeni soruya eski cevabın gönderilebilir kalması, kabuğun "gönder"
        // düğmesini yanlış soruya açık bırakırdı.
        if hadAnswer { onAnswerReady(nil) }
        autoplay()
    }

    /// Dinleme sorusunda klip kendiliğinden çalıyor — ama yalnızca diskteyse.
    /// İnmemiş klipte `play` Türkçe bir hata bırakır; soru açılır açılmaz hata
    /// şeridi göstermek yerine düğme "Ses henüz inmedi" diyor.
    private func autoplay() {
        guard exercise.kind == .listenChoose,
              let audioId = exercise.audioId,
              audio.downloadedAudioIds.contains(audioId) else { return }
        audio.play(audioId: audioId)
    }
}
