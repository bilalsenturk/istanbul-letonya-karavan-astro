import Foundation
import UIKit

// Saf kuralları canlı veriye bağlar. Kural mantığı burada YOK —
// yalnızca "veri geldi → kurala sor → bütçeye sor → bildir" akışı.
@MainActor
final class TripNotifier: ObservableObject {
    static let shared = TripNotifier()

    private var budget = NotificationBudget()
    private var driveStartedAt: Date?
    private var lastMovingAt: Date?

    /// Ülke kodu → €/L dizel. RoadFeedService besler.
    private var fuelPrices: [String: Double] = [:]

    private init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    // MARK: - Konum tabanlı

    func onLocation(remainingKm: Int?, nextStopName: String?, speedKmh: Int?,
                    currentCountry: String? = nil, nextCountry: String? = nil,
                    currentCode: String? = nil, nextCountryCode: String? = nil,
                    now: Date = Date()) {
        trackDriving(speedKmh: speedKmh, now: now)

        if let km = remainingKm, let name = nextStopName {
            if NotificationRules.arrivalSoon(remainingKm: Double(km)),
               budget.allow(.arrivalSoon, now: now) {
                NotificationManager.shared.notify(
                    title: "\(name)'a 50 km",
                    body: "Kamp yerini şimdi aramaya başla — akşam yer bulmak zor."
                )
            }
        }

        if let seconds = continuousDriveSeconds(now: now),
           NotificationRules.driveBreak(continuousDriveSeconds: seconds),
           budget.allow(.driveBreak, now: now) {
            NotificationManager.shared.notify(
                title: "İki saattir yoldasın",
                body: "Mola ver: bacaklarını aç, su iç, gözlerini dinlendir."
            )
            driveStartedAt = now   // sayacı sıfırla
        }

        // Sınır yaklaşımı — yaklaşık: sıradaki durak farklı ülkedeyse
        // o etapta sınır var, mesafe durağa olan mesafeyle tahmin edilir.
        // currentCountry da açıkça çözülür: ülke bilinmiyorsa (nil) sınır kararı
        // verilemez — "nil != "HU"" her zaman true döner ve bu, ülke henüz
        // belirlenmemişken sahte sınır/yakıt bildirimine yol açardı.
        if let km = remainingKm, let country = nextCountry,
           let currentCountryName = currentCountry, country != currentCountryName {
            onBorderDistance(Double(km), countryName: country, now: now)

            // Sınırı geçmeden önce: buradaki dizel sıradaki ülkeden ucuz mu?
            if let hereCode = currentCode, let nextCode = nextCountryCode,
               let here = fuelPrices[hereCode], let next = fuelPrices[nextCode] {
                onFuel(here: here, next: next,
                       hereCountry: currentCountryName,
                       nextCountry: country, now: now)
            }
        }
    }

    /// Sınıra yaklaşım — çağıran taraf mesafeyi hesaplar.
    func onBorderDistance(_ km: Double, countryName: String, now: Date = Date()) {
        guard NotificationRules.borderApproach(distanceKm: km),
              budget.allow(.borderApproach, now: now) else { return }
        NotificationManager.shared.notify(
            title: "\(countryName) sınırı \(Int(km)) km",
            body: "Pasaport, ruhsat, yeşil kart ve vinyet hazır mı?"
        )
    }

    // MARK: - Para

    func onCurrency(previous: Double, current: Double, code: String, now: Date = Date()) {
        guard NotificationRules.currencyJump(previous: previous, current: current),
              budget.allow(.currencyJump, now: now) else { return }
        let direction = current > previous ? "yükseldi" : "düştü"
        NotificationManager.shared.notify(
            title: "\(code) \(direction)",
            body: String(format: "%.2f → %.2f. Bozdurma planını gözden geçir.", previous, current)
        )
    }

    func onFuel(here: Double, next: Double, hereCountry: String, nextCountry: String, now: Date = Date()) {
        guard let pct = NotificationRules.fuelCheaper(here: here, next: next),
              budget.allow(.fuelPrice, now: now) else { return }
        NotificationManager.shared.notify(
            title: "Burada dizel %\(pct) ucuz",
            body: "\(hereCountry) · \(nextCountry)'dan ucuz. Depoyu burada doldur."
        )
    }

    func updateFuelPrices(_ prices: [FuelPrice]) {
        fuelPrices = Dictionary(uniqueKeysWithValues: prices.map { ($0.country, $0.dieselEur) })
    }

    // MARK: - Pil

    func checkBattery(navigating: Bool, now: Date = Date()) {
        let level = UIDevice.current.batteryLevel
        guard level >= 0,   // -1 = bilinmiyor
              NotificationRules.lowBattery(level: level, navigating: navigating),
              budget.allow(.lowBattery, now: now) else { return }
        NotificationManager.shared.notify(
            title: "Pil %\(Int(level * 100))",
            body: "Navigasyon açık. Şarja tak — haritasız kalmak istemezsin."
        )
    }

    // MARK: - Sürüş süresi takibi

    private func trackDriving(speedKmh: Int?, now: Date) {
        let moving = (speedKmh ?? 0) >= 20
        if moving {
            if driveStartedAt == nil { driveStartedAt = now }
            lastMovingAt = now
        } else if let last = lastMovingAt, now.timeIntervalSince(last) > 10 * 60 {
            // 10 dakikadan uzun duraklama = mola sayılır, sayaç sıfırlanır
            driveStartedAt = nil
            lastMovingAt = nil
        }
    }

    private func continuousDriveSeconds(now: Date) -> TimeInterval? {
        guard let start = driveStartedAt else { return nil }
        return now.timeIntervalSince(start)
    }
}
