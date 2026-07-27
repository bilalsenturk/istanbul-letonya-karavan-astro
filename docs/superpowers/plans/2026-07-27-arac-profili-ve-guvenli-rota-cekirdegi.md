# Araç Profili ve Güvenli Rota Çekirdeği Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kuzey'e doğrulanabilir araç/enerji profilleri, kalıcı araç garajı, tüketim aralığı ve sağlayıcılardan bağımsız güvenli rota seçme çekirdeği eklemek.

**Architecture:** Bu ilk teslim yalnız saf Swift/Foundation birimleri üretir; MapKit, HERE, TomTom, SwiftUI ve ağ katmanlarına bağlanmaz. `VehicleProfile` araç zarfını, `ConsumptionEstimator` enerji tahminini, `RouteSafetyEngine` sert elemeyi ve yüzde 15 seçim politikasını tanımlar. Sonraki çoklu sağlayıcı ve navigasyon planları bu kararlı arayüzleri kullanır.

**Tech Stack:** Swift 5.9, Foundation, Codable, mevcut `swiftc` tabanlı test düzeni, iOS 17+

## Global Constraints

- Mevcut çalışma ağacındaki kullanıcı değişikliklerine dokunma; bu planda yalnız yeni dosyalar oluştur.
- Üretim kodundan önce davranışı tanımlayan başarısız testi yaz ve beklenen nedenle başarısız olduğunu gör.
- Saf çekirdek MapKit, SwiftUI, Combine, HERE veya TomTom modülü içe aktarmasın.
- Kritik araç ölçüleri kullanıcı tarafından doğrulanmadan rota `araç için doğrulandı` sayılmasın.
- Sert fiziksel/yasal uygunluk süre, ücret veya sürüş karakteriyle takas edilmesin.
- Varsayılan azami süre uzaması `0.15` olsun.
- Sonuç güvenlik, güvenilirlik, konfor ve maliyeti ayrı alanlarda taşısın.
- Apple, HERE, TomTom ve açık motor ortak `RouteProvider` türüyle temsil edilsin.
- Passat B8 + Adria Altea 432 PX başlangıç profili kritik ölçü ve tüketimi uydurmasın; bu alanları kullanıcı doğrulamasına bıraksın.
- Her görev yalnız kendi yeni dosyalarını commit etsin.

---

## File Structure

| Dosya                                            | Sorumluluk                                                                |
| ------------------------------------------------ | ------------------------------------------------------------------------- |
| `ios/Karavan/Routing/VehicleProfile.swift`       | Araç sınıfı, enerji türü, ölçü zarfı, doğrulama ve Passat + Adria taslağı |
| `ios/Karavan/Routing/VehicleGarage.swift`        | Profil koleksiyonu, seçili araç ve atomik JSON kalıcılığı                 |
| `ios/Karavan/Routing/ConsumptionEstimator.swift` | Yakıt/elektrik/PHEV tüketim aralığı ve menzil uygunluğu                   |
| `ios/Karavan/Routing/RouteQualityModels.swift`   | Sağlayıcıdan bağımsız aday, yol kanıtı, seçenek, skor ve karar türleri    |
| `ios/Karavan/Routing/RouteSafetyEngine.swift`    | Sert eleme, puanlama, yüzde 15 pencere ve sürüş karakteri seçimi          |
| `ios/Tests/route-quality-check.swift`            | Saf çekirdeğin deterministik davranış kontrolleri                         |
| `ios/Tests/run-route-quality-check.sh`           | Yeni Swift dosyalarını derleyip test programını çalıştırma                |

## Task 1: Araç profili ve doğrulama zarfı

**Files:**

- Create: `ios/Karavan/Routing/VehicleProfile.swift`
- Create: `ios/Tests/route-quality-check.swift`
- Create: `ios/Tests/run-route-quality-check.sh`

**Interfaces:**

- Produces: `VehiclePowertrain`, `VehicleKind`, `VehicleVerification`, `ConsumptionDataSource`, `ConsumptionRates`, `VehicleEnergyProfile`, `VehicleDimensions`, `VehicleProfile`, `VehicleValidationIssue`
- `VehicleProfile.isReadyForRestrictedRouting: Bool`
- `VehicleProfile.validationIssues: [VehicleValidationIssue]`
- `VehicleProfile.passatAdriaDraft: VehicleProfile`

- [ ] **Step 1: Write the failing vehicle-profile checks**

Create the test helper and these first assertions in `ios/Tests/route-quality-check.swift`:

```swift
import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() { print("  ✓ \(message)") }
    else { fputs("  ✗ \(message)\n", stderr); exit(1) }
}

@main
struct RouteQualityCheck {
    static func main() throws {
        print("\n=== Araç profili ===")
        let draft = VehicleProfile.passatAdriaDraft
        expect(draft.id == "passat-b8-adria-altea-432-px", "hazır profil sabit kimlik taşır")
        expect(draft.kind == .carWithTrailer && draft.powertrain == .diesel, "Passat + Adria doğru sınıflanır")
        expect(!draft.isReadyForRestrictedRouting, "uydurma ölçü olmadan profil doğrulanmış sayılmaz")
        expect(draft.validationIssues.contains(.missingDimensions), "eksik ölçü açıkça raporlanır")

        let dimensions = VehicleDimensions(
            lengthM: 10.4, widthM: 2.3, heightM: 2.58,
            grossWeightKg: 3_650, axleWeightKg: 1_500, axleCount: 3
        )
        var confirmed = draft
        confirmed.declaredDimensions = dimensions
        confirmed.routingEnvelope = dimensions
        confirmed.verification = .confirmed
        expect(confirmed.isReadyForRestrictedRouting, "doğrulanmış geçerli zarf rota için hazırdır")

        var invalid = confirmed
        invalid.routingEnvelope = VehicleDimensions(
            lengthM: -1, widthM: 2.3, heightM: 2.58,
            grossWeightKg: 3_650, axleWeightKg: nil, axleCount: 0
        )
        expect(!invalid.isReadyForRestrictedRouting, "geçersiz fiziksel değer reddedilir")
        expect(invalid.validationIssues.contains(.invalidDimensions), "geçersiz ölçü nedeni korunur")
    }
}
```

Create `ios/Tests/run-route-quality-check.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/../Karavan/Routing"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

swiftc -warnings-as-errors -O -o "$OUT/route-quality-check" \
  "$DIR/route-quality-check.swift" \
  "$SRC/VehicleProfile.swift"
"$OUT/route-quality-check"
```

- [ ] **Step 2: Run the check and verify RED**

Run:

```bash
chmod +x ios/Tests/run-route-quality-check.sh
./ios/Tests/run-route-quality-check.sh
```

Expected: compilation fails because `VehicleProfile` and related types do not exist.

- [ ] **Step 3: Implement the minimal vehicle domain**

Create `ios/Karavan/Routing/VehicleProfile.swift` with these exact public shapes:

