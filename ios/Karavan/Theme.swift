import SwiftUI

// Web ile aynı marka dili: gün doğumu → aurora spektrumu, koyu zemin.
enum Theme {
    static let bg = Color(red: 0.027, green: 0.027, blue: 0.043)          // #07070b
    static let panel = Color.white.opacity(0.055)
    static let line = Color.white.opacity(0.10)
    static let text = Color(red: 0.965, green: 0.965, blue: 0.985)
    static let dim = Color.white.opacity(0.66)
    static let muted = Color.white.opacity(0.45)

    static let c1 = Color(red: 1.00, green: 0.604, blue: 0.235)  // #ff9a3c
    static let c2 = Color(red: 1.00, green: 0.302, blue: 0.427)  // #ff4d6d
    static let c3 = Color(red: 0.635, green: 0.294, blue: 1.00)  // #a24bff
    static let c4 = Color(red: 0.20, green: 0.878, blue: 0.816)  // #33e0d0

    static let ok = Color(red: 0.22, green: 0.878, blue: 0.541)
    static let warn = Color(red: 1.00, green: 0.761, blue: 0.294)
    static let bad = Color(red: 1.00, green: 0.329, blue: 0.439)

    static var grad: LinearGradient {
        LinearGradient(colors: [c1, c2, c3, c4], startPoint: .leading, endPoint: .trailing)
    }

    static var gradWarm: LinearGradient {
        LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var gradCool: LinearGradient {
        LinearGradient(colors: [c3, c4], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// Kart görünümü
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

// Mono etiket (web'deki eyebrow/mono his)
struct MonoLabel: View {
    let text: String
    var color: Color = Theme.muted

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .kerning(1.6)
            .foregroundStyle(color)
    }
}
