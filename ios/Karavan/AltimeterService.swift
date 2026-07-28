import Foundation
import CoreMotion

// Barometre: rakım + basınç. Geçit tırmanışlarında canlı yükseklik; dururken
// hızlı basınç düşüşünden fırtına uyarısı. Barometreli iPhone gerekir
// (simülatörde barometre yok → sessizce kapalı, available = false).
@MainActor
final class AltimeterService: ObservableObject {
    @Published var altitude: Double?      // geriye uyumlu: mutlak varsa o, yoksa göreli
    @Published var absoluteAltitude: Double?
    @Published var relativeAltitude: Double?
    @Published var altitudeIsRelative = false
    @Published var pressureHpa: Double?   // hPa
    @Published var available = false

    /// Yalnızca dururken fırtına kontrolü yapılır — sürerken basınç değişimi irtifadan gelir.
    /// nil = hız bilinmiyor → kontrol yapma (bilinmeyeni "duruyor" sayma).
    private(set) var stationary: Bool? = nil
    var motionSignalUnavailable = false

    private let altimeter = CMAltimeter()
    private var reference: (hpa: Double, at: Date)?   // fırtına bazı (~1 saatlik sabit pencere)
    private var pressureSamples: [(hpa: Double, at: Date)] = []
    private var lastStormAlert: Date = .distantPast
    private var stationaryScore = 0

    func start() {
        if CMAltimeter.isAbsoluteAltitudeAvailable() {
            available = true
            altimeter.startAbsoluteAltitudeUpdates(to: .main) { [weak self] data, _ in
                guard let self, let data else { return }
                Task { @MainActor in
                    self.absoluteAltitude = data.altitude
                    self.altitude = data.altitude
                    self.altitudeIsRelative = false
                }
            }
        }
        if CMAltimeter.isRelativeAltitudeAvailable() {
            available = true
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
                guard let self, let data else { return }
                Task { @MainActor in
                    let hpa = data.pressure.doubleValue * 10   // kPa → hPa
                    self.pressureHpa = hpa
                    self.relativeAltitude = data.relativeAltitude.doubleValue
                    if self.absoluteAltitude == nil {
                        self.altitude = data.relativeAltitude.doubleValue
                        self.altitudeIsRelative = true
                    }
                    self.checkStorm(hpa)
                }
            }
        }
    }

    func updateMotion(speedKmh: Int?) {
        guard let speedKmh else { return }
        if speedKmh < 5 {
            stationaryScore = min(6, stationaryScore + 1)
        } else if speedKmh > 12 {
            stationaryScore = max(-6, stationaryScore - 2)
        }

        if stationaryScore >= 2 {
            stationary = true
        } else if stationaryScore <= -2 {
            stationary = false
        }
    }

    private func checkStorm(_ hpa: Double) {
        // Sürerken (veya hız bilinmiyorken) bazı güncel tut; irtifa kaynaklı düşüşü fırtına sanma.
        let now = Date()
        guard stationary == true || motionSignalUnavailable else {
            reference = (hpa, now)
            pressureSamples.removeAll()
            return
        }
        guard let ref = reference else { reference = (hpa, now); return }

        pressureSamples.append((hpa, now))
        pressureSamples.removeAll { now.timeIntervalSince($0.at) > 75 * 60 }
        let peak = pressureSamples
            .filter { now.timeIntervalSince($0.at) >= 30 * 60 }
            .max { $0.hpa < $1.hpa }

        // Sabit pencere + kayan fail-safe: düşüş tam saat sınırına bölünürse
        // yüksek örnek hâlâ 75 dk tutulur ve uyarı kaçmaz.
        let fixedDropReady = now.timeIntervalSince(ref.at) >= 3600
        let fixedDrop = fixedDropReady ? ref.hpa - hpa : 0
        let slidingDrop = peak.map { $0.hpa - hpa } ?? 0
        if max(fixedDrop, slidingDrop) >= 2.0, now.timeIntervalSince(lastStormAlert) > 3600 {
            lastStormAlert = now
            NotificationManager.shared.notify(
                title: "Basınç düşüyor — fırtına yaklaşıyor olabilir",
                body: "Hava kötüleşebilir; kamp/mola planını gözden geçir."
            )
            AnnouncementService.shared.announce(AnnouncementCatalog.Category.storm)
        }
        if fixedDropReady { reference = (hpa, now) }   // pencereyi kaydır
    }

    func stop() {
        altimeter.stopAbsoluteAltitudeUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        available = false   // güncellemeler durdu — sensör artık kullanılabilir değil
    }
}
