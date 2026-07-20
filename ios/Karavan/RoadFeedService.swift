import Foundation

// Yol bülteni: (1) ülke bazında dizel fiyatı, (2) Kapıkule sınır beklemesi,
// (4) döviz kurları. Hepsi siteden tek endpoint üzerinden gelir (/api/roadfeed):
// anahtar gerektirmeyen kaynaklar sunucuda toplanır, app tek istekle okur.
struct FuelPrice: Codable, Identifiable {
    let country: String        // ülke kodu (TR, BG, RO…)
    let dieselEur: Double      // €/L
    var id: String { country }
}

struct BorderWait: Codable, Identifiable {
    let name: String           // "Kapıkule"
    let inbound: String?       // giriş bekleme (metin, ör. "2 saat")
    let outbound: String?      // çıkış bekleme
    let note: String?
    var id: String { name }
}

struct RoadFeed: Codable {
    let fuel: [FuelPrice]
    let borders: [BorderWait]
    let rates: [String: Double]     // EUR bazlı: {"TRY": 47.2, "BGN": 1.96, …}
    let updatedAt: String?
    let sources: [String]?
}

@MainActor
final class RoadFeedService: ObservableObject {
    @Published private(set) var feed: RoadFeed?
    @Published private(set) var updatedAt: Date?

    private var lastFetch: Date = .distantPast

    /// En fazla 3 saatte bir tazelenir (veri günlük/haftalık değişiyor).
    func refresh(force: Bool = false) async {
        guard force || Date().timeIntervalSince(lastFetch) > 3 * 3600 else { return }
        guard let url = Config.roadFeedURL else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(RoadFeed.self, from: data)
        else { return }
        feed = decoded
        updatedAt = Date()
        lastFetch = Date()
    }

    // MARK: - Yardımcılar

    func diesel(for countryCode: String) -> Double? {
        feed?.fuel.first { $0.country == countryCode }?.dieselEur
    }

    /// Rota üzerindeki ülkeler arasında en ucuz dizel.
    func cheapestDiesel(among codes: [String]) -> FuelPrice? {
        feed?.fuel.filter { codes.contains($0.country) }.min { $0.dieselEur < $1.dieselEur }
    }

    /// EUR → yerel para çevirisi (ör. 40 € kaç TRY).
    func convert(eur: Double, to currency: String) -> Double? {
        guard let rate = feed?.rates[currency] else { return nil }
        return eur * rate
    }

    /// Ülke kodu → para birimi
    static func currency(for countryCode: String) -> String? {
        switch countryCode {
        case "TR": return "TRY"
        case "BG": return "BGN"
        case "RO": return "RON"
        case "HU": return "HUF"
        case "PL": return "PLN"
        case "LV", "LT": return "EUR"
        default: return nil
        }
    }
}
