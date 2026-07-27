import SwiftUI

/// Beş soru görünümünün paylaştığı parçalar: soru başlığı, dinleme düğmesi,
/// taşıyıcı cümle kartı, kilit rozeti ve sarmalayan yerleşim.
///
/// Ayrı dosyada, çünkü beşi de aynı sözleşmeyi taşıyor
/// (`init(exercise:audio:feedback:isLocked:onAnswerReady:)`) ve aynı kabuğun
/// içinde çiziliyor; parçaları kopyalamak beş yerde ayrışan bir tipografi
/// demekti. Hiçbiri motoru (yani `Learning/`) bilmiyor — tersi de geçerli.

// MARK: - Soru metni

struct LatvianPromptText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 21, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.text)
            // Uzun sorular tek satıra sıkışıp kırpılmasın.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Taşıyıcı cümle

/// Boşluk doldurma / hal tatbikatının altı çizili cümlesi ve telaffuzun hedefi.
/// Letonca diakritikler olduğu gibi gösteriliyor; katlama yalnızca notlamada var.
struct LatvianCarrierCard: View {
    let text: String
    var size: CGFloat = 26

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.text)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 22)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
    }
}

// MARK: - Dinleme düğmesi

/// Klip diskte yoksa düğme "yalancı" görünmesin diye ayrı bir hâl gösteriyor:
/// `LatvianAudioStore.play` o durumda zaten Türkçe bir hata bırakıyor, ama
/// kullanıcı düğmeye basmadan da bilmeli.
struct LatvianListenButton: View {
    let audioId: String
    @ObservedObject var audio: LatvianAudioStore
    @ObservedObject var feedback: LatvianFeedback
    var title = "Dinle"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isReady: Bool { audio.downloadedAudioIds.contains(audioId) }
    private var isPlaying: Bool { audio.playingAudioId == audioId }

    var body: some View {
        Button {
            feedback.tap()
            audio.play(audioId: audioId)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isPlaying ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 19, weight: .bold))
                Text(isReady ? title : "Ses henüz inmedi")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(isReady ? Color.white : Theme.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                isReady ? AnyShapeStyle(Theme.gradCool) : AnyShapeStyle(Theme.panel),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.line, lineWidth: isReady ? 0 : 1)
            )
            .scaleEffect(isPlaying ? 1.02 : 1)
            .animation(LatvianMotion.adaptive(LatvianMotion.snap, reduceMotion: reduceMotion), value: isPlaying)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isReady ? "\(title). Sesi çal." : "Bu sesin dosyası henüz inmedi.")
    }
}

// MARK: - Kilit rozeti

/// Cevap paneli açıldığında kartların üstüne binen işaret. Renk tek başına
/// yeterli değil (renk körlüğü): simge ve Türkçe etiket hep birlikte gidiyor.
enum LatvianAnswerMark {
    case correct
    case wrong

    var symbol: String { self == .correct ? "checkmark.circle.fill" : "xmark.circle.fill" }
    var color: Color { self == .correct ? Theme.ok : Theme.bad }
    var label: String { self == .correct ? "doğru cevap" : "senin cevabın, yanlış" }

    var caption: String { self == .correct ? "Doğru" : "Seçtiğin" }
}

// MARK: - Sarmalayan yerleşim

/// Değişken genişlikli parçaları satır satır saran yerleşim.
///
/// `LazyVGrid` sabit sütun genişliği ister; kelime bankasında parçalar
/// "es"ten "apdrošināšana."ya kadar değişiyor. Adı `LatvianFlowLayout`:
/// `Views/Tools/LatvianLearningView.swift` içinde aynı işi gören eski bir
/// `FlowLayout` var ve iki tip aynı modülde çakışırdı.
///
/// Üç ayrıntı:
/// 1. Parçaya teklif edilen genişlik kutuyla sınırlanıyor. Kutudan geniş tek
///    bir parça (dar ekran + uzun kelime) taşıp kırpılmak yerine kendi içinde
///    sarıyor.
/// 2. Satır kırma payı var: kayan nokta yuvarlaması tam sığan bir parçayı alt
///    satıra atmasın.
/// 3. Genişlik teklifi yoksa (`nil`) tek satır varsayılıp doğal genişlik
///    dönüyor; `.infinity` döndürmek sarmalayan kutuyu sonsuza gerdiriyordu.
struct LatvianFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = proposal.width ?? .infinity
        let rows = rows(subviews: subviews, limit: limit)
        let height = rows.reduce(CGFloat.zero) { $0 + $1.height }
            + lineSpacing * CGFloat(max(0, rows.count - 1))
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: limit.isFinite ? limit : widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews: subviews, limit: bounds.width) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private func rows(subviews: Subviews, limit: CGFloat) -> [Row] {
        let itemProposal = ProposedViewSize(width: limit.isFinite ? max(limit, 0) : nil, height: nil)
        var rows: [Row] = []
        var row = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(itemProposal)
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if !row.items.isEmpty, needed > limit + 0.01 {
                rows.append(row)
                row = Row(items: [(index, size)], width: size.width, height: size.height)
            } else {
                row.items.append((index, size))
                row.width = needed
                row.height = max(row.height, size.height)
            }
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
