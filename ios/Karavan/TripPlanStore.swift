import Foundation

enum PlanEditMerge {
    static func rebase(
        local: TripEdits,
        base: TripEdits,
        remote: TripEdits,
        canMoveDeparture: Bool
    ) -> TripEdits {
        var merged = remote
        for slug in Set(local.days.keys).union(base.days.keys)
        where local.days[slug] != base.days[slug] {
            merged.days[slug] = local.days[slug]
        }
        if canMoveDeparture, local.departureAt != base.departureAt {
            merged.departureAt = local.departureAt
        }
        return merged
    }
}

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
    private var publishedTripScope: PublishedTripScope?
    private let planEditsClient: PlanEditSending
    private let storageDirectory: URL
    private let canMoveDepartureOverride: (() -> Bool)?

    private var fileURL: URL {
        storageDirectory.appendingPathComponent("trip-edits.json")
    }

    private var baseFileURL: URL {
        storageDirectory.appendingPathComponent("trip-edits-sync-base.json")
    }

    private var arrivalTargetOverridesFileURL: URL {
        storageDirectory.appendingPathComponent("arrival-target-overrides.json")
    }

    init(
        planEditsClient: PlanEditSending? = nil,
        storageDirectory: URL? = nil,
        canMoveDeparture: (() -> Bool)? = nil
    ) {
        self.planEditsClient = planEditsClient ?? PublishedTripClient.shared
        self.storageDirectory = storageDirectory
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        canMoveDepartureOverride = canMoveDeparture
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

    // MARK: - Cihazlar arası senkron

    func setPublishedTripScope(_ scope: PublishedTripScope?) {
        publishedTripScope = scope
    }

    /// Seçili public Kuzey rotasının kimlik doğrulamalı revision
    /// kaydını çeker. Yerel farklar uzak kaydın üstüne bindirilir;
    /// fark varsa aynı revision'a koşullu PUT yapılır.
    func syncFromWeb() async {
        guard !syncing, let scope = publishedTripScope else { return }
        syncing = true
        defer { syncing = false }

        let remote: RemotePlanEdits
        do {
            remote = try await planEditsClient.getPlanEdits(scope: scope)
        } catch {
            return
        }
        guard publishedTripScope == scope else { return }

        lastSyncedAt = Date()
        let remoteEdits = remote.edits.sharedSyncState
        let merged = PlanEditMerge.rebase(
            local: edits.sharedSyncState,
            base: syncBase.sharedSyncState,
            remote: remoteEdits,
            canMoveDeparture: canMoveDeparture
        )
        apply(edits: merged, syncBase: remoteEdits)
        guard merged != remoteEdits else { return }

        do {
            let accepted = try await planEditsClient.putPlanEdits(
                scope: scope,
                baseRevision: remote.revision,
                edits: merged
            )
            guard publishedTripScope == scope else { return }
            applyAccepted(accepted)
        } catch PublishedTripClientError.revisionConflict(let current) {
            guard publishedTripScope == scope else { return }
            let currentEdits = current.edits.sharedSyncState
            let rebased = PlanEditMerge.rebase(
                local: merged,
                base: remoteEdits,
                remote: currentEdits,
                canMoveDeparture: canMoveDeparture
            )
            apply(edits: rebased, syncBase: currentEdits)
            guard rebased != currentEdits else { return }
            do {
                let accepted = try await planEditsClient.putPlanEdits(
                    scope: scope,
                    baseRevision: current.revision,
                    edits: rebased
                )
                guard publishedTripScope == scope else { return }
                applyAccepted(accepted)
            } catch {
                // Yerel/rebase edilmiş düzenleme ile current tabanı diskte
                // kalır; bir sonraki foreground sync aynı farkı yeniden dener.
            }
        } catch {
            // GET sonrası oluşan yerel fark ve uzak taban diskte kalır.
        }
    }

    private func pushToWeb() {
        guard publishedTripScope != nil else { return }
        Task { await syncFromWeb() }
    }

    /// Kalkış tarihini web'e taşıma yetkisi: sahip cihaz ya da sürücünün cihazı.
    private var canMoveDeparture: Bool {
        canMoveDepartureOverride?() ?? (isOwner || RoleStore.shared.isDriver)
    }

    private func applyAccepted(_ remote: RemotePlanEdits) {
        let accepted = remote.edits.sharedSyncState
        apply(edits: accepted, syncBase: accepted)
    }

    private func apply(edits updatedEdits: TripEdits, syncBase updatedBase: TripEdits) {
        let didChange = edits != updatedEdits
        edits = updatedEdits
        syncBase = updatedBase
        persist()
        persistBase()
        if didChange {
            onChange?(edits)
            objectWillChange.send()
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
