import Foundation

struct DaySubplan: Codable, Equatable, Identifiable {
    let id: String
    var title: String
    var placeName: String
    var latitude: Double
    var longitude: Double
    /// Gün başlangıcından itibaren dakika (17:30 = 1050).
    var startMinute: Int
    var durationMinutes: Int
    var note: String?
}

struct PlanScheduleEntry: Equatable {
    let id: String
    let requestedStartMinute: Int
    let previousEndMinute: Int
    let travelMinutes: Int
    let durationMinutes: Int

    var earliestStartMinute: Int { previousEndMinute + max(0, travelMinutes) }
    var finishMinute: Int { requestedStartMinute + max(0, durationMinutes) }
}

struct PlanScheduleConflict: Equatable {
    let entryID: String
    let earliestStartMinute: Int
}

struct PlanScheduleNeighbors: Equatable {
    let previousID: String?
    let nextID: String?
}

enum PlanScheduleValidator {
    static func conflict(for entry: PlanScheduleEntry) -> PlanScheduleConflict? {
        guard entry.requestedStartMinute < entry.earliestStartMinute else { return nil }
        return PlanScheduleConflict(entryID: entry.id, earliestStartMinute: entry.earliestStartMinute)
    }

    static func fitsBeforeNextDeparture(
        finishMinute: Int,
        travelMinutesToNext: Int,
        nextDepartureMinute: Int
    ) -> Bool {
        finishMinute + max(0, travelMinutesToNext) <= nextDepartureMinute
    }

    static func neighbors(
        for requestedStartMinute: Int,
        excludingID: String?,
        in subplans: [DaySubplan]
    ) -> PlanScheduleNeighbors {
        let ordered = subplans
            .filter { $0.id != excludingID }
            .sorted { $0.startMinute < $1.startMinute }
        return PlanScheduleNeighbors(
            previousID: ordered.last { $0.startMinute <= requestedStartMinute }?.id,
            nextID: ordered.first { $0.startMinute > requestedStartMinute }?.id
        )
    }
}

struct ArrivalTargetOverrideScope: Codable, Equatable, Hashable {
    let tripID: String
    let daySlug: String
    let userID: String?
}

struct ScopedArrivalTargetOverride: Codable, Equatable {
    let scope: ArrivalTargetOverrideScope
    let target: ArrivalTarget
    let stay: StayDetails
}

struct ScopedArrivalTargetOverrides: Codable, Equatable {
    private var values: [ScopedArrivalTargetOverride] = []

    func value(for scope: ArrivalTargetOverrideScope) -> ScopedArrivalTargetOverride? {
        values.first { $0.scope == scope }
    }

    mutating func set(_ value: ScopedArrivalTargetOverride) {
        values.removeAll { $0.scope == value.scope }
        values.append(value)
    }

    mutating func remove(scope: ArrivalTargetOverrideScope) {
        values.removeAll { $0.scope == scope }
    }
}

enum ArrivalTargetSelectionResolver {
    static func target(
        scope: ArrivalTargetOverrideScope,
        ephemeral: ScopedArrivalTargetOverride?,
        persisted: ScopedArrivalTargetOverride?,
        account: ArrivalTarget?,
        base: ArrivalTarget?
    ) -> ArrivalTarget? {
        matching(scope: scope, ephemeral: ephemeral, persisted: persisted)?.target ?? account ?? base
    }

    static func stay(
        scope: ArrivalTargetOverrideScope,
        ephemeral: ScopedArrivalTargetOverride?,
        persisted: ScopedArrivalTargetOverride?,
        account: StayDetails?,
        base: StayDetails
    ) -> StayDetails {
        matching(scope: scope, ephemeral: ephemeral, persisted: persisted)?.stay ?? account ?? base
    }

    private static func matching(
        scope: ArrivalTargetOverrideScope,
        ephemeral: ScopedArrivalTargetOverride?,
        persisted: ScopedArrivalTargetOverride?
    ) -> ScopedArrivalTargetOverride? {
        if ephemeral?.scope == scope { return ephemeral }
        if persisted?.scope == scope { return persisted }
        return nil
    }
}

// Kullanıcının bir güne yaptığı düzenlemeler. Hepsi opsiyonel: nil = "web verisini kullan".
struct DayEdit: Codable, Equatable {
    var origin: String?
    var destination: String?
    var distanceKm: String?
    var duration: String?
    var fuel: String?
    var note: String?           // kişisel not
    var campName: String?
    var campPlace: String?
    var arrivalTarget: ArrivalTarget?
    var stayDetails: StayDetails?
    var arrivalTargetScope: ArrivalTargetOverrideScope?
    var isRestDay: Bool?        // nil → origin == destination'dan türetilir
    var extraDays: Int?         // bu durakta fazladan kalınan gün (0 = normal)
    var startHour: Int?         // o günün çıkış saati (nil → kalkış saati / 08:00)
    /// Eksik anahtar eski kayıtlarda `nil` çözülür; böylece geriye uyumludur.
    var subplans: [DaySubplan]?

