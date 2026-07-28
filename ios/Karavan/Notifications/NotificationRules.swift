import Foundation

// Bildirim türleri. Kritik olanlar daha kısa bekleme süresine tabidir —
// sınıra yaklaşırken belge hatırlatması gecikirse işe yaramaz.
enum NotifKind: String, CaseIterable {
    case borderApproach, driveBreak, arrivalSoon
    case currencyJump, fuelPrice
    case journalReminder, dailySummary, lowBattery
    // Letonca kursu. Hiçbiri kritik DEĞİL: yolculuk uygulaması önce yolculuk
    // uygulaması — dil hatırlatması sınır geçişinin önüne geçemez. Ayrı türler
    // olmaları bütçede kendi şeritlerinde kalmalarını sağlıyor: bir Letonca
    // hatırlatması borderApproach'un 10 dakikalık hakkını yiyemez.
    case latvianDaily, latvianStreakRescue, latvianMilestone, latvianDecay

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
    /// `level` negatifse (pil izleme kapalı/bilinmiyor durumu — bkz.
    /// UIDevice.current.batteryLevel dokümantasyonu) düşük pil SAYILMAZ:
    /// aksi halde -1 <= 0.20 her zaman doğru olur ve navigasyon açıkken
    /// pil durumu bilinmese bile sahte "düşük pil" uyarısı üretilir.
    static func lowBattery(level: Float, navigating: Bool) -> Bool {
        guard level >= 0 else { return false }
        return navigating && level <= 0.20
    }
}
