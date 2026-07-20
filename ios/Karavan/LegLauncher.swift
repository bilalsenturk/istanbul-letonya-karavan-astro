import Foundation
import MapKit

// "Sonraki rotayı başlat" — tek yerden: kaptan anonsu + kilit ekranı kartı (Live
// Activity) + Apple Haritalar'da sürüş. Hem haritadaki düğme hem kalkış saati
// modalı burayı çağırır ki davranış her yerde aynı olsun.
@MainActor
enum LegLauncher {
    /// Etabı başlat. `openMaps: false` ise yalnızca anons + Live Activity başlar
    /// (kullanıcı navigasyonu kendi açmak isterse).
    static func start(stop: Stop, nav: NavProgressStore, speedKmh: Int?, openMaps: Bool = true) {
        AnnouncementService.shared.announceDeparture(nextStop: stop.name)

        LiveActivityManager.shared.startOrUpdate(
            nextStop: stop.name,
            nextCode: stop.code,
            remainingKm: nav.remainingKm ?? 0,
            remainingMin: nav.remainingMinutes ?? 0,
            speedKmh: speedKmh ?? 0,
            progress: nav.legProgress
        )

        if openMaps { NavApp.openAppleMaps(to: stop) }
    }
}
