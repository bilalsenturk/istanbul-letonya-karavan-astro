import Foundation
import os

private let logger = Logger(subsystem: "com.bilalsenturk.kuzey", category: "RoadFeed")

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

/// Dizi içindeki bozuk tek bir girdi tüm çözümlemeyi öldürmesin:
/// çözülemeyen eleman nil olur ve atlanır.
private struct LossyElement<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// Kur değeri sayı ya da metin gelebilir; ikisi de değilse nil (atlanır).
private struct LossyDouble: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = Double(s) }
        else { value = nil }
    }
}

struct RoadFeed: Codable {
    let fuel: [FuelPrice]
    let borders: [BorderWait]
    let rates: [String: Double]     // EUR bazlı: {"TRY": 47.2, "BGN": 1.96, …}
    let updatedAt: String?
    let sources: [String]?

    // Hoşgörülü çözümleme: tek bir bozuk alan bültenin tamamını sessizce
    // öldürüyordu (strict Codable tek hata atar). Hatalı girdiler atlanır
    // ve günlüğe yazılır; kalan bölümler yaşamaya devam eder.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let rawFuel = (try? c.decode([LossyElement<FuelPrice>].self, forKey: .fuel)) ?? []
        fuel = rawFuel.compactMap(\.value)
        let droppedFuel = rawFuel.count - fuel.count
        if droppedFuel > 0 {
            logger.warning("roadfeed: \(droppedFuel) bozuk yakıt girdisi atlandı")
        }

        let rawBorders = (try? c.decode([LossyElement<BorderWait>].self, forKey: .borders)) ?? []
        borders = rawBorders.compactMap(\.value)
        let droppedBorders = rawBorders.count - borders.count
        if droppedBorders > 0 {
            logger.warning("roadfeed: \(droppedBorders) bozuk sınır girdisi atlandı")
        }

        let rawRates = (try? c.decode([String: LossyDouble].self, forKey: .rates)) ?? [:]
        rates = rawRates.compactMapValues(\.value)
        let droppedRates = rawRates.count - rates.count
        if droppedRates > 0 {
            logger.warning("roadfeed: \(droppedRates) bozuk kur girdisi atlandı")
        }

        updatedAt = try? c.decode(String.self, forKey: .updatedAt)
        sources = try? c.decode([String].self, forKey: .sources)
    }
}

@MainActor
final class RoadFeedService: ObservableObject {
    @Published private(set) var feed: RoadFeed?
    @Published private(set) var updatedAt: Date?

    /// Bir önceki çekimdeki kurlar — sıçrama tespiti için. UserDefaults'ta
    /// tutulur; yalnızca bellekte kalsaydı uygulama açılışındaki İLK çekimde
    /// karşılaştırma tabanı olmaz ve sıçramalar kaçardı.
    private static let previousRatesKey = "roadfeed.previousRates"
    private var previousRates: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: Self.previousRatesKey) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.previousRatesKey) }
    }

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

        // Kur sıçraması bildirimi + yakıt fiyatlarını bildirim katmanına ver.
        if let feed {
            let previous = previousRates
            for (code, rate) in feed.rates {
                if let old = previous[code] {
                    TripNotifier.shared.onCurrency(previous: old, current: rate, code: code)
                }
            }
            previousRates = feed.rates

            // Yakıt karşılaştırması konumu bilmeyi gerektiriyor; fiyatları
            // bildirim katmanına verip kararı orada veriyoruz.
            TripNotifier.shared.updateFuelPrices(feed.fuel)
        }
    }

    // MARK: - Yardımcılar

    func diesel(for countryCode: String) -> Double? {
        feed?.fuel.first { $0.country == countryCode }?.dieselEur
    }

    /// Rota üzerindeki ülkeler arasında en ucuz dizel.
    func cheapestDiesel(among codes: [String]) -> FuelPrice? {
        feed?.fuel
            .filter { codes.contains($0.country) && $0.dieselEur > 0 }
            .min { $0.dieselEur < $1.dieselEur }
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
