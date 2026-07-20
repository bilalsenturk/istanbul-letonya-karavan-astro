import Foundation

// Kullanıcı düzenlemelerinin cihazdaki deposu + kaskat tetikleyicisi.
// Web verisi TABAN kalır; düzenlemeler onun üstüne bindirilir. Böylece site
// güncellenince taban tazelenir, kişisel değişikliklerin korunur.
@MainActor
final class TripPlanStore: ObservableObject {
    @Published private(set) var edits = TripEdits()

    /// Kalkış/gün değişince çağrılır: bildirimleri yeniden kur, snapshot/web'i güncelle.
    var onChange: ((TripEdits) -> Void)?

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("trip-edits.json")
    }

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(TripEdits.self, from: data) {
            edits = decoded
        }
    }

    // MARK: - Türetme kısayolları

    func departure(_ trip: TripData?) -> Date { TripPlanner.departure(trip: trip, edits: edits) }
    func days(_ trip: TripData?) -> [EffectiveDay] { TripPlanner.days(trip: trip, edits: edits) }
    func totalDays(_ trip: TripData?) -> Int { TripPlanner.totalDays(trip: trip, edits: edits) }
    func arrivalDate(_ trip: TripData?) -> Date? { TripPlanner.arrivalDate(trip: trip, edits: edits) }

    func day(_ trip: TripData?, slug: String) -> EffectiveDay? {
        days(trip).first { $0.base.slug == slug }
    }

    // MARK: - Düzenleme

    func setDeparture(_ date: Date) {
        edits.departureAt = date
        commit()
    }

    func resetDeparture() {
        edits.departureAt = nil
        commit()
    }

    func update(slug: String, _ mutate: (inout DayEdit) -> Void) {
        var e = edits.days[slug] ?? DayEdit()
        mutate(&e)
        if e.isEmpty { edits.days.removeValue(forKey: slug) } else { edits.days[slug] = e }
        commit()
    }

    func reset(slug: String) {
        edits.days.removeValue(forKey: slug)
        commit()
    }

    func resetAll() {
        edits = TripEdits()
        commit()
    }

    var hasEdits: Bool { edits.departureAt != nil || !edits.days.isEmpty }
    var editedDayCount: Int { edits.days.count }

    // MARK: - Kalıcılık + kaskat

    private func commit() {
        if let data = try? JSONEncoder().encode(edits) {
            try? data.write(to: fileURL, options: .atomic)
        }
        onChange?(edits)
        objectWillChange.send()
    }
}
