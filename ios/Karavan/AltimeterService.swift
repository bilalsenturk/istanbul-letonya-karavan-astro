import Foundation
import CoreMotion

// Barometre: rakım + basınç. Geçit tırmanışlarında canlı yükseklik; dururken
// hızlı basınç düşüşünden fırtına uyarısı. Barometreli iPhone gerekir
// (simülatörde barometre yok → sessizce kapalı, available = false).
@MainActor
final class AltimeterService: ObservableObject {
    @Published var altitude: Double?      // metre
    @Published var pressureHpa: Double?   // hPa
    @Published var available = false

    /// Yalnızca dururken fırtına kontrolü yapılır — sürerken basınç değişimi irtifadan gelir.
    var stationary = true

    private let altimeter = CMAltimeter()
    private var baselinePressure: Double?
    private var lastStormAlert: Date = .distantPast

    func start() {
        if CMAltimeter.isAbsoluteAltitudeAvailable() {
            available = true
            altimeter.startAbsoluteAltitudeUpdates(to: .main) { [weak self] data, _ in
                guard let self, let data else { return }
                Task { @MainActor in self.altitude = data.altitude }
            }
        }
        if CMAltimeter.isRelativeAltitudeAvailable() {
            available = true
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
                guard let self, let data else { return }
                Task { @MainActor in
                    let hpa = data.pressure.doubleValue * 10   // kPa → hPa
                    self.pressureHpa = hpa
                    if self.altitude == nil { self.altitude = data.relativeAltitude.doubleValue }
                    self.checkStorm(hpa)
                }
            }
        }
    }

    private func checkStorm(_ hpa: Double) {
        // Sürerken baz çizgiyi güncel tut; irtifa kaynaklı düşüşü fırtına sanma.
        guard stationary else { baselinePressure = hpa; return }
        guard let base = baselinePressure else { baselinePressure = hpa; return }

        if base - hpa > 2.0, Date().timeIntervalSince(lastStormAlert) > 3600 {
            lastStormAlert = Date()
            NotificationManager.shared.notify(
                title: "Basınç düşüyor — fırtına yaklaşıyor olabilir",
                body: "Hava kötüleşebilir; kamp/mola planını gözden geçir."
            )
            AnnouncementService.shared.announce(AnnouncementCatalog.Category.storm)
        }
        baselinePressure = base + (hpa - base) * 0.05   // baz çizgiyi yavaş takip et
    }

    func stop() {
        altimeter.stopAbsoluteAltitudeUpdates()
        altimeter.stopRelativeAltitudeUpdates()
    }
}
