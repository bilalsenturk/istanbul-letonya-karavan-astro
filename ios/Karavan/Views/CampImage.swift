import SwiftUI

// Ağdan yüklenen, önbellekli kamp görseli. Görsel app'e gömülmez → app hafif kalır.
// Yükleme/başarısızlıkta temalı gradyan + çadır ikonu gösterir; eksik görsel UI'ı bozmaz.
struct CampImage: View {
    let path: String?          // "/assets/camps/x.webp" ya da tam URL
    var height: CGFloat = 190
    var width: CGFloat? = nil  // nil → tüm genişliği kaplar
    var cornerRadius: CGFloat = 18
    var symbol = "tent.fill"
    var accessibilityLabel = "Kamp görseli"

    private var url: URL? {
        Self.resolve(path: path, relativeTo: Config.imageBaseURL)
    }

    var body: some View {
        ZStack {
            placeholder
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Color.clear
                    }
                }
            }
        }
        .modifier(SizeModifier(width: width, height: height))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var placeholder: some View {
        ZStack {
            Theme.gradWarm.opacity(0.5)
            Image(systemName: symbol)
                .font(.system(size: min(height * 0.32, 34), weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    static func resolve(path: String?, relativeTo baseURL: URL?) -> URL? {
        guard let value = path?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if let absolute = URL(string: value), let scheme = absolute.scheme {
            guard scheme == "https" || scheme == "http" else { return nil }
            return absolute
        }
        guard let baseURL, ["https", "http"].contains(baseURL.scheme?.lowercased() ?? "") else { return nil }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }
}

private struct SizeModifier: ViewModifier {
    let width: CGFloat?
    let height: CGFloat

    func body(content: Content) -> some View {
        if let width {
            content.frame(width: width, height: height)
        } else {
            content.frame(maxWidth: .infinity).frame(height: height)
        }
    }
}
