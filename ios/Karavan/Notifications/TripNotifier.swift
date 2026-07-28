import Foundation
import UIKit

// Saf kuralları canlı veriye bağlar. Kural mantığı burada YOK —
// yalnızca "veri geldi → kurala sor → bütçeye sor → bildir" akışı.
@MainActor
final class TripNotifier: ObservableObject {
    static let shared = TripNotifier()

    /// Sınır yaklaşımı ve yakıt karşılaştırma bildirimleri KAPALI.
    /// Neden: ikisi de "sıradaki DURAK" verisini sınır konumu yerine kullanıyor —
    /// mesafe sınıra değil sıradaki durağa olan mesafe, ülke adı da sıradaki
    /// durağın ülkesi. Gerçek rotada transit ülkeler (Slovakya, Litvanya) durak
    /// listesinde hiç yok ve bir ülkede birden fazla durak olabiliyor; bu yüzden
    /// bildirim yanlış anda ve/veya yanlış ülke adıyla çıkabiliyor. Yanlış bilgi
    /// vermektense hiç vermemek daha iyi — rota mimarisi geldiğinde (gerçek sınır
    /// noktaları rota geometrisinden hesaplandığında) bu bayrak true yapılabilir.
    static let borderAndFuelEnabled = false

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
                    routeStarted: Bool = true,
                    now: Date = Date()) {
        if RouteAnnouncementPolicy.allowsDrivingReminder(routeStarted: routeStarted) {
            trackDriving(speedKmh: speedKmh, now: now)
        } else {
            resetDriving()
        }

        if let km = remainingKm, let name = nextStopName {
            // Gerçek kalan mesafe başlıkta; bütçe durak başına ayrı sayılır —
            // aynı durağın 50 km çemberinde 45 dk'da bir tekrar atmaz.
            if NotificationRules.arrivalSoon(remainingKm: Double(km)) {
                deliver(.arrivalSoon, key: name, now: now,
                        title: "\(name)'a \(km) km",
                        body: "Kamp yerini şimdi aramaya başla — akşam yer bulmak zor.")
            }
        }

        if RouteAnnouncementPolicy.allowsDrivingReminder(routeStarted: routeStarted),
           let seconds = continuousDriveSeconds(now: now),
           NotificationRules.driveBreak(continuousDriveSeconds: seconds) {
            if deliver(.driveBreak, now: now,
                       title: "İki saattir yoldasın",
                       body: "Mola ver: bacaklarını aç, su iç, gözlerini dinlendir.") {
                driveStartedAt = now   // sayacı sıfırla
            }
        }

        // Sınır yaklaşımı — yaklaşık: sıradaki durak farklı ülkedeyse
        // o etapta sınır var, mesafe durağa olan mesafeyle tahmin edilir.
        // currentCountry da açıkça çözülür: ülke bilinmiyorsa (nil) sınır kararı
        // verilemez — "nil != "HU"" her zaman true döner ve bu, ülke henüz
        // belirlenmemişken sahte sınır/yakıt bildirimine yol açardı.
        //
        // `borderAndFuelEnabled` false olduğu sürece bu blok tamamen atlanır —
        // bkz. bayrağın tanımındaki not: mesafe/ülke bilgisi yanlış.
        if Self.borderAndFuelEnabled,
           let km = remainingKm, let country = nextCountry,
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
        guard NotificationRules.borderApproach(distanceKm: km) else { return }
        deliver(.borderApproach, now: now,
                title: "\(countryName) sınırı \(Int(km)) km",
                body: "Pasaport, ruhsat, yeşil kart ve vinyet hazır mı?")
    }

    // MARK: - Para

    func onCurrency(previous: Double, current: Double, code: String, now: Date = Date()) {
        guard NotificationRules.currencyJump(previous: previous, current: current) else { return }
        let direction = current > previous ? "yükseldi" : "düştü"
        // Bütçe para birimi başına: TRY sıçraması RON/BGN hakkını yemez.
        deliver(.currencyJump, key: code, now: now,
                title: "\(code) \(direction)",
                body: String(format: "%.2f → %.2f. Bozdurma planını gözden geçir.", previous, current))
    }

    func onFuel(here: Double, next: Double, hereCountry: String, nextCountry: String, now: Date = Date()) {
        guard let pct = NotificationRules.fuelCheaper(here: here, next: next) else { return }
        deliver(.fuelPrice, now: now,
                title: "Burada dizel %\(pct) ucuz",
                body: "\(hereCountry) · \(nextCountry)'dan ucuz. Depoyu burada doldur.")
    }

    func updateFuelPrices(_ prices: [FuelPrice]) {
        // Sunucu JSON'unda aynı ülke kodu iki kez gelebilir —
        // uniqueKeysWithValues bu durumda çöker; son kaydı al, yutma.
        fuelPrices = Dictionary(prices.map { ($0.country, $0.dieselEur) }) { _, yeni in yeni }
    }

    // MARK: - Pil

    func checkBattery(navigating: Bool, now: Date = Date()) {
        let level = UIDevice.current.batteryLevel
        guard level >= 0,   // -1 = bilinmiyor
              NotificationRules.lowBattery(level: level, navigating: navigating) else { return }
        deliver(.lowBattery, now: now,
                title: "Pil %\(Int(level * 100))",
                body: "Navigasyon açık. Şarja tak — haritasız kalmak istemezsin.")
    }

    // MARK: - Gönderim (izin + bütçe + iade)

    /// Bütçeyi ancak bildirim gerçekten kurulabiliyorsa harcar:
    /// izin yoksa allow() hiç çağrılmaz; planlama hatasında damga release
    /// ile iade edilir (aksi halde bekleme hakkı boşa yanar).
    /// Bütçe onaylandıysa true döner.
    @discardableResult
    private func deliver(_ kind: NotifKind, key: String? = nil, now: Date,
                         title: String, body: String) -> Bool {
        guard NotificationManager.shared.authorized else { return false }
        guard budget.allow(kind, key: key, now: now) else { return false }
        NotificationManager.shared.notify(title: title, body: body) { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in self?.budget.release(kind, key: key) }
        }
        return true
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

    private func resetDriving() {
        driveStartedAt = nil
        lastMovingAt = nil
    }
}
