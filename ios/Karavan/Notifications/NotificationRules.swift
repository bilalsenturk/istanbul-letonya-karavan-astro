import Foundation

// Bildirim türleri. Kritik olanlar daha kısa bekleme süresine tabidir —
// sınıra yaklaşırken belge hatırlatması gecikirse işe yaramaz.
enum NotifKind: String, CaseIterable {
    case borderApproach, driveBreak, arrivalSoon
    case currencyJump, fuelPrice
    case journalReminder, dailySummary, lowBattery

    var isCritical: Bool {
        switch self {
        case .borderApproach, .lowBattery: return true
        default: return false
        }
    }
}

// Tetik kararları — SAF fonksiyonlar. Konum/hava/kur girdi, evet-hayır çıktı.
// UI ve sistem API'lerinden ayrı olduğu için cihazsız test edilebiliyor.
enum NotificationRules {
    static func borderApproach(distanceKm: Double) -> Bool {
        distanceKm <= 30
    }

    static func driveBreak(continuousDriveSeconds: TimeInterval) -> Bool {
        continuousDriveSeconds >= 2 * 3600
    }

    static func arrivalSoon(remainingKm: Double) -> Bool {
        remainingKm <= 50
    }

    /// %3 ve üzeri değişim — iki yönde de.
    static func currencyJump(previous: Double, current: Double) -> Bool {
        guard previous > 0 else { return false }
        return abs(current - previous) / previous >= 0.03
    }

    /// Buradaki yakıt sıradaki ülkeden en az %5 ucuzsa yüzde farkını döndürür.
    static func fuelCheaper(here: Double, next: Double) -> Int? {
        guard next > 0, here < next else { return nil }
        let pct = Int(((next - here) / next * 100).rounded())
        return pct >= 5 ? pct : nil
    }

    /// Yalnızca navigasyon açıkken uyarılır — telefon cepteyken %20 pil sorun değil.
    static func lowBattery(level: Float, navigating: Bool) -> Bool {
        navigating && level <= 0.20
    }
}
