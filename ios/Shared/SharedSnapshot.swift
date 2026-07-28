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
        static let navUpdatedAt = "navUpdatedAt"     // epoch — yalnız NAV yazımında
        static let simpleMode = "simpleMode"         // Sürüş Focus filtresi (sade mod)
        static let activeRouteStop = "activeRouteStop"
        static let activeRouteCode = "activeRouteCode"
        static let activeRouteStartedAt = "activeRouteStartedAt"   // epoch
    }

    /// Bu anahtarlardan biri yazıldığında nav verisi de tazelenmiş sayılır.
    private static let navKeys: Set<String> = [Key.nextStop, Key.remainingKm, Key.remainingMin]

    static func write(_ values: [String: Any]) {
        guard let d = defaults else { return }
        for (k, v) in values { d.set(v, forKey: k) }
        let now = Date().timeIntervalSince1970
        d.set(now, forKey: Key.updatedAt)
        // Nav tazeliği ayrı izlenir: harcama ekleme / odak filtresi gibi yazımlar
        // saatler önceki durak-km verisini "taze" göstermesin.
        if values.keys.contains(where: navKeys.contains) {
            d.set(now, forKey: Key.navUpdatedAt)
        }
    }

    static var departureDate: Date? {
        guard let s = defaults?.string(forKey: Key.departureAt) else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }

    static var isFresh: Bool {
        guard let t = defaults?.double(forKey: Key.updatedAt), t > 0 else { return false }
        return Date().timeIntervalSince1970 - t < 3600
    }

    /// Yalnız NAV verisinin (sıradaki durak / kalan km / süre) taze olup olmadığı.
    /// isFresh'ten farkı: herhangi bir yazım değil, son NAV yazımı baz alınır.
    static var isNavFresh: Bool {
        guard let t = defaults?.double(forKey: Key.navUpdatedAt), t > 0 else { return false }
        return Date().timeIntervalSince1970 - t < 3600
    }
}
