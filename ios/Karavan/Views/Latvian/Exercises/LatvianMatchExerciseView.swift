import SwiftUI

/// `match` için dört çiftlik eşleştirme tahtası.
///
/// Sıra dayatmıyor: önce Türkçeye dokunan da eşleştirebiliyor, aynı karta ikinci
/// kez dokunmak seçimi bırakıyor, kurulmuş bir eşleşmenin herhangi bir ucuna
/// dokunmak onu geri alıyor — geri alınamayan yanlış bir eşleşme öğrenciyi
/// kaybedilmiş bir soruya kilitlerdi.
///
/// İki sütun `Grid` ile: satır yükseklikleri eşitleniyor, böylece uzun bir Türkçe
/// karşılık ("her şey gönlünüzce olsun") sütunları kaydırmıyor.
struct LatvianMatchExerciseView: View {
    let exercise: LatvianExercise
    @ObservedObject var audio: LatvianAudioStore
    @ObservedObject var feedback: LatvianFeedback
    let isLocked: Bool
    let onAnswerReady: (LatvianAnswer?) -> Void

    private enum Side { case lv, tr }

    private struct Row: Identifiable {
        let id: Int
        let lv: String
        let tr: String
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lvColumn: [String] = []
    @State private var trColumn: [String] = []
    @State private var matched: [LatvianMatchPair] = []
    @State private var selectedLv: String?
    @State private var selectedTr: String?
    @State private var loadedId: String?
    @State private var shakeTrigger = 0

    private var pairs: [LatvianMatchPair] {
        if case .matching(let values) = exercise.content { return values }
        return []
    }

    private var motion: Animation {
        LatvianMotion.adaptive(LatvianMotion.snap, reduceMotion: reduceMotion)
    }

    private var rows: [Row] {
        zip(lvColumn, trColumn).enumerated().map { Row(id: $0.offset, lv: $0.element.0, tr: $0.element.1) }
    }

    /// Notlayıcının vereceği sonuç: her beklenen çift tam bir kez örtülmüş mü.
    private var isAnswerCorrect: Bool {
        matched.count == pairs.count && !pairs.isEmpty && matched.allSatisfy(isRight)
    }

