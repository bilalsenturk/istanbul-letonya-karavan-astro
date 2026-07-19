import Foundation

// App ↔ widget veri köprüsü (App Group). App yazar, widget okur.
// Not: Ücretsiz kişisel takımda App Group çalışır; yine de suite açılamazsa
// tüm okuma/yazmalar sessizce boşa düşer ve widget "—" gösterir (çökme olmaz).
enum SharedSnapshot {
    static let suiteName = "group.com.bilalsenturk.kuzey"
    static var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    enum Key {
        static let departureAt = "departureAt"       // ISO8601
        static let nextStop = "nextStop"
        static let nextCode = "nextCode"
        static let remainingKm = "remainingKm"
        static let remainingMin = "remainingMin"
        static let spentEur = "spentEur"
        static let budgetMax = "budgetMax"
        static let legProgress = "legProgress"       // 0…100
        static let currentCity = "currentCity"
        static let updatedAt = "updatedAt"           // epoch
        static let simpleMode = "simpleMode"         // Sürüş Focus filtresi (sade mod)
    }

    static func write(_ values: [String: Any]) {
        guard let d = defaults else { return }
        for (k, v) in values { d.set(v, forKey: k) }
        d.set(Date().timeIntervalSince1970, forKey: Key.updatedAt)
    }

    static var departureDate: Date? {
        guard let s = defaults?.string(forKey: Key.departureAt) else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }

    static var isFresh: Bool {
        guard let t = defaults?.double(forKey: Key.updatedAt), t > 0 else { return false }
        return Date().timeIntervalSince1970 - t < 3600
    }
}