```swift
import Foundation

enum VehiclePowertrain: String, Codable, CaseIterable, Sendable {
    case diesel, gasoline, lpgCng, hybrid, plugInHybrid, electric
}

enum VehicleKind: String, Codable, CaseIterable, Sendable {
    case car, van, motorhome, carWithTrailer
}

enum VehicleVerification: String, Codable, Sendable {
    case needsConfirmation, confirmed
}

enum ConsumptionDataSource: String, Codable, Sendable {
    case userObserved, manufacturer, estimated

    var uncertaintyFraction: Double {
        switch self {
        case .userObserved: 0.08
        case .manufacturer: 0.15
        case .estimated: 0.25
        }
    }
}

struct ConsumptionRates: Codable, Equatable, Sendable {
    var urban: Double
    var mixed: Double
    var highway: Double
    var source: ConsumptionDataSource

    var isValid: Bool {
        [urban, mixed, highway].allSatisfy { $0.isFinite && $0 > 0 && $0 < 100 }
    }
}

struct VehicleEnergyProfile: Codable, Equatable, Sendable {
    var fuelCapacityLiters: Double?
    var usableBatteryKWh: Double?
    var fuelLitersPer100Km: ConsumptionRates?
    var electricityKWhPer100Km: ConsumptionRates?
    var minimumReserveFraction: Double
    var baselineIncludesTrailer: Bool

    var isValid: Bool {
        minimumReserveFraction.isFinite
            && (0 ... 0.5).contains(minimumReserveFraction)
            && fuelCapacityLiters.map { $0.isFinite && $0 > 0 }.unwrap(or: true)
            && usableBatteryKWh.map { $0.isFinite && $0 > 0 }.unwrap(or: true)
            && fuelLitersPer100Km.map(\.isValid).unwrap(or: true)
            && electricityKWhPer100Km.map(\.isValid).unwrap(or: true)
    }
}

struct VehicleDimensions: Codable, Equatable, Sendable {
    var lengthM: Double
    var widthM: Double
    var heightM: Double
    var grossWeightKg: Double
    var axleWeightKg: Double?
    var axleCount: Int

    var isValid: Bool {
        lengthM.isFinite && lengthM > 0 && lengthM <= 30
            && widthM.isFinite && widthM > 0 && widthM <= 4
            && heightM.isFinite && heightM > 0 && heightM <= 5
            && grossWeightKg.isFinite && grossWeightKg > 0 && grossWeightKg <= 60_000
            && axleWeightKg.map { $0.isFinite && $0 > 0 && $0 <= grossWeightKg }.unwrap(or: true)
            && (1 ... 10).contains(axleCount)
    }
}

enum VehicleValidationIssue: String, Equatable, Sendable {
    case missingDimensions, invalidDimensions, unconfirmedDimensions, invalidEnergyProfile
}

struct VehicleProfile: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var kind: VehicleKind
    var powertrain: VehiclePowertrain
    var hasTrailer: Bool
    var declaredDimensions: VehicleDimensions?
    var routingEnvelope: VehicleDimensions?
    var maxSafeSpeedKmh: Int
    var emissionClass: String?
    var energy: VehicleEnergyProfile
    var verification: VehicleVerification

    var validationIssues: [VehicleValidationIssue] {
        var issues: [VehicleValidationIssue] = []
        if declaredDimensions == nil || routingEnvelope == nil {
            issues.append(.missingDimensions)
        }
        if declaredDimensions.map({ !$0.isValid }) == true
            || routingEnvelope.map({ !$0.isValid }) == true {
            issues.append(.invalidDimensions)
        }
        if verification != .confirmed {
            issues.append(.unconfirmedDimensions)
        }
        if !energy.isValid {
            issues.append(.invalidEnergyProfile)
        }
        return issues
    }
    var isReadyForRestrictedRouting: Bool { validationIssues.isEmpty }

    static let passatAdriaDraft = VehicleProfile(
        id: "passat-b8-adria-altea-432-px",
        name: "VW Passat B8 + Adria Altea 432 PX",
        kind: .carWithTrailer,
        powertrain: .diesel,
        hasTrailer: true,
        declaredDimensions: nil,
        routingEnvelope: nil,
        maxSafeSpeedKmh: 90,
        emissionClass: nil,
        energy: VehicleEnergyProfile(
            fuelCapacityLiters: nil,
            usableBatteryKWh: nil,
            fuelLitersPer100Km: nil,
            electricityKWhPer100Km: nil,
            minimumReserveFraction: 0.2,
            baselineIncludesTrailer: false
        ),
        verification: .needsConfirmation
    )
}

private extension Optional where Wrapped == Bool {
    func unwrap(or fallback: Bool) -> Bool { self ?? fallback }
}
```

Implement `validationIssues` in this order: missing routing envelope, invalid declared or routing dimensions, unconfirmed dimensions, invalid energy profile. Do not require consumption to approve physical routing.

- [ ] **Step 4: Run the check and verify GREEN**

Run: `./ios/Tests/run-route-quality-check.sh`

Expected: all five vehicle assertions pass with no compiler warning.

- [ ] **Step 5: Commit the vehicle domain**

```bash
git add ios/Karavan/Routing/VehicleProfile.swift ios/Tests/route-quality-check.swift ios/Tests/run-route-quality-check.sh
git commit -m "feat: add verified vehicle profile domain"
```

## Task 2: Kalıcı araç garajı

**Files:**

- Create: `ios/Karavan/Routing/VehicleGarage.swift`
- Modify: `ios/Tests/route-quality-check.swift`
- Modify: `ios/Tests/run-route-quality-check.sh`

**Interfaces:**

- Consumes: `VehicleProfile`, `VehicleProfile.passatAdriaDraft`
- Produces: `VehicleGarage`, `VehicleGarageRepository`
- `VehicleGarage.selectedProfile: VehicleProfile?`
- `VehicleGarage.upsert(_:)`, `select(id:)`, `remove(id:)`
- `VehicleGarageRepository.load() throws -> VehicleGarage`
- `VehicleGarageRepository.save(_:) throws`

- [ ] **Step 1: Add failing garage behavior checks**

Append inside `RouteQualityCheck.main()`:

```swift
print("\n=== Araç garajı ===")
let tempRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tempRoot) }
let repository = VehicleGarageRepository(fileURL: tempRoot.appendingPathComponent("garage.json"))

var garage = try repository.load()
expect(garage.profiles == [.passatAdriaDraft], "ilk açılışta Passat + Adria taslağı tohumlanır")
expect(garage.selectedProfile?.id == VehicleProfile.passatAdriaDraft.id, "tohum profil seçilir")

var second = VehicleProfile.passatAdriaDraft
second.id = "electric-car"
second.name = "Elektrikli otomobil"
second.kind = .car
second.powertrain = .electric
second.hasTrailer = false
garage.upsert(second)
garage.select(id: second.id)
try repository.save(garage)

let reloaded = try repository.load()
expect(reloaded.profiles.count == 2, "garaj atomik JSON kaydından açılır")
expect(reloaded.selectedProfile?.id == second.id, "seçili araç yeniden açılışta korunur")

var removing = reloaded
removing.remove(id: second.id)
expect(removing.selectedProfile?.id == VehicleProfile.passatAdriaDraft.id, "seçili araç silinince ilk profil seçilir")
```

Add `"$SRC/VehicleGarage.swift"` to the compile command.

