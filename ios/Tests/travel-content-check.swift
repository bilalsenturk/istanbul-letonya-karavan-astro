import Foundation

private var failures = 0

private func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    if condition() {
        print("  ✓ \(name)")
    } else {
        failures += 1
        print("  ✗ \(name)")
    }
}

@main
struct TravelContentCheck {
    static func main() {
        let sofia = GeoPoint(latitude: 42.6977, longitude: 23.3219)
        let nearby = GeoPoint(latitude: 42.7236, longitude: 23.2679)
        let far = GeoPoint(latitude: 42.10, longitude: 24.30)

        print("\n=== Küratörlü seyahat içeriği ===")
        check("şehir kampı 25 km içinde kabul edilir",
              CampDistancePolicy.city(maximumKm: 25).accepts(candidate: nearby, destination: sofia, routeDistanceKm: nil))
        check("uzak şehir kampı reddedilir",
              !CampDistancePolicy.city(maximumKm: 25).accepts(candidate: far, destination: sofia, routeDistanceKm: nil))
        check("transit kamp 10 km sapmada kabul edilir",
              CampDistancePolicy.transit(maximumDetourKm: 10).accepts(candidate: nearby, destination: sofia, routeDistanceKm: 9.8))

        let iso = ISO8601DateFormatter()
        let verified = iso.date(from: "2026-04-01T00:00:00Z")!
        let day91 = iso.date(from: "2026-07-01T00:00:01Z")!
        check("90 günü aşan kayıt teyit ister",
              ContentFreshness.requiresReverification(verifiedAt: verified, on: day91))
        check("hedef Türkçe karakterlerden bağımsız çözülür",
              DestinationKey.resolve("Kraków") == "krakow")

        if failures > 0 {
            print("\n❌ \(failures) KONTROL BAŞARISIZ")
            exit(1)
        }
        print("\n✅ SEYAHAT İÇERİĞİ KONTROLLERİ GEÇTİ")
    }
}
