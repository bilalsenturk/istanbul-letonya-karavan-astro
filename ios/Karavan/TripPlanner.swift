import Foundation

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
    var isRestDay: Bool?        // nil → origin == destination'dan türetilir
    var extraDays: Int?         // bu durakta fazladan kalınan gün (0 = normal)
    var startHour: Int?         // o günün çıkış saati (nil → kalkış saati / 08:00)

    var isEmpty: Bool { self == DayEdit() }
}

struct TripEdits: Codable, Equatable {
    var departureAt: Date?              // kalkış tarihi/saati (nil → web verisi)
    var days: [String: DayEdit] = [:]   // slug → düzenleme
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
    var note: String? { edit?.note?.isEmpty == false ? edit?.note : nil }
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
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM · EEEE"
        return f
    }()

    static let shortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMM"
        return f
    }()

    /// Geçerli kalkış: kullanıcı düzenlemesi > web verisi > şimdi.
    static func departure(trip: TripData?, edits: TripEdits) -> Date {
        edits.departureAt ?? trip?.departureDate ?? Date()
    }

    /// Günleri türet. Tarihler kalkıştan kümülatif hesaplanır; `extraDays`
    /// sonraki tüm günleri kaydırır; dinlenme günleri etap tüketmez.
    static func days(trip: TripData?, edits: TripEdits) -> [EffectiveDay] {
        guard let trip else { return [] }
        let cal = Calendar.current
        let dep = departure(trip: trip, edits: edits)
        let day0 = cal.startOfDay(for: dep)
        let depHour = cal.component(.hour, from: dep)
        let depMinute = cal.component(.minute, from: dep)

        var result: [EffectiveDay] = []
        var dayOffset = 0
        var legCounter = 0

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

            result.append(
                EffectiveDay(
                    index: i, base: base, edit: edit,
                    date: date, departTime: departTime,
                    legIndex: rest ? nil : legCounter,
                    dayCount: 1 + extra
                )
            )

            if !rest { legCounter += 1 }
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
        return Calendar.current.date(byAdding: .day, value: last.dayCount - 1, to: last.date)
    }
}
