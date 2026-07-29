import Foundation

// Kullanıcı düzenlemelerinin cihazdaki deposu + kaskat tetikleyicisi.
// Web verisi TABAN kalır; düzenlemeler onun üstüne bindirilir. Böylece site
// güncellenince taban tazelenir, kişisel değişikliklerin korunur.
@MainActor
final class TripPlanStore: ObservableObject {
    @Published private(set) var edits = TripEdits()

    /// Bu cihaz planın sahibi mi? GÜN düzenlemelerini artık HER cihaz web'e
    /// yazar ("kamp planını herkes düzenleyebilir"; sunucu son-yazan-kazanır,
    /// aile içi kabul edilebilir). Kalkış tarihi ise yalnızca sahip/sürücü
    /// cihazdan taşınır — ayrıntı: `canMoveDeparture`.
    @Published var isOwner: Bool {
        didSet {
            UserDefaults.standard.set(isOwner, forKey: Self.ownerKey)
            // The public projection is queued by KaravanApp only after the
            // selected trip has passed its public-tracking eligibility gate.
            if isOwner { pushToWeb() }
        }
    }

    /// Web'den en son ne zaman çekildi (arayüzde göstermek için).
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var syncing = false

    /// Kalkış/gün değişince çağrılır: bildirimleri yeniden kur, snapshot/web'i güncelle.
    var onChange: ((TripEdits) -> Void)?

    /// RoleStore ilk açılış tohumu için de okuyor (önceki kurulum tespiti).
    static let ownerKey = "plan-owner-device"

    /// Son senkron/gönderim anındaki düzenlemeler: 3-yönlü birleştirmede
    /// "bu cihazda ne değişti" tabanı. Diske yazılır (yeniden başlatmada da geçerli).
    private var syncBase = TripEdits()
    private var arrivalTargetOverrides = ScopedArrivalTargetOverrides()

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("trip-edits.json")
    }

    private var baseFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("trip-edits-sync-base.json")
    }

    private var arrivalTargetOverridesFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("arrival-target-overrides.json")
    }

    init() {
        isOwner = UserDefaults.standard.bool(forKey: Self.ownerKey)
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(TripEdits.self, from: data) {
            edits = decoded
        }
        if let data = try? Data(contentsOf: baseFileURL),
           let decoded = try? JSONDecoder().decode(TripEdits.self, from: data) {
            syncBase = decoded
        }
        if let data = try? Data(contentsOf: arrivalTargetOverridesFileURL),
           let decoded = try? JSONDecoder().decode(ScopedArrivalTargetOverrides.self, from: data) {
            arrivalTargetOverrides = decoded
        }
        migrateScopedArrivalTargetEdits()
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-preview-subplans") {
            var edit = edits.days["istanbul-sofya"] ?? DayEdit()
            edit.subplans = [
                DaySubplan(
                    id: "preview-sofia-museum",
                    title: "Ulusal Tarih Müzesi",
                    placeName: "National History Museum, Sofia",
                    latitude: 42.6557,
                    longitude: 23.2716,
                    startMinute: 16 * 60,
                    durationMinutes: 90,
                    note: nil
                )
            ]
            edits.days["istanbul-sofya"] = edit
        }