- [ ] **Step 2: Run the check and verify RED**

Run: `./ios/Tests/run-route-quality-check.sh`

Expected: compilation fails because `VehicleGarageRepository` does not exist.

- [ ] **Step 3: Implement garage collection and persistence**

Create `ios/Karavan/Routing/VehicleGarage.swift`:

```swift
import Foundation

struct VehicleGarage: Codable, Equatable, Sendable {
    private(set) var profiles: [VehicleProfile]
    private(set) var selectedProfileID: String?

    init(profiles: [VehicleProfile] = [.passatAdriaDraft], selectedProfileID: String? = nil) {
        self.profiles = profiles
        self.selectedProfileID = selectedProfileID ?? profiles.first?.id
        reconcileSelection()
    }

    var selectedProfile: VehicleProfile? {
        selectedProfileID.flatMap { id in profiles.first { $0.id == id } }
    }

    mutating func upsert(_ profile: VehicleProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile }
        else { profiles.append(profile) }
        reconcileSelection()
    }

    mutating func select(id: String) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        selectedProfileID = id
    }

    mutating func remove(id: String) {
        profiles.removeAll { $0.id == id }
        reconcileSelection()
    }

    private mutating func reconcileSelection() {
        if selectedProfile == nil { selectedProfileID = profiles.first?.id }
    }
}

struct VehicleGarageRepository: Sendable {
    let fileURL: URL

    init(fileURL: URL) { self.fileURL = fileURL }

    func load() throws -> VehicleGarage {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return VehicleGarage() }
        return try JSONDecoder().decode(VehicleGarage.self, from: Data(contentsOf: fileURL))
    }

    func save(_ garage: VehicleGarage) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(garage).write(to: fileURL, options: [.atomic])
    }
}
```

Do not swallow corrupt JSON. A future UI store must distinguish a missing garage from damaged user data.

- [ ] **Step 4: Run the check and verify GREEN**

Run: `./ios/Tests/run-route-quality-check.sh`

Expected: vehicle and garage sections pass.

- [ ] **Step 5: Commit the garage**

```bash
git add ios/Karavan/Routing/VehicleGarage.swift ios/Tests/route-quality-check.swift ios/Tests/run-route-quality-check.sh
git commit -m "feat: persist vehicle garage profiles"
```

## Task 3: Yakıt, elektrik ve PHEV tüketim aralığı

**Files:**

- Create: `ios/Karavan/Routing/ConsumptionEstimator.swift`
- Modify: `ios/Tests/route-quality-check.swift`
- Modify: `ios/Tests/run-route-quality-check.sh`

**Interfaces:**

- Consumes: `VehicleProfile.energy`, `VehicleProfile.powertrain`, `VehicleProfile.hasTrailer`
- Produces: `ConsumptionContext`, `EstimateRange`, `EnergyEstimate`, `ConsumptionEstimator.estimate(profile:context:)`

- [ ] **Step 1: Add failing consumption checks**

Add a local helper that starts from a confirmed profile, then append:

```swift
print("\n=== Tüketim ===")
let fuelRates = ConsumptionRates(urban: 11, mixed: 9, highway: 10, source: .userObserved)
var diesel = confirmedProfile(powertrain: .diesel, hasTrailer: true)
diesel.energy.fuelCapacityLiters = 66
diesel.energy.fuelLitersPer100Km = fuelRates
diesel.energy.baselineIncludesTrailer = true
let dieselEstimate = ConsumptionEstimator.estimate(
    profile: diesel,
    context: ConsumptionContext(
        distanceKm: 500, motorwayShare: 0.8, urbanShare: 0.05,
        ascentMeters: 900, ambientTemperatureC: 18, headwindKmh: 10
    )
)
expect(dieselEstimate?.fuelLiters?.expected ?? 0 > 45, "dizel karavan tüketimi mesafeyle hesaplanır")
expect(dieselEstimate?.fuelLiters?.lower ?? 0 < dieselEstimate?.fuelLiters?.upper ?? 0, "tahmin tek sayı yerine aralık verir")

var ev = confirmedProfile(powertrain: .electric, hasTrailer: false)
ev.energy.usableBatteryKWh = 75
ev.energy.electricityKWhPer100Km = ConsumptionRates(urban: 17, mixed: 19, highway: 23, source: .manufacturer)
ev.energy.minimumReserveFraction = 0.15
let evEstimate = ConsumptionEstimator.estimate(
    profile: ev,
    context: ConsumptionContext(
        distanceKm: 350, motorwayShare: 0.9, urbanShare: 0,
        ascentMeters: 300, ambientTemperatureC: 0, headwindKmh: 20
    )
)
expect(evEstimate?.electricityKWh != nil, "elektrikli araç kWh aralığı üretir")
expect(evEstimate?.reachableWithoutStop == false, "rezervi aşan EV rotası şarj ister")

var phev = confirmedProfile(powertrain: .plugInHybrid, hasTrailer: false)
phev.energy.usableBatteryKWh = 18
phev.energy.electricityKWhPer100Km = ConsumptionRates(urban: 18, mixed: 20, highway: 24, source: .manufacturer)
phev.energy.fuelLitersPer100Km = ConsumptionRates(urban: 7, mixed: 6, highway: 6.5, source: .manufacturer)
let phevEstimate = ConsumptionEstimator.estimate(
    profile: phev,
    context: ConsumptionContext(
        distanceKm: 300, motorwayShare: 0.8, urbanShare: 0.05,
        ascentMeters: 0, ambientTemperatureC: 20, headwindKmh: 0
    )
)
expect(phevEstimate?.electricityKWh != nil && phevEstimate?.fuelLiters != nil, "PHEV batarya ve yakıtı ayrı gösterir")
```

Add this helper above `@main` in the test file:

```swift
func confirmedProfile(powertrain: VehiclePowertrain, hasTrailer: Bool) -> VehicleProfile {
    let dimensions = VehicleDimensions(
        lengthM: hasTrailer ? 10.4 : 4.8,
        widthM: hasTrailer ? 2.3 : 1.85,
        heightM: hasTrailer ? 2.58 : 1.5,
        grossWeightKg: hasTrailer ? 3_650 : 1_900,
        axleWeightKg: hasTrailer ? 1_500 : 1_100,
        axleCount: hasTrailer ? 3 : 2
    )
    return VehicleProfile(
        id: "fixture-\(powertrain.rawValue)-\(hasTrailer)",
        name: "Test aracı",
        kind: hasTrailer ? .carWithTrailer : .car,
        powertrain: powertrain,
        hasTrailer: hasTrailer,
        declaredDimensions: dimensions,
        routingEnvelope: dimensions,
        maxSafeSpeedKmh: hasTrailer ? 90 : 120,
        emissionClass: nil,
        energy: VehicleEnergyProfile(
            fuelCapacityLiters: nil,
            usableBatteryKWh: nil,
            fuelLitersPer100Km: nil,
            electricityKWhPer100Km: nil,
            minimumReserveFraction: 0.15,
            baselineIncludesTrailer: false
        ),
        verification: .confirmed
    )
}
```

