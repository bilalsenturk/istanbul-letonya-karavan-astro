import Foundation

// Anons seçim motoru — kullanıcı kuralları:
//  • Aynı METİN en az 12 saat tekrar etmez
//  • Aynı KATEGORİ en az 45 dk tekrar etmez (kritik kategoriler muaf)
//  • Ağırlıklı seçim: normal ×55 · kişisel (Sezin/Leyla) ×25 · güçlü kaptan ×15
//    (kategori içi ağırlık; nadir klipler ayrıca ~%4 ihtimalle araya girer)
//  • Nadir sürpriz: ~%4 ihtimalle araya girer (yalnızca eğlence anonslarında)
//  • Pırt esprisi: günde en fazla 1
//  • Kritik uyarılar (yağmur/fırtına/rüzgâr/hız/dikkat): her zaman çalar, komedi
//    filtrelenmez — metinlerde zaten önce talimat, sonra espri var
//  • 12 saniyeyi aşacak kadar uzun metinler elenir
@MainActor
final class AnnouncementEngine: ObservableObject {
    static let shared = AnnouncementEngine()

    @Published private(set) var clipCount = 0

    /// key → metin
    private var clips: [String: String] = [:]
    /// kategori → o kategorideki anahtarlar
    private var byCategory: [String: [String]] = [:]

    private let defaults = UserDefaults.standard
    private let playedKeyPrefix = "annPlayed."      // key → epoch
    private let playedCatPrefix = "annCat."         // kategori → epoch
    private let fartDayKey = "annFartDay"           // gün numarası

    private init() {}

    // MARK: - Katalog

    /// Web'den (veya gömülü kopyadan) anons kataloğunu yükle.
    func load() async {
        if let remote = await fetchRemote(), !remote.isEmpty {
            apply(remote)
            return
        }
        if let url = Bundle.main.url(forResource: "announcements", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let local = try? JSONDecoder().decode([String: String].self, from: data) {
            apply(local)
        }
    }

    private func fetchRemote() async -> [String: String]? {
        guard let base = Config.imageBaseURL,
              let url = URL(string: "/assets/announcements.json", relativeTo: base) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return nil }
        return decoded
    }

    private func apply(_ map: [String: String]) {
        clips = map
        byCategory = Dictionary(grouping: map.keys) { Self.category(of: $0) }
        clipCount = map.count
    }