#endif
    }

    // MARK: - Public projection

    /// Legacy anonymous edits transport has been retired. The current local
    /// plan is projected through the selected trip's Bearer route by the app.
    func syncFromWeb() async {
        lastSyncedAt = nil
    }

    /// Preserve a local baseline while KaravanApp publishes the public plan
    /// through the scoped outbox during its onChange cascade.
    private func pushToWeb() {
        syncBase = edits.sharedSyncState
        persistBase()
    }

    /// 3-yönlü birleştirme: base'den beri BU cihazda değişen günler uzak
    /// hâlin üstüne bindirilir (yerelde silinen gün uzaktan da silinir).
    /// Kalkış tarihi yalnızca sahip/sürücü cihazdan alınır; takipçi
    /// uzaktaki kalkışı aynen korur (asla taşıyamaz).
    private func merge(local: TripEdits, base: TripEdits, remote: TripEdits) -> TripEdits {
        var merged = remote
        for slug in Set(local.days.keys).union(base.days.keys)
        where local.days[slug] != base.days[slug] {
            merged.days[slug] = local.days[slug]   // nil → uzaktakini siler
        }
        if canMoveDeparture, local.departureAt != base.departureAt {
            merged.departureAt = local.departureAt
        }
        return merged
    }

    /// Kalkış tarihini web'e taşıma yetkisi: sahip cihaz ya da sürücünün cihazı.
    private var canMoveDeparture: Bool {
        isOwner || RoleStore.shared.isDriver
    }

    private static func encodeDays(_ days: [String: DayEdit]) -> [String: Any] {
        let safeDays = days.mapValues { edit in
            var safe = edit
            safe.arrivalTarget = edit.arrivalTarget?.publicSummary
            safe.arrivalTargetScope = nil
            if var details = safe.stayDetails {
                details.reservationReference = nil
                details.note = nil
                details.lastContactedAt = nil
                safe.stayDetails = details
            }
            return safe
        }
        guard let data = try? encoder.encode(safeDays),
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
        // Web yükü kesirli saniyeli ISO-8601 gönderebilir (örn. updatedAt
        // damgalı kayıtlar); düz .iso8601 bunu okuyamaz ve takipçi senkronu
        // kalıcı olarak ölür. Önce kesirli saniyeyle, olmazsa düz biçimle dene.
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: text) { return date }
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Geçersiz ISO-8601 tarih: \(text)")
        }
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

    func arrivalTargetOverride(
        slug: String,
        scope: ArrivalTargetOverrideScope
    ) -> ScopedArrivalTargetOverride? {
        guard scope.daySlug == slug else { return nil }
        return arrivalTargetOverrides.value(for: scope)
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

    func setArrivalTarget(
        _ target: ArrivalTarget,
        stay: StayDetails,
        slug: String,
        scope: ArrivalTargetOverrideScope
    ) {
        guard scope.daySlug == slug else { return }
        arrivalTargetOverrides.set(ScopedArrivalTargetOverride(
            scope: scope,
            target: target,
            stay: stay
        ))
        _ = persistArrivalTargetOverrides(arrivalTargetOverrides)
        objectWillChange.send()
    }

    func clearArrivalTargetOverride(slug: String, scope: ArrivalTargetOverrideScope) {
        guard scope.daySlug == slug,
              arrivalTargetOverrides.value(for: scope) != nil
        else { return }
        arrivalTargetOverrides.remove(scope: scope)
        _ = persistArrivalTargetOverrides(arrivalTargetOverrides)
        objectWillChange.send()
    }

    func upsertSubplan(_ subplan: DaySubplan, slug: String) {
        update(slug: slug) { edit in
            var values = edit.subplans ?? []
            if let index = values.firstIndex(where: { $0.id == subplan.id }) {
                values[index] = subplan
            } else {
                values.append(subplan)
            }
            edit.subplans = values.sorted { $0.startMinute < $1.startMinute }
        }
    }

    func removeSubplan(id: String, slug: String) {
        update(slug: slug) { edit in
            let values = (edit.subplans ?? []).filter { $0.id != id }
            edit.subplans = values.isEmpty ? nil : values
        }
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
        pushToWeb()          // her cihaz gün düzenlemesini gönderir; kalkış kısıtlı
        onChange?(edits)
        objectWillChange.send()
    }

    /// Yerel dosyalar VARSAYILAN tarih biçimini kullanır — init de öyle okuyor.
    /// ISO-8601 yalnızca ağ yükünde; yerelde değiştirmek cihazdaki mevcut
    /// düzenlemeleri okunamaz hale getirirdi.
    private func persist() {
        if let data = try? JSONEncoder().encode(edits) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func persistBase() {
        if let data = try? JSONEncoder().encode(syncBase) {
            try? data.write(to: baseFileURL, options: .atomic)
        }
    }

    private func persistArrivalTargetOverrides(_ value: ScopedArrivalTargetOverrides) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        do {
            try data.write(to: arrivalTargetOverridesFileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func migrateScopedArrivalTargetEdits() {
        var migratedOverrides = arrivalTargetOverrides
        var migratedEdits = edits
        var migratedBase = syncBase
        let succeeded = ScopedArrivalTargetOverrideMigration.perform(
            overrides: &migratedOverrides,
            edits: &migratedEdits,
            syncBase: &migratedBase,
            persistOverrides: { [arrivalTargetOverridesFileURL] candidate in
                guard let data = try? JSONEncoder().encode(candidate) else { return false }
                do {
                    try data.write(to: arrivalTargetOverridesFileURL, options: .atomic)
                    return true
                } catch {
                    return false
                }
            },
            persistEdits: { [fileURL] value in
                if let data = try? JSONEncoder().encode(value) {
                    try? data.write(to: fileURL, options: .atomic)
                }
            },
            persistBase: { [baseFileURL] value in
                if let data = try? JSONEncoder().encode(value) {
                    try? data.write(to: baseFileURL, options: .atomic)
                }
            }
        )
        if succeeded {
            arrivalTargetOverrides = migratedOverrides
            edits = migratedEdits
            syncBase = migratedBase
        }
    }
}