Add `"$SRC/ConsumptionEstimator.swift"` to the compile command.

- [ ] **Step 2: Run the check and verify RED**

Run: `./ios/Tests/run-route-quality-check.sh`

Expected: compilation fails because `ConsumptionEstimator` does not exist.

- [ ] **Step 3: Implement deterministic estimation**

Create these types in `ios/Karavan/Routing/ConsumptionEstimator.swift`:

```swift
import Foundation

struct ConsumptionContext: Equatable, Sendable {
    var distanceKm: Double
    var motorwayShare: Double
    var urbanShare: Double
    var ascentMeters: Double
    var ambientTemperatureC: Double
    var headwindKmh: Double
}

struct EstimateRange: Equatable, Sendable {
    var lower: Double
    var expected: Double
    var upper: Double
}

struct EnergyEstimate: Equatable, Sendable {
    var fuelLiters: EstimateRange?
    var electricityKWh: EstimateRange?
    var reachableWithoutStop: Bool
}

enum ConsumptionEstimator {
    static func estimate(profile: VehicleProfile, context: ConsumptionContext) -> EnergyEstimate? {
        guard profile.energy.isValid,
              context.distanceKm.isFinite, context.distanceKm >= 0,
              context.motorwayShare.isFinite, context.urbanShare.isFinite,
              context.ascentMeters.isFinite, context.ascentMeters >= 0,
              context.ambientTemperatureC.isFinite,
              context.headwindKmh.isFinite
        else { return nil }

        let shares = normalizedShares(motorway: context.motorwayShare, urban: context.urbanShare)
        let commonMultiplier = trailerMultiplier(profile)
            * (1 + min(0.20, context.ascentMeters / 100_000))
            * (1 + min(0.25, max(0, context.headwindKmh) / 200))

        switch profile.powertrain {
        case .diesel, .gasoline, .lpgCng, .hybrid:
            guard let rates = profile.energy.fuelLitersPer100Km else { return nil }
            let expected = context.distanceKm / 100
                * blendedRate(rates, shares: shares)
                * commonMultiplier
                * combustionTemperatureMultiplier(context.ambientTemperatureC)
            let result = range(expected: expected, source: rates.source)
            let reachable = profile.energy.fuelCapacityLiters.map {
                result.expected <= $0 * (1 - profile.energy.minimumReserveFraction)
            } ?? true
            return EnergyEstimate(fuelLiters: result, electricityKWh: nil, reachableWithoutStop: reachable)

        case .electric:
            guard let rates = profile.energy.electricityKWhPer100Km,
                  let capacity = profile.energy.usableBatteryKWh
            else { return nil }
            let expected = context.distanceKm / 100
                * blendedRate(rates, shares: shares)
                * commonMultiplier
                * electricTemperatureMultiplier(context.ambientTemperatureC)
            let result = range(expected: expected, source: rates.source)
            let available = capacity * (1 - profile.energy.minimumReserveFraction)
            return EnergyEstimate(
                fuelLiters: nil,
                electricityKWh: result,
                reachableWithoutStop: result.expected <= available
            )

        case .plugInHybrid:
            guard let electricRates = profile.energy.electricityKWhPer100Km,
                  let fuelRates = profile.energy.fuelLitersPer100Km,
                  let capacity = profile.energy.usableBatteryKWh
            else { return nil }
            let electricRatePerKm = blendedRate(electricRates, shares: shares) / 100
                * commonMultiplier
                * electricTemperatureMultiplier(context.ambientTemperatureC)
            let available = capacity * (1 - profile.energy.minimumReserveFraction)
            let electricDistance = electricRatePerKm > 0
                ? min(context.distanceKm, available / electricRatePerKm)
                : 0
            let electricity = range(
                expected: electricDistance * electricRatePerKm,
                source: electricRates.source
            )
            let fuelDistance = max(0, context.distanceKm - electricDistance)
            let fuelExpected = fuelDistance / 100
                * blendedRate(fuelRates, shares: shares)
                * commonMultiplier
                * combustionTemperatureMultiplier(context.ambientTemperatureC)
            let fuel = range(expected: fuelExpected, source: fuelRates.source)
            let fuelReachable = profile.energy.fuelCapacityLiters.map {
                fuel.expected <= $0 * (1 - profile.energy.minimumReserveFraction)
            } ?? true
            return EnergyEstimate(
                fuelLiters: fuel,
                electricityKWh: electricity,
                reachableWithoutStop: fuelReachable
            )
        }
    }

    private static func normalizedShares(motorway: Double, urban: Double) -> (motorway: Double, urban: Double, mixed: Double) {
        let motorway = min(1, max(0, motorway))
        let urban = min(1, max(0, urban))
        let total = motorway + urban
        guard total > 1 else { return (motorway, urban, 1 - total) }
        return (motorway / total, urban / total, 0)
    }

    private static func blendedRate(
        _ rates: ConsumptionRates,
        shares: (motorway: Double, urban: Double, mixed: Double)
    ) -> Double {
        rates.highway * shares.motorway
            + rates.urban * shares.urban
            + rates.mixed * shares.mixed
    }

    private static func trailerMultiplier(_ profile: VehicleProfile) -> Double {
        profile.hasTrailer && !profile.energy.baselineIncludesTrailer ? 1.25 : 1
    }

    private static func electricTemperatureMultiplier(_ temperature: Double) -> Double {
        if temperature < 5 { return 1.15 }
        if temperature > 30 { return 1.08 }
        return 1
    }

    private static func combustionTemperatureMultiplier(_ temperature: Double) -> Double {
        temperature < 0 || temperature > 35 ? 1.05 : 1
    }

    private static func range(expected: Double, source: ConsumptionDataSource) -> EstimateRange {
        let uncertainty = source.uncertaintyFraction
        return EstimateRange(
            lower: max(0, expected * (1 - uncertainty)),
            expected: max(0, expected),
            upper: max(0, expected * (1 + uncertainty))
        )
    }
}
```

Use these explicit factors:

- Remaining share: `max(0, 1 - clamp(motorwayShare) - clamp(urbanShare))`; renormalize if the two supplied shares exceed 1.
- Trailer: `1.25` only when `hasTrailer` and `baselineIncludesTrailer == false`.
- Ascent: `1 + min(0.20, ascentMeters / 100_000)`.
- Headwind: `1 + min(0.25, max(0, headwindKmh) / 200)`.
- EV/PHEV temperature: `1.15` below 5°C, `1.08` above 30°C, otherwise `1`.
- Combustion temperature: `1.05` below 0°C or above 35°C, otherwise `1`.
- EV reachability: expected electricity must not exceed `usableBatteryKWh * (1 - minimumReserveFraction)`.
- PHEV uses battery up to the same reserve boundary, then applies fuel consumption to the remaining distance.
- Fuel-only reachability uses `fuelCapacityLiters * (1 - minimumReserveFraction)` when capacity exists.

Return `nil` for invalid contexts, invalid energy profiles or missing rates required by the selected powertrain.

- [ ] **Step 4: Run the check and verify GREEN**

Run: `./ios/Tests/run-route-quality-check.sh`

Expected: diesel, EV and PHEV checks pass without warning.

