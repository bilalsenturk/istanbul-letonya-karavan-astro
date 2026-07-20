import SwiftUI

// iPad / geniş ekran uyarlaması. iPhone'da (compact) tek sütun; iPad'de (regular)
// iki sütunlu ızgara + daha geniş okuma alanı. Tek yerden yönetilir.
enum Adaptive {
    /// Okunabilir içerik genişliği — iPad'de daha geniş ama sonsuz değil.
    static func contentWidth(_ sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        sizeClass == .regular ? 900 : 700
    }

    static func isWide(_ sizeClass: UserInterfaceSizeClass?) -> Bool {
        sizeClass == .regular
    }
}

/// Geniş ekranda iki sütuna açılan, dar ekranda tek sütun kalan yerleşim.
/// Kart yükseklikleri farklı olduğu için `LazyVGrid` yerine iki dikey sütun
/// kullanılır — böylece kartlar arasında boşluk oluşmaz.
struct AdaptiveColumns<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    var spacing: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        if Adaptive.isWide(sizeClass) {
            HStack(alignment: .top, spacing: spacing) {
                _VariadicView.Tree(TwoColumnLayout(spacing: spacing)) { content }
            }
        } else {
            VStack(spacing: spacing) { content }
        }
    }
}

/// Alt görünümleri sırayla iki sütuna dağıtır (sol, sağ, sol, sağ …).
private struct TwoColumnLayout: _VariadicView_MultiViewRoot {
    let spacing: CGFloat

    func body(children: _VariadicView.Children) -> some View {
        let left = children.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
        let right = children.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
        return Group {
            VStack(spacing: spacing) { ForEach(left) { $0 } }
                .frame(maxWidth: .infinity, alignment: .top)
            VStack(spacing: spacing) { ForEach(right) { $0 } }
                .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}
