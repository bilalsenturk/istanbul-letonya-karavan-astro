import SwiftUI

// Sakin koyu arayüz: vurgu rengi sınırlı, kartlar nötr.
enum Theme {
    static let bg = Color(red: 0.027, green: 0.027, blue: 0.043)          // #07070b
    static let panel = Color.white.opacity(0.045)
    static let line = Color.white.opacity(0.085)
    static let text = Color(red: 0.965, green: 0.965, blue: 0.985)
    static let dim = Color.white.opacity(0.66)
    static let muted = Color.white.opacity(0.45)

    static let c1 = Color(red: 1.00, green: 0.604, blue: 0.235)  // #ff9a3c
    static let c2 = Color(red: 0.92, green: 0.286, blue: 0.392)  // softened rose
    static let c3 = Color(red: 0.49, green: 0.38, blue: 0.86)    // muted violet
    static let c4 = Color(red: 0.23, green: 0.78, blue: 0.74)    // muted teal

    static let ok = Color(red: 0.22, green: 0.878, blue: 0.541)
    static let warn = Color(red: 1.00, green: 0.761, blue: 0.294)
    static let bad = Color(red: 1.00, green: 0.329, blue: 0.439)

    static var grad: LinearGradient {
        LinearGradient(colors: [c1, c2], startPoint: .leading, endPoint: .trailing)
    }

    static var gradWarm: LinearGradient {
        LinearGradient(colors: [c1, c2.opacity(0.86)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var gradCool: LinearGradient {
        LinearGradient(colors: [c4.opacity(0.92), c4.opacity(0.66)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// Kart görünümü
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

// Ülke kodu rozeti — bayrak emojisi yerine (simülatörde/bazı fontlarda "?" çıkmaz).
struct CountryBadge: View {
    let code: String
    var size: CGFloat = 12

    var body: some View {
        Text(code)
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .kerning(0.3)
            .foregroundStyle(.white)
            .padding(.horizontal, size * 0.42)
            .padding(.vertical, size * 0.18)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: size * 0.35, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.35, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 0.7)
            )
            .fixedSize()
    }
}

// Mono etiket (web'deki eyebrow/mono his)
struct MonoLabel: View {
    let text: String
    var color: Color = Theme.muted

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .kerning(0.8)
            .foregroundStyle(color)
    }
}