- [ ] **Step 5: Commit the estimator**

```bash
git add ios/Karavan/Routing/ConsumptionEstimator.swift ios/Tests/route-quality-check.swift ios/Tests/run-route-quality-check.sh
git commit -m "feat: estimate route energy ranges"
```

## Task 4: Ortak rota kanıtı ve sert eleme

**Files:**

- Create: `ios/Karavan/Routing/RouteQualityModels.swift`
- Create: `ios/Karavan/Routing/RouteSafetyEngine.swift`
- Modify: `ios/Tests/route-quality-check.swift`
- Modify: `ios/Tests/run-route-quality-check.sh`

**Interfaces:**

- Consumes: `VehicleProfile.routingEnvelope`, `VehicleProfile.isReadyForRestrictedRouting`
- Produces: `RouteProvider`, `RoutingPreferenceStyle`, `RoutePreferences`, `RoadClass`, `RoadSurface`, `RoadFeature`, `RouteSectionEvidence`, `RouteCandidate`, `HardRouteExclusion`, `RouteScores`, `RouteAssessment`, `RouteDecisionStatus`, `RouteReason`, `RouteDecision`
- `RouteSafetyEngine.assess(candidate:vehicle:preferences:) -> RouteAssessment`

- [ ] **Step 1: Add failing hard-exclusion checks**

Add this helper above `@main` after the route model types become available:

```swift
func candidate(
    id: String,
    duration: Int,
    sections: [RouteSectionEvidence],
    provider: RouteProvider = .here,
    tollCostEUR: Double = 0,
    energyCostEUR: Double? = nil
) -> RouteCandidate {
    RouteCandidate(
        id: id,
        provider: provider,
        durationMinutes: duration,
        distanceKm: sections.reduce(0) { $0 + $1.lengthKm },
        tollCostEUR: tollCostEUR,
        estimatedEnergyCostEUR: energyCostEUR,
        sections: sections
    )
}
```

Append these checks:

```swift
print("\n=== Sert rota kuralları ===")
let routeVehicle = confirmedProfile(powertrain: .diesel, hasTrailer: true)
let baseSection = RouteSectionEvidence(
    lengthKm: 20, roadClass: .motorway, isDivided: true, surface: .smoothPaved,
    features: [], maxHeightM: 4.5, maxWidthM: 3.2, maxWeightKg: 20_000,
    trailerAllowed: true, accessAllowed: true, isClosed: false,
    gradientPercent: 1, turnLoad: 0.05, crosswindKmh: 10,
    restrictionCoverage: 1, sourceCount: 3
)

var lowBridge = baseSection
lowBridge.maxHeightM = (routeVehicle.routingEnvelope?.heightM ?? 0) - 0.01
let lowAssessment = RouteSafetyEngine.assess(
    candidate: candidate(id: "low", duration: 60, sections: [lowBridge]),
    vehicle: routeVehicle,
    preferences: .balanced
)
expect(lowAssessment.exclusions.contains(.heightLimit), "alçak köprü rotayı sert eler")

var closed = baseSection
closed.isClosed = true
expect(RouteSafetyEngine.assess(
    candidate: candidate(id: "closed", duration: 55, sections: [closed]),
    vehicle: routeVehicle, preferences: .balanced
).exclusions.contains(.roadClosed), "kapanmış yol sert elenir")

var trailerForbidden = baseSection
trailerForbidden.trailerAllowed = false
expect(RouteSafetyEngine.assess(
    candidate: candidate(id: "trailer", duration: 55, sections: [trailerForbidden]),
    vehicle: routeVehicle, preferences: .balanced
).exclusions.contains(.trailerForbidden), "römork yasağı sert elenir")

var unknown = baseSection
unknown.restrictionCoverage = 0.2
unknown.sourceCount = 1
unknown.maxHeightM = nil
let unknownAssessment = RouteSafetyEngine.assess(
    candidate: candidate(id: "unknown", duration: 55, sections: [unknown]),
    vehicle: routeVehicle, preferences: .balanced
)
expect(unknownAssessment.exclusions.isEmpty, "bilinmeyen kısıt sahte sert yasak üretmez")
expect(unknownAssessment.scores.reliability < 50, "bilinmeyen kısıt güvenilirliği düşürür")
```

Add both new production files to the compile command.

- [ ] **Step 2: Run the check and verify RED**

Run: `./ios/Tests/run-route-quality-check.sh`

Expected: compilation fails because `RouteSectionEvidence` and `RouteSafetyEngine` do not exist.

- [ ] **Step 3: Define the shared route types**

Create `ios/Karavan/Routing/RouteQualityModels.swift` with these shapes:

```swift
import Foundation

enum RouteProvider: String, Codable, CaseIterable, Sendable { case apple, here, tomTom, open }
enum RoutingPreferenceStyle: String, Codable, CaseIterable, Sendable { case balanced, motorway, comfort, economy }
enum RoadClass: String, Codable, Sendable { case motorway, trunk, primary, secondary, local, service }
enum RoadSurface: String, Codable, Sendable { case smoothPaved, paved, rough, unpaved, unknown }
enum RoadFeature: String, Codable, Hashable, Sendable { case tunnel, ferry, carTrain }

struct RoutePreferences: Equatable, Sendable {
    var style: RoutingPreferenceStyle
    var maxDetourFraction: Double
    var avoidUnpaved: Bool
    var avoidFerries: Bool
    var avoidTunnels: Bool

    static let balanced = RoutePreferences(
        style: .balanced, maxDetourFraction: 0.15,
        avoidUnpaved: true, avoidFerries: false, avoidTunnels: false
    )
}

struct RouteSectionEvidence: Equatable, Sendable {
    var lengthKm: Double
    var roadClass: RoadClass
    var isDivided: Bool
    var surface: RoadSurface
    var features: Set<RoadFeature>
    var maxHeightM: Double?
    var maxWidthM: Double?
    var maxWeightKg: Double?
    var trailerAllowed: Bool?
    var accessAllowed: Bool?
    var isClosed: Bool
    var gradientPercent: Double
    var turnLoad: Double
    var crosswindKmh: Double?
    var restrictionCoverage: Double
    var sourceCount: Int
}

struct RouteCandidate: Identifiable, Equatable, Sendable {
    var id: String
    var provider: RouteProvider
    var durationMinutes: Int
    var distanceKm: Double
    var tollCostEUR: Double
    var estimatedEnergyCostEUR: Double?
    var sections: [RouteSectionEvidence]
}

enum HardRouteExclusion: String, Equatable, Sendable {
    case vehicleNeedsConfirmation, invalidCandidate, roadClosed, heightLimit, widthLimit,
         weightLimit, trailerForbidden, accessForbidden, unpavedDisallowed,
         ferryDisallowed, tunnelDisallowed
}

struct RouteScores: Equatable, Sendable {
    var safety: Int
    var reliability: Int
    var comfort: Int
    var totalCostEUR: Double?
}

struct RouteAssessment: Equatable, Sendable {
    var candidate: RouteCandidate
    var exclusions: [HardRouteExclusion]
    var scores: RouteScores
    var motorwayShare: Double
    var localRoadKm: Double
    var roughRoadKm: Double
    var unknownRestrictionKm: Double
}

enum RouteDecisionStatus: String, Equatable, Sendable { case selected, requiresVehicleConfirmation, noEligibleRoute }
enum RouteReason: String, Equatable, Sendable {
    case highestSafety, moreMotorway, lessLocalRoad, smootherSurface, strongerConsensus, lowerCost
}

struct RouteDecision: Equatable, Sendable {
    var status: RouteDecisionStatus
    var selected: RouteAssessment?
    var fastestEligible: RouteAssessment?
    var saferOutsideWindow: RouteAssessment?
    var rejected: [RouteAssessment]
    var reasons: [RouteReason]
}
```