    /// Notlayıcının beklediği eşleme, aynı katlamayla: kilitli hâlin rengi
    /// buradan geliyor, ayrı bir karşılaştırma iki doğruluk kaynağı olurdu.
    private var expectedByLv: [String: String] {
        var map: [String: String] = [:]
        for pair in pairs { map[LatvianGrader.normalize(pair.lv)] = LatvianGrader.normalize(pair.tr) }
        return map
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LatvianPromptText(text: exercise.prompt)

            if let audioId = exercise.audioId {
                LatvianListenButton(audioId: audioId, audio: audio, feedback: feedback)
            }

            Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    MonoLabel(text: "Letonca", color: Theme.c4)
                    MonoLabel(text: "Türkçe", color: Theme.c1)
                }
                ForEach(rows) { row in
                    GridRow {
                        cell(row.lv, side: .lv)
                        cell(row.tr, side: .tr)
                    }
                }
            }
        }
        .latvianShake(trigger: shakeTrigger)
        .onAppear(perform: syncExercise)
        .onChange(of: exercise.id) { _, _ in syncExercise() }
        .onChange(of: isLocked) { _, locked in
            guard locked, !isAnswerCorrect else { return }
            shakeTrigger += 1
        }
    }

    // MARK: - Kartlar

    private func cell(_ value: String, side: Side) -> some View {
        Button {
            tap(value, side: side)
        } label: {
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)

                badge(value, side: side)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(tone(value, side: side), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(border(value, side: side), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isLocked)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(value, side: side))
        .accessibilityAddTraits(isLocked ? [] : [.isButton])
        .accessibilityHint(isLocked ? "" : "Eşleştirmek için dokun; kurulmuş eşleşmeyi geri almak için yine dokun.")
    }

    /// Numara hangi kartın hangisiyle eşleştiğini söylüyor ve kilitlendikten
    /// sonra da duruyor: yalnızca yeşil/kırmızı bırakmak, iki ayrı satırdaki
    /// yeşil kartın aynı çift mi olduğunu okunamaz hâle getiriyordu.
    @ViewBuilder
    private func badge(_ value: String, side: Side) -> some View {
        if let pair = pair(containing: value, side: side), let order = order(of: pair) {
            if isLocked {
                HStack(spacing: 3) {
                    Text("\(order)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                    Image(systemName: isRight(pair) ? LatvianAnswerMark.correct.symbol : LatvianAnswerMark.wrong.symbol)
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(isRight(pair) ? Theme.ok : Theme.bad)
            } else {
                Text("\(order)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.bg)
                    .frame(width: 20, height: 20)
                    .background(Theme.c3, in: Circle())
            }
        }
    }

    // MARK: - Dokunuş

    private func tap(_ value: String, side: Side) {
        guard !isLocked else { return }
        feedback.tap()
        if let pair = pair(containing: value, side: side) {
            withAnimation(motion) { matched.removeAll { $0 == pair } }
            publish()
            return
        }
        switch side {
        case .lv:
            if let tr = selectedTr { commit(lv: value, tr: tr) } else { toggle(&selectedLv, value) }
        case .tr:
            if let lv = selectedLv { commit(lv: lv, tr: value) } else { toggle(&selectedTr, value) }
        }
    }

    private func toggle(_ slot: inout String?, _ value: String) {
        let next = slot == value ? nil : value
        withAnimation(motion) { slot = next }
    }

    private func commit(lv: String, tr: String) {
        withAnimation(motion) {
            matched.append(LatvianMatchPair(lv: lv, tr: tr))
            selectedLv = nil
            selectedTr = nil
        }
        publish()
    }

    /// Eksik eşleşme gönderilemez. `pairs` boşken de gönderilemez: notlayıcı boş
    /// bir `.pairs([])`'i "hepsi örtüldü" sayıp doğru derdi.
    private func publish() {
        let complete = !pairs.isEmpty && matched.count == pairs.count
        onAnswerReady(complete ? .pairs(matched) : nil)
    }

    // MARK: - Durum

    private func pair(containing value: String, side: Side) -> LatvianMatchPair? {
        matched.first { side == .lv ? $0.lv == value : $0.tr == value }
    }

    private func order(of pair: LatvianMatchPair) -> Int? {
        matched.firstIndex(of: pair).map { $0 + 1 }
    }

    private func isRight(_ pair: LatvianMatchPair) -> Bool {
        expectedByLv[LatvianGrader.normalize(pair.lv)] == LatvianGrader.normalize(pair.tr)
    }

    private func isSelected(_ value: String, side: Side) -> Bool {
        side == .lv ? selectedLv == value : selectedTr == value
    }

    private func tone(_ value: String, side: Side) -> Color {
        guard let pair = pair(containing: value, side: side) else {
            return isSelected(value, side: side) ? Theme.c3.opacity(0.28) : Theme.panel
        }
        guard isLocked else { return Theme.c3.opacity(0.16) }
        return (isRight(pair) ? Theme.ok : Theme.bad).opacity(0.22)
    }

    private func border(_ value: String, side: Side) -> Color {
        guard let pair = pair(containing: value, side: side) else {
            return isSelected(value, side: side) ? Theme.c3 : Theme.line
        }
        guard isLocked else { return Theme.c3.opacity(0.7) }
        return isRight(pair) ? Theme.ok : Theme.bad
    }

    private func accessibilityText(_ value: String, side: Side) -> String {
        var parts = [side == .lv ? "Letonca: \(value)" : "Türkçe: \(value)"]
        if isSelected(value, side: side) { parts.append("seçili") }
        if let pair = pair(containing: value, side: side) {
            let order = order(of: pair).map { "\($0). çift, " } ?? ""
            parts.append(order + (side == .lv ? "\(pair.tr) ile eşleşti" : "\(pair.lv) ile eşleşti"))
            if isLocked { parts.append(isRight(pair) ? LatvianAnswerMark.correct.label : LatvianAnswerMark.wrong.label) }
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Soru değişimi

    private func syncExercise() {
        guard loadedId != exercise.id else { return }
        let hadAnswer = !matched.isEmpty
        loadedId = exercise.id
        matched = []
        selectedLv = nil
        selectedTr = nil
        // Ayrı ayrı karıştırılıyor; aynı sırada dizilseler cevap satır satır okunurdu.
        lvColumn = pairs.map(\.lv).shuffled()
        trColumn = pairs.map(\.tr).shuffled()
        if hadAnswer { onAnswerReady(nil) }
    }
}