    var isEmpty: Bool { self == DayEdit() }
}

struct TripEdits: Codable, Equatable {
    var departureAt: Date?              // kalkış tarihi/saati (nil → web verisi)
    var days: [String: DayEdit] = [:]   // slug → düzenleme

    var sharedSyncState: TripEdits {
        var shared = self
        for (slug, edit) in shared.days where edit.arrivalTargetScope != nil {
            var safe = edit
            safe.arrivalTarget = nil
            safe.stayDetails = nil
            safe.arrivalTargetScope = nil
            if safe.isEmpty {
                shared.days.removeValue(forKey: slug)
            } else {
                shared.days[slug] = safe
            }
        }
        return shared
    }
}

// Web verisi + kullanıcı düzenlemeleri birleşiminden türetilen tek gerçek gün.
struct EffectiveDay: Identifiable {
    let index: Int
    let base: DayPlan
    let edit: DayEdit?
    /// Türetilmiş takvim günü (kalkış + kümülatif gün). JSON'daki metin DEĞİL.
    let date: Date
    /// O gün yola çıkış saati
    let departTime: Date
    /// RouteStore etabı — dinlenme gününde nil
    let legIndex: Int?
    /// Bu gün kaç takvim günü sürüyor (1 + extraDays)
    let dayCount: Int

    var id: String { base.slug }

    var origin: String { edit?.origin ?? base.origin }
    var destination: String { edit?.destination ?? base.destination }
    var distanceKm: String { edit?.distanceKm ?? base.distanceKm }
    var duration: String { edit?.duration ?? base.duration }
    var fuel: String { edit?.fuel ?? base.fuel }
    var campName: String { edit?.campName ?? base.camp.name }
    var campPlace: String { edit?.campPlace ?? base.camp.place }
    var arrivalTarget: ArrivalTarget? {
        guard edit?.arrivalTargetScope == nil else { return nil }
        return edit?.arrivalTarget
    }
    var stayDetails: StayDetails {
        guard edit?.arrivalTargetScope == nil else { return StayDetails() }
        return edit?.stayDetails ?? StayDetails()
    }
    var note: String? { edit?.note?.isEmpty == false ? edit?.note : nil }
    var subplans: [DaySubplan] { edit?.subplans ?? [] }
    var isRestDay: Bool { edit?.isRestDay ?? (origin == destination) }
    var isEdited: Bool { edit?.isEmpty == false }

    /// Ülke değişiyor mu (sınır geçişi) — durak listesinden çözülür.
    func crossesBorder(in trip: TripData) -> Bool {
        guard !isRestDay,
              let a = trip.stop(matching: origin),
              let b = trip.stop(matching: destination) else { return false }
        return a.country != b.country
    }

    var dateText: String { TripPlanner.dayFormatter.string(from: date) }
    var shortDateText: String { TripPlanner.shortFormatter.string(from: date) }
}

// Saf türetme motoru: (web verisi + düzenlemeler) → kalkış + günler.
// Hiçbir yan etkisi yok; bu yüzden kaskat davranışı öngörülebilir ve test edilebilir.
enum TripPlanner {
    /// Rota planı Türkiye çıkış takvimine göre yazıldı. Cihaz başka saat
    /// dilimindeyken erken saatli kalkışlar bir önceki güne kaymasın.
    static let routeTimeZone = TimeZone(identifier: "Europe/Istanbul")!