- [ ] **Step 4: Implement hard assessment and separate scores**

In `ios/Karavan/Routing/RouteSafetyEngine.swift`, implement:

```swift
import Foundation

enum RouteSafetyEngine {
    static func assess(
        candidate: RouteCandidate,
        vehicle: VehicleProfile,
        preferences: RoutePreferences
    ) -> RouteAssessment {
        var exclusions: [HardRouteExclusion] = []
        func add(_ exclusion: HardRouteExclusion) {
            if !exclusions.contains(exclusion) { exclusions.append(exclusion) }
        }

        if !vehicle.isReadyForRestrictedRouting { add(.vehicleNeedsConfirmation) }
        let validSections = candidate.sections.allSatisfy {
            $0.lengthKm.isFinite && $0.lengthKm >= 0
                && $0.gradientPercent.isFinite
                && $0.turnLoad.isFinite
                && $0.restrictionCoverage.isFinite
        }
        if candidate.sections.isEmpty
            || !validSections
            || candidate.durationMinutes <= 0
            || !candidate.distanceKm.isFinite
            || candidate.distanceKm <= 0 {
            add(.invalidCandidate)
        }

        for section in candidate.sections {
            if section.isClosed { add(.roadClosed) }
            if section.accessAllowed == false { add(.accessForbidden) }
            if vehicle.hasTrailer && section.trailerAllowed == false { add(.trailerForbidden) }
            if preferences.avoidUnpaved && section.surface == .unpaved { add(.unpavedDisallowed) }
            if preferences.avoidFerries && section.features.contains(.ferry) { add(.ferryDisallowed) }
            if preferences.avoidTunnels && section.features.contains(.tunnel) { add(.tunnelDisallowed) }

            if let envelope = vehicle.routingEnvelope {
                if let limit = section.maxHeightM, envelope.heightM > limit { add(.heightLimit) }
                if let limit = section.maxWidthM, envelope.widthM > limit { add(.widthLimit) }
                if let limit = section.maxWeightKg, envelope.grossWeightKg > limit { add(.weightLimit) }
            }
        }

        let totalLength = candidate.sections.reduce(0) { $0 + max(0, $1.lengthKm) }
        guard totalLength > 0 else {
            return RouteAssessment(
                candidate: candidate,
                exclusions: exclusions,
                scores: RouteScores(safety: 0, reliability: 0, comfort: 0, totalCostEUR: nil),
                motorwayShare: 0,
                localRoadKm: 0,
                roughRoadKm: 0,
                unknownRestrictionKm: 0
            )
        }

        var motorwayKm = 0.0
        var localKm = 0.0
        var roughKm = 0.0
        var unknownKm = 0.0
        var safetyPenalty = 0.0
        var comfortPenalty = 0.0
        var reliabilityTotal = 0.0

        for section in candidate.sections {
            let length = max(0, section.lengthKm)
            if section.roadClass == .motorway { motorwayKm += length }
            if section.roadClass == .local || section.roadClass == .service { localKm += length }
            if section.surface == .rough || section.surface == .unpaved { roughKm += length }

            let coverage = min(1, max(0, section.restrictionCoverage))
            unknownKm += length * (1 - coverage)
            let sourceRatio = min(1, Double(max(0, section.sourceCount)) / 3)
            reliabilityTotal += length * (0.7 * coverage + 0.3 * sourceRatio)

            var sectionSafetyPenalty = 0.0
            if section.surface == .rough { sectionSafetyPenalty += 0.25 }
            if section.surface == .unpaved { sectionSafetyPenalty += 0.55 }
            if section.roadClass == .local || section.roadClass == .service { sectionSafetyPenalty += 0.10 }
            if abs(section.gradientPercent) >= 8 { sectionSafetyPenalty += 0.20 }
            if section.crosswindKmh.map({ $0 >= 50 }) == true { sectionSafetyPenalty += 0.25 }
            safetyPenalty += length * sectionSafetyPenalty

            var sectionComfortPenalty = 0.0
            if section.surface == .rough { sectionComfortPenalty += 0.35 }
            if section.surface == .unpaved { sectionComfortPenalty += 0.70 }
            if section.roadClass == .local || section.roadClass == .service { sectionComfortPenalty += 0.25 }
            if abs(section.gradientPercent) >= 6 { sectionComfortPenalty += 0.25 }
            sectionComfortPenalty += 0.30 * min(1, max(0, section.turnLoad))
            if section.crosswindKmh.map({ $0 >= 40 }) == true { sectionComfortPenalty += 0.20 }
            comfortPenalty += length * sectionComfortPenalty
        }

        let safety = score(fromPenalty: safetyPenalty / totalLength)
        let reliability = Int((100 * reliabilityTotal / totalLength).rounded()).clamped(to: 0 ... 100)
        let comfort = score(fromPenalty: comfortPenalty / totalLength)
        let cost = candidate.estimatedEnergyCostEUR.map { max(0, candidate.tollCostEUR) + max(0, $0) }

        return RouteAssessment(
            candidate: candidate,
            exclusions: exclusions,
            scores: RouteScores(safety: safety, reliability: reliability, comfort: comfort, totalCostEUR: cost),
            motorwayShare: motorwayKm / totalLength,
            localRoadKm: localKm,
            roughRoadKm: roughKm,
            unknownRestrictionKm: unknownKm
        )
    }

    private static func score(fromPenalty penalty: Double) -> Int {
        Int((100 * (1 - min(1, max(0, penalty)))).rounded()).clamped(to: 0 ... 100)
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(limits.upperBound, max(limits.lowerBound, self))
    }
}
```

Rules:

- Unready vehicle adds only `.vehicleNeedsConfirmation`; still calculate descriptive scores.
- Empty sections, nonpositive duration/distance, nonfinite length or negative section length add `.invalidCandidate`.
- Compare confirmed routing envelope to each present max height, width and weight.
- Closed, explicit access false and explicit trailer false are hard exclusions.
- `avoidUnpaved`, `avoidFerries` and `avoidTunnels` are hard only when the corresponding preference is true.
- Unknown limits never create hard exclusions.
- Deduplicate exclusions while preserving first occurrence order.
- Calculate all shares by section length.
- Safety penalty per length: rough `0.25`, unpaved `0.55`, local/service `0.10`, absolute gradient ≥8% `0.20`, crosswind ≥50 km/h `0.25`; clamp final score to 0...100.
- Reliability per section: `0.7 * clamp(restrictionCoverage) + 0.3 * min(sourceCount / 3, 1)`; length-weight and scale to 0...100.
- Comfort penalty per length: rough `0.35`, unpaved `0.70`, local/service `0.25`, absolute gradient ≥6% `0.25`, `0.30 * clamp(turnLoad)`, crosswind ≥40 km/h `0.20`; clamp final score to 0...100.
- Total cost is toll plus energy cost when energy cost exists; otherwise `nil`.

