import Foundation

// Anons klip tipi + durak adı → katalog anahtarı eşlemesi.
// Metinlerin kendisi announcements.json'da (web + gömülü kopya); seçim kuralları
// AnnouncementEngine'de. Böylece anons eklemek için app'i yeniden derlemek gerekmez.
enum AnnouncementCatalog {
    struct Clip: Identifiable {
        let key: String
        let text: String
        var lang: String = "tr-TR"
        var id: String { key }
    }

    /// "Bükreş Güney" → "bukres" (announcements.json anahtarlarıyla uyumlu)
    static func citySlug(for stopName: String) -> String {
        let map: [(String, String)] = [
            ("İstanbul", "istanbul"), ("Sofya", "sofya"), ("Bükreş", "bukres"),
            ("Deva", "deva"), ("Budapeşte", "budapeste"), ("Katowice", "katowice"),
            ("Suwałki", "suwalki"), ("Riga", "riga"),
        ]
        return map.first { stopName.contains($0.0) || $0.0.contains(stopName) }?.1
            ?? stopName.lowercased()
    }

    // Kategori adları (tek yerden, yazım hatası olmasın)
    enum Category {
        static let captain = "captain"
        static let ready = "ready"
        static let morning = "morning"
        static let rest = "rest-reminder"
        static let border = "border-ahead"
        static let deviation = "deviation"
        static let rain = "rain-start"
        static let storm = "storm"
        static let crosswind = "crosswind"
        static let roughRoad = "rough-road"
        static let traffic = "traffic"
        static let speed = "speed-warning"
        static let focus = "focus"
        static let fuelLow = "fuel-low"
        static let campAhead = "camp-ahead"
        static let eta60 = "eta-60"
        static let eta30 = "eta-30"
        static let eta10 = "eta-10"
        static let snack = "snack"
        static let karaoke = "karaoke"
        static let silence = "silence"
        static let familyCouncil = "family-council"
    }
}