    static var routeCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "tr_TR")
        cal.timeZone = routeTimeZone
        return cal
    }()

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.timeZone = routeTimeZone
        f.dateFormat = "d MMMM · EEEE"
        return f
    }()

    static let shortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.timeZone = routeTimeZone
        f.dateFormat = "d MMM"
        return f
    }()

    /// Geçerli kalkış: kullanıcı düzenlemesi > web verisi > bugünün başlangıcı.
    /// Web tarihi ayrıştırılamazsa "şimdi"ye sessizce düşmek yerine deterministik
    /// bir tarih kullan — yoksa gün planı her çağrıda kayar. Yolculuk yoksa "şimdi".
    static func departure(trip: TripData?, edits: TripEdits) -> Date {
        if let d = edits.departureAt { return d }
        if let d = trip?.departureDate { return d }
        guard trip != nil else { return Date() }
        return routeCalendar.startOfDay(for: Date())
    }

    /// Günleri türet. Tarihler kalkıştan kümülatif hesaplanır; `extraDays`
    /// sonraki tüm günleri kaydırır; dinlenme günleri etap tüketmez.
    static func days(trip: TripData?, edits: TripEdits) -> [EffectiveDay] {
        guard let trip else { return [] }
        let cal = routeCalendar
        let dep = departure(trip: trip, edits: edits)
        let day0 = cal.startOfDay(for: dep)
        let depHour = cal.component(.hour, from: dep)
        let depMinute = cal.component(.minute, from: dep)

        var result: [EffectiveDay] = []
        var dayOffset = 0

        for (i, base) in trip.days.enumerated() {
            let edit = edits.days[base.slug]
            let origin = edit?.origin ?? base.origin
            let destination = edit?.destination ?? base.destination
            let rest = edit?.isRestDay ?? (origin == destination)
            let extra = max(0, edit?.extraDays ?? 0)

            let date = cal.date(byAdding: .day, value: dayOffset, to: day0) ?? day0

            // Çıkış saati: ilk gün gerçek kalkış saati, diğerleri düzenleme ya da 08:00
            let hour = edit?.startHour ?? (i == 0 ? depHour : 8)
            let minute = (edit?.startHour == nil && i == 0) ? depMinute : 0
            let departTime = cal.date(bySettingHour: min(23, max(0, hour)),
                                      minute: minute, second: 0, of: date) ?? date

            // Etap indeksi "dinlenmeyen gün sayacı"ndan DEĞİL, günün çıkış durağının
            // trip.stops'taki konumundan türetilir: bir dinlenme günü düzenlemesi
            // sonraki günlerin etabını RouteStore'un pozisyonel legs'ine göre kaydırmaz.
            let legIndex: Int?
            if rest {
                legIndex = nil
            } else if let originStop = trip.stop(matching: origin) {
                legIndex = trip.stops.firstIndex(where: { $0.id == originStop.id })
            } else {
                legIndex = nil
            }

            result.append(
                EffectiveDay(
                    index: i, base: base, edit: edit,
                    date: date, departTime: departTime,
                    legIndex: legIndex,
                    dayCount: 1 + extra
                )
            )

            dayOffset += 1 + extra
        }
        return result
    }

    /// Yolculuğun toplam takvim günü (düzenlemeler dahil).
    static func totalDays(trip: TripData?, edits: TripEdits) -> Int {
        days(trip: trip, edits: edits).reduce(0) { $0 + $1.dayCount }
    }

    /// Son durağa varış günü.
    static func arrivalDate(trip: TripData?, edits: TripEdits) -> Date? {
        guard let last = days(trip: trip, edits: edits).last else { return nil }
        return routeCalendar.date(byAdding: .day, value: last.dayCount - 1, to: last.date)
    }
}

enum DeparturePromptKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.timeZone = TripPlanner.routeTimeZone
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f
    }()

    static func key(prefix: String = "departure-prompt-shown", stopId: String, departure: Date) -> String {
        "\(prefix)-\(stopId)-\(formatter.string(from: departure))"
    }
}

struct LiveActivityStartPayload {
    let remainingKm: Int
    let remainingMin: Int
}

struct RouteStartMetrics {
    let remainingKm: Int?
    let remainingMinutes: Int?

    var liveActivityPayload: LiveActivityStartPayload? {
        guard let remainingKm, let remainingMinutes,
              remainingKm > 0, remainingMinutes > 0
        else { return nil }
        return LiveActivityStartPayload(remainingKm: remainingKm, remainingMin: remainingMinutes)
    }
}

struct AltitudeReading: CustomStringConvertible {
    let text: String
    let label: String
    let symbol: String

    var description: String { "\(label): \(text)" }
}

enum AltitudeDisplay {
    static func reading(absoluteMeters: Double?, relativeMeters: Double?) -> AltitudeReading? {
        if let absoluteMeters {
            return AltitudeReading(
                text: "\(Int(absoluteMeters.rounded())) m",
                label: "Rakım",
                symbol: "mountain.2.fill"
            )
        }
        if let relativeMeters {
            let rounded = Int(relativeMeters.rounded())
            let sign = rounded > 0 ? "+" : ""
            return AltitudeReading(
                text: "\(sign)\(rounded) m",
                label: "Rakım değişimi",
                symbol: "arrow.up.and.down.circle.fill"
            )
        }
        return nil
    }
}