- [ ] **Step 5: Run the check and verify GREEN**

Run: `./ios/Tests/run-route-quality-check.sh`

Expected: all hard-exclusion and reliability checks pass.

- [ ] **Step 6: Commit shared route evidence and assessment**

```bash
git add ios/Karavan/Routing/RouteQualityModels.swift ios/Karavan/Routing/RouteSafetyEngine.swift ios/Tests/route-quality-check.swift ios/Tests/run-route-quality-check.sh
git commit -m "feat: enforce hard route safety rules"
```

## Task 5: Yüzde 15 seçimi, sürüş karakterleri ve gerekçeler

**Files:**

- Modify: `ios/Karavan/Routing/RouteSafetyEngine.swift`
- Modify: `ios/Tests/route-quality-check.swift`

**Interfaces:**

- Consumes: `RouteSafetyEngine.assess`, `RoutePreferences.style`, `RouteAssessment`
- Produces: `RouteSafetyEngine.select(candidates:vehicle:preferences:) -> RouteDecision`

- [ ] **Step 1: Add failing selection checks**

Add this helper above `@main`:

```swift
func section(
    length: Double,
    roadClass: RoadClass,
    surface: RoadSurface,
    sources: Int
) -> RouteSectionEvidence {
    RouteSectionEvidence(
        lengthKm: length,
        roadClass: roadClass,
        isDivided: roadClass == .motorway || roadClass == .trunk,
        surface: surface,
        features: [],
        maxHeightM: 4.5,
        maxWidthM: 3.2,
        maxWeightKg: 20_000,
        trailerAllowed: true,
        accessAllowed: true,
        isClosed: false,
        gradientPercent: 1,
        turnLoad: roadClass == .local ? 0.4 : 0.05,
        crosswindKmh: 10,
        restrictionCoverage: 1,
        sourceCount: sources
    )
}
```

Append scenarios with explicit sections:

```swift
print("\n=== Rota seçimi ===")
let fastLocal = candidate(
    id: "fast-local", duration: 100,
    sections: [section(length: 100, roadClass: .local, surface: .paved, sources: 2)]
)
let safeMotorway = candidate(
    id: "safe-motorway", duration: 112,
    sections: [section(length: 108, roadClass: .motorway, surface: .smoothPaved, sources: 3)]
)
let tooLongMotorway = candidate(
    id: "too-long", duration: 121,
    sections: [section(length: 110, roadClass: .motorway, surface: .smoothPaved, sources: 3)]
)

let balancedDecision = RouteSafetyEngine.select(
    candidates: [fastLocal, safeMotorway, tooLongMotorway],
    vehicle: routeVehicle,
    preferences: .balanced
)
expect(balancedDecision.selected?.candidate.id == "safe-motorway", "+%15 içindeki güvenli rota seçilir")
expect(balancedDecision.fastestEligible?.candidate.id == "fast-local", "en hızlı uygun referans korunur")
expect(balancedDecision.selected?.candidate.durationMinutes == 112, "+dakika hesabı için kesin süre korunur")
expect(balancedDecision.reasons.count <= 3, "kullanıcıya en fazla üç gerekçe verilir")

var motorwayPreferences = RoutePreferences.balanced
motorwayPreferences.style = .motorway
let motorwayDecision = RouteSafetyEngine.select(
    candidates: [fastLocal, safeMotorway], vehicle: routeVehicle, preferences: motorwayPreferences
)
expect(motorwayDecision.selected?.motorwayShare == 1, "otoyol modu en yüksek otoyol oranını seçer")

let verySafeOutside = candidate(
    id: "outside-safe", duration: 130,
    sections: [section(length: 115, roadClass: .motorway, surface: .smoothPaved, sources: 3)]
)
let riskyInside = candidate(
    id: "inside-rough", duration: 100,
    sections: [section(length: 90, roadClass: .secondary, surface: .rough, sources: 2)]
)
let outsideDecision = RouteSafetyEngine.select(
    candidates: [riskyInside, verySafeOutside], vehicle: routeVehicle, preferences: .balanced
)
expect(outsideDecision.selected?.candidate.id == "inside-rough", "varsayılan seçim yüzde 15 penceresinde kalır")
expect(outsideDecision.saferOutsideWindow?.candidate.id == "outside-safe", "anlamlı güvenli uzun rota gizlenmez")

let unconfirmedDecision = RouteSafetyEngine.select(
    candidates: [safeMotorway], vehicle: .passatAdriaDraft, preferences: .balanced
)
expect(unconfirmedDecision.status == .requiresVehicleConfirmation, "doğrulanmamış araç onay kapısını açar")
```

- [ ] **Step 2: Run the check and verify RED**

Run: `./ios/Tests/run-route-quality-check.sh`

Expected: compilation fails because `RouteSafetyEngine.select` does not exist.

- [ ] **Step 3: Implement selection order**

Add to `RouteSafetyEngine`:

