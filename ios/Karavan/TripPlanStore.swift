import Foundation

// Kullanıcı düzenlemelerinin cihazdaki deposu + kaskat tetikleyicisi.
// Web verisi TABAN kalır; düzenlemeler onun üstüne bindirilir. Böylece site
// güncellenince taban tazelenir, kişisel değişikliklerin korunur.
@MainActor
final class TripPlanStore: ObservableObject {
    @Published private(set) var edits = TripEdits()

    /// Bu cihaz planı yönetiyor mu? Yalnızca SAHİP yazar, diğerleri okur.
    /// "Son yazan kazanır" kasten tercih edilmedi: yolda iki kişi aynı anda
    /// düzenleyince biri sessizce diğerinin değişikliğini siler.
    @Published var isOwner: Bool {
        didSet {
            UserDefaults.standard.set(isOwner, forKey: Self.ownerKey)
            if isOwner { pushToWeb() }
        }
    }

    /// Web'den en son ne zaman çekildi (arayüzde göstermek için).
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var syncing = false

    /// Kalkış/gün değişince çağrılır: bildirimleri yeniden kur, snapshot/web'i güncelle.
    var onChange: ((TripEdits) -> Void)?

    private static let ownerKey = "plan-owner-device"

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("trip-edits.json")
    }

    init() {
        isOwner = UserDefaults.standard.bool(forKey: Self.ownerKey)
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(TripEdits.self, from: data) {
            edits = decoded
        }
    }

    // MARK: - Cihazlar arası senkron

    /// Takipçi cihazlarda web'deki düzenlemeleri çeker ve uygular.
    /// Sahip cihaz çekmez — kendi hâli zaten kaynak.
    func syncFromWeb() async {
        guard !isOwner, !syncing, let url = Config.editsURL else { return }
        syncing = true
        defer { syncing = false }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let remote = try? Self.decoder.decode(TripEdits.self, from: data)
        else { return }

        lastSyncedAt = Date()
        guard remote != edits else { return }   // değişmemişse dokunma

        edits = remote
        persist()
        onChange?(edits)
        objectWillChange.send()
    }

    /// Sahip cihazda düzenlemeleri web'e yazar.
    private func pushToWeb() {
        guard isOwner, let url = Config.editsURL else { return }

        var payload: [String: Any] = ["days": Self.encodeDays(edits.days)]
        if let dep = edits.departureAt {
            payload["departureAt"] = ISO8601DateFormatter().string(from: dep)
        } else {
            payload["departureAt"] = NSNull()
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.livePostSecret, forHTTPHeaderField: "x-live-secret")
        request.timeoutInterval = 12
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        Task { _ = try? await URLSession.shared.data(for: request) }
    }

    private static func encodeDays(_ days: [String: DayEdit]) -> [String: Any] {
        guard let data = try? encoder.encode(days),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

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
        persist()
        pushToWeb()          // yalnızca sahip cihazda etkili
        onChange?(edits)
        objectWillChange.send()
    }

    /// Yerel dosya VARSAYILAN tarih biçimini kullanır — init de öyle okuyor.
    /// ISO-8601 yalnızca ağ yükünde; yerelde değiştirmek cihazdaki mevcut
    /// düzenlemeleri okunamaz hale getirirdi.
    private func persist() {
        if let data = try? JSONEncoder().encode(edits) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