    /// "captain-07" → "captain", "arrive-sofya-tr-02" → "arrive-sofya-tr", "storm" → "storm"
    static func category(of key: String) -> String {
        guard let range = key.range(of: #"-\d+$"#, options: .regularExpression) else { return key }
        return String(key[key.startIndex ..< range.lowerBound])
    }

    // MARK: - Kurallar

    /// Güvenlik/uyarı kategorileri — kısıtlamalardan muaf, her zaman çalar.
    private static let critical: Set<String> = [
        "rain-start", "storm", "crosswind", "speed-warning", "focus",
        "fuel-low", "border-ahead", "deviation", "rough-road",
    ]

    private static let sameTextWindow: TimeInterval = 12 * 3600
    private static let sameCategoryWindow: TimeInterval = 45 * 60
    private static let rareChance = 0.04
    private static let maxChars = 220        // ~12 sn konuşma

    private func isPersonal(_ text: String) -> Bool {
        text.contains("Sezin") || text.contains("Leyla")
    }

    private func isFart(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains("pırt")
    }

    private func lastPlayed(key: String) -> Date? {
        let t = defaults.double(forKey: playedKeyPrefix + key)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    private func lastPlayed(category: String) -> Date? {
        let t = defaults.double(forKey: playedCatPrefix + category)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    private func markPlayed(key: String) {
        let now = Date().timeIntervalSince1970
        defaults.set(now, forKey: playedKeyPrefix + key)
        defaults.set(now, forKey: playedCatPrefix + Self.category(of: key))
        if let text = clips[key], isFart(text) {
            defaults.set(Self.dayNumber, forKey: fartDayKey)
        }
    }

    private func markPlayed(category: String) {
        defaults.set(Date().timeIntervalSince1970, forKey: playedCatPrefix + category)
    }

    /// Yerel takvim günü (UTC gece yarısı değil; saat dilimi geçişinde doğru sayılır).
    private static var dayNumber: Int {
        Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
    }

    private var fartUsedToday: Bool {
        defaults.integer(forKey: fartDayKey) == Self.dayNumber
    }

    // MARK: - Seçim

    /// Bir kategoriden kural-uyumlu anons seç. Uygun yoksa nil.
    func pick(_ category: String) -> AnnouncementCatalog.Clip? {
        let isCritical = Self.critical.contains(category)

        // Kategori bekleme süresi (kritikler muaf)
        if !isCritical, let last = lastPlayed(category: category),
           Date().timeIntervalSince(last) < Self.sameCategoryWindow {
            return nil
        }

        // Eğlence anonslarında nadir sürpriz araya girebilir
        if !isCritical, category != "rare", Double.random(in: 0 ... 1) < Self.rareChance,
           let rare = candidates(in: "rare").randomElement() {
            markPlayed(category: category)   // istenen kategori de bekleme alsın
            return makeClip(rare)
        }

        var pool = candidates(in: category)
        guard !pool.isEmpty else {
            // Hepsi 12 saat penceresindeyse en eskisini kullan (sessiz kalmaktansa)
            guard let fallback = oldest(in: category) else { return nil }
            return makeClip(fallback)
        }

        if !isCritical {
            pool = weighted(pool)
        }
        guard let key = pool.randomElement() else { return nil }
        return makeClip(key)
    }

    /// 12 saat penceresi + pırt kuralı + uzunluk filtresinden geçen anahtarlar.
    private func candidates(in category: String) -> [String] {
        (byCategory[category] ?? []).filter { key in
            guard let text = clips[key], text.count <= Self.maxChars else { return false }
            if isFart(text), fartUsedToday { return false }
            if let last = lastPlayed(key: key), Date().timeIntervalSince(last) < Self.sameTextWindow {
                return false
            }
            return true
        }
    }

    private func oldest(in category: String) -> String? {
        (byCategory[category] ?? [])
            .filter { key in
                guard let text = clips[key], text.count <= Self.maxChars else { return false }
                // Günlük pırt kotası yedek seçimde de geçerli — yoksa fallback
                // kotayı baypas edip günün ikinci pırtını çalardı.
                if isFart(text), fartUsedToday { return false }
                return true
            }
            .min { (lastPlayed(key: $0) ?? .distantPast) < (lastPlayed(key: $1) ?? .distantPast) }
    }

    /// %55 normal · %25 kişisel · %15 güçlü kaptan — havuzu kopyalayarak ağırlıklandırır.
    private func weighted(_ pool: [String]) -> [String] {
        var out: [String] = []
        for key in pool {
            guard let text = clips[key] else { continue }
            let weight: Int
            if isPersonal(text) { weight = 25 }
            else if key.hasPrefix("captain") { weight = 15 }
            else { weight = 55 }
            out.append(contentsOf: Array(repeating: key, count: weight))
        }
        return out.isEmpty ? pool : out
    }

    private func makeClip(_ key: String) -> AnnouncementCatalog.Clip {
        markPlayed(key: key)
        return AnnouncementCatalog.Clip(key: key, text: clips[key] ?? "", lang: Self.language(of: key))
    }

    private static func language(of key: String) -> String {
        if key.hasSuffix("-bg") { return "bg-BG" }
        if key.hasSuffix("-ro") { return "ro-RO" }
        if key.hasSuffix("-hu") { return "hu-HU" }
        if key.hasSuffix("-pl") { return "pl-PL" }
        if key.hasSuffix("-lv") { return "lv-LV" }
        return "tr-TR"
    }

    /// Yerel dildeki bir anahtarın Türkçe karşılığının metni (varsa).
    /// Cihazda yerel TTS sesi yoksa AnnouncementService buna düşer — Türkçe
    /// sesle Bulgarca/Rumence okumak anlaşılmaz olur.
    func turkishText(for key: String) -> String? {
        let base = Self.category(of: key)   // sondaki -NN varyant numarasını at
        guard let range = base.range(of: #"-(bg|ro|hu|pl|lv)$"#, options: .regularExpression)
        else { return nil }
        let trBase = String(base[base.startIndex ..< range.lowerBound]) + "-tr"
        if let direct = clips[trBase] { return direct }
        return (byCategory[trBase] ?? []).sorted().compactMap { clips[$0] }.first
    }

    /// Varış: Türkçe varyant + (varsa) yerel dil karşılaması.
    func arrivalClips(citySlug: String) -> [AnnouncementCatalog.Clip] {
        var result: [AnnouncementCatalog.Clip] = []
        if let tr = pick("arrive-\(citySlug)-tr") ?? pick("arrive-\(citySlug)") {
            result.append(tr)
        }
        for suffix in ["bg", "ro", "hu", "pl", "lv"] {
            let key = "arrive-\(citySlug)-\(suffix)"
            if let text = clips[key] {
                result.append(AnnouncementCatalog.Clip(key: key, text: text, lang: Self.language(of: key)))
                break
            }
        }
        return result
    }
}