```swift
static func select(
    candidates: [RouteCandidate],
    vehicle: VehicleProfile,
    preferences: RoutePreferences
) -> RouteDecision {
    let assessments = candidates.map {
        assess(candidate: $0, vehicle: vehicle, preferences: preferences)
    }
    if !vehicle.isReadyForRestrictedRouting {
        return RouteDecision(
            status: .requiresVehicleConfirmation,
            selected: nil,
            fastestEligible: nil,
            saferOutsideWindow: nil,
            rejected: assessments,
            reasons: []
        )
    }

    let eligible = assessments.filter(\.exclusions.isEmpty)
    guard let fastest = eligible.min(by: fasterAssessment) else {
        return RouteDecision(
            status: .noEligibleRoute,
            selected: nil,
            fastestEligible: nil,
            saferOutsideWindow: nil,
            rejected: assessments,
            reasons: []
        )
    }

    let detour = preferences.maxDetourFraction.clamped(to: 0 ... 1)
    let limit = Double(fastest.candidate.durationMinutes) * (1 + detour)
    let inside = eligible.filter { Double($0.candidate.durationMinutes) <= limit }
    let bestSafety = inside.map(\.scores.safety).max() ?? fastest.scores.safety
    let stylePool = preferences.style == .balanced
        ? inside
        : inside.filter { $0.scores.safety >= bestSafety - 5 }
    let selected = stylePool.sorted { better($0, than: $1, style: preferences.style) }.first ?? fastest

    let outside = eligible
        .filter { Double($0.candidate.durationMinutes) > limit }
        .sorted { better($0, than: $1, style: .balanced) }
    let saferOutside = outside.first.flatMap { candidate in
        candidate.scores.safety >= selected.scores.safety + 10
            || candidate.scores.reliability >= selected.scores.reliability + 20
            ? candidate : nil
    }

    return RouteDecision(
        status: .selected,
        selected: selected,
        fastestEligible: fastest,
        saferOutsideWindow: saferOutside,
        rejected: assessments.filter { !$0.exclusions.isEmpty },
        reasons: reasons(selected: selected, comparedWith: fastest)
    )
}

private static func fasterAssessment(_ lhs: RouteAssessment, _ rhs: RouteAssessment) -> Bool {
    if lhs.candidate.durationMinutes != rhs.candidate.durationMinutes {
        return lhs.candidate.durationMinutes < rhs.candidate.durationMinutes
    }
    if lhs.candidate.distanceKm != rhs.candidate.distanceKm {
        return lhs.candidate.distanceKm < rhs.candidate.distanceKm
    }
    return lhs.candidate.id < rhs.candidate.id
}

private static func better(
    _ lhs: RouteAssessment,
    than rhs: RouteAssessment,
    style: RoutingPreferenceStyle
) -> Bool {
    switch style {
    case .balanced:
        if lhs.scores.safety != rhs.scores.safety { return lhs.scores.safety > rhs.scores.safety }
        if lhs.scores.reliability != rhs.scores.reliability { return lhs.scores.reliability > rhs.scores.reliability }
        if lhs.scores.comfort != rhs.scores.comfort { return lhs.scores.comfort > rhs.scores.comfort }
    case .motorway:
        if lhs.motorwayShare != rhs.motorwayShare { return lhs.motorwayShare > rhs.motorwayShare }
        if lhs.scores.safety != rhs.scores.safety { return lhs.scores.safety > rhs.scores.safety }
        if lhs.scores.reliability != rhs.scores.reliability { return lhs.scores.reliability > rhs.scores.reliability }
    case .comfort:
        if lhs.scores.comfort != rhs.scores.comfort { return lhs.scores.comfort > rhs.scores.comfort }
        if lhs.scores.safety != rhs.scores.safety { return lhs.scores.safety > rhs.scores.safety }
        if lhs.scores.reliability != rhs.scores.reliability { return lhs.scores.reliability > rhs.scores.reliability }
    case .economy:
        switch (lhs.scores.totalCostEUR, rhs.scores.totalCostEUR) {
        case let (left?, right?) where left != right: return left < right
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        if lhs.scores.safety != rhs.scores.safety { return lhs.scores.safety > rhs.scores.safety }
        if lhs.scores.reliability != rhs.scores.reliability { return lhs.scores.reliability > rhs.scores.reliability }
    }
    if lhs.candidate.durationMinutes != rhs.candidate.durationMinutes {
        return lhs.candidate.durationMinutes < rhs.candidate.durationMinutes
    }
    return lhs.candidate.id < rhs.candidate.id
}

private static func reasons(
    selected: RouteAssessment,
    comparedWith fastest: RouteAssessment
) -> [RouteReason] {
    var reasons: [RouteReason] = []
    if selected.scores.safety >= fastest.scores.safety + 5 { reasons.append(.highestSafety) }
    if selected.motorwayShare >= fastest.motorwayShare + 0.05 { reasons.append(.moreMotorway) }
    if selected.localRoadKm <= fastest.localRoadKm - 2 { reasons.append(.lessLocalRoad) }
    if selected.roughRoadKm <= fastest.roughRoadKm - 1 { reasons.append(.smootherSurface) }
    if selected.scores.reliability >= fastest.scores.reliability + 10 { reasons.append(.strongerConsensus) }
    if let selectedCost = selected.scores.totalCostEUR,
       let fastestCost = fastest.scores.totalCostEUR,
       selectedCost <= fastestCost - 2 {
        reasons.append(.lowerCost)
    }
    return Array((reasons.isEmpty ? [.highestSafety] : reasons).prefix(3))
}
```

Implement this exact order:

1. Assess every candidate once.
2. If vehicle is unready, return `.requiresVehicleConfirmation`, no selected route and all assessments in `rejected`.
3. Eligible assessments have no hard exclusions.
4. If none remain, return `.noEligibleRoute`.
5. `fastestEligible` is the lowest duration, then shortest distance, then lexical candidate ID.
6. Clamp `maxDetourFraction` to `0...1`; window limit is `fastest * (1 + fraction)`.
7. Find best safety inside the window. For motorway, comfort and economy styles, only compare candidates within five safety points of that best value; balanced compares all candidates in the window.
8. Balanced sort: safety descending, reliability descending, comfort descending, duration ascending, ID ascending.
9. Motorway sort: motorway share descending, safety descending, reliability descending, duration ascending, ID ascending.
10. Comfort sort: comfort descending, safety descending, reliability descending, duration ascending, ID ascending.
11. Economy sort: known total cost before unknown, cost ascending, safety descending, reliability descending, duration ascending, ID ascending.
12. `saferOutsideWindow` is the best outside candidate only when its safety exceeds selected by at least 10 or reliability exceeds selected by at least 20.
13. Build reasons by comparing selected to fastest: safety +5 → `.highestSafety`, motorway share +0.05 → `.moreMotorway`, local road -2 km → `.lessLocalRoad`, rough road -1 km → `.smootherSurface`, reliability +10 → `.strongerConsensus`, total cost at least €2 lower → `.lowerCost`. Preserve this order and return at most three. If no comparison reason exists, return `.highestSafety`.

- [ ] **Step 4: Run the focused check and verify GREEN**

Run: `./ios/Tests/run-route-quality-check.sh`

Expected: every vehicle, garage, consumption, hard-rule and selection assertion passes.

- [ ] **Step 5: Run regression checks**

Run:

```bash
./ios/Tests/run-planner-check.sh
./ios/Tests/run-account-check.sh
npm run check
npm run lint
```

Expected: every command exits 0. Existing warnings or failures must be reported, not hidden.

- [ ] **Step 6: Commit route selection**

```bash
git add ios/Karavan/Routing/RouteSafetyEngine.swift ios/Tests/route-quality-check.swift
git commit -m "feat: select safe route within detour budget"
```

## Final Verification

- [ ] Run `./ios/Tests/run-route-quality-check.sh` and confirm every section passes.
- [ ] Run `./ios/Tests/run-planner-check.sh` and `./ios/Tests/run-account-check.sh`.
- [ ] Run `npm run check` and `npm run lint`.
- [ ] Run `git diff --check` for all files changed by this plan.
- [ ] Confirm the commits contain only `ios/Karavan/Routing/*`, `ios/Tests/route-quality-check.swift`, and `ios/Tests/run-route-quality-check.sh`.
- [ ] Confirm no existing dirty user file was staged or committed.

## Follow-up Plans

This plan intentionally implements the first independently testable subsystem from the approved design. Continue with separate plans in this order:

1. Vehicle garage SwiftUI and route-builder binding after the existing untracked route-builder work is committed or explicitly brought into scope.
2. Apple/HERE/TomTom/open provider adapters and Astro `/api/v2/routes/compare` orchestration.
3. Approval UI, immutable approved-route persistence and role-aware synchronization.
4. HERE in-app navigation, critical rerouting and offline trip packages.
5. Official live feeds, EV/PHEV charging, safe stops, border and vignette enrichment.
