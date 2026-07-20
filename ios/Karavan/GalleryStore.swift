import Foundation

// Şehir görsel galerisi. Manifest uzak depodan (site ya da Cloudflare) okunur;
// görseller ağdan yüklenir (app'e gömülmez) ve URLCache'te kalır.
struct GalleryPhoto: Codable, Identifiable, Hashable {
    let city: String
    let cityName: String
    let file: String          // "/assets/gallery/sofia/sofia-01.webp"
    let caption: String
    let credit: String?
    let license: String?

    var id: String { file }
}

@MainActor
final class GalleryStore: ObservableObject {
    @Published private(set) var photos: [GalleryPhoto] = []

    private var loaded = false

    /// Gün hedefinden şehir anahtarına ("Bükreş Güney" → "bucharest").
    private static let cityKeys: [(match: String, key: String)] = [
        ("İstanbul", "istanbul"), ("Sofya", "sofia"), ("Bükreş", "bucharest"),
        ("Deva", "deva"), ("Budapeşte", "budapest"), ("Katowice", "katowice"),
        ("Suwałki", "suwalki"), ("Riga", "riga"),
    ]

    static func cityKey(for name: String) -> String? {
        cityKeys.first { name.contains($0.match) || $0.match.contains(name) }?.key
    }

    func load() async {
        guard !loaded,
              let base = Config.imageBaseURL,
              let url = URL(string: "/assets/gallery/manifest.json", relativeTo: base)
        else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode([GalleryPhoto].self, from: data)
        else { return }
        photos = decoded
        loaded = true
    }

    func photos(forDestination name: String) -> [GalleryPhoto] {
        guard let key = Self.cityKey(for: name) else { return [] }
        return photos.filter { $0.city == key }
    }
}
