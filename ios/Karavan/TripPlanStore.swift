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
            // Sahipliğe terfide hemen körü körüne yazma: pushToWeb önce uzak
            // hâlle birleştirir, bayat yerel düzenleme yenilerini ezemez.
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

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("trip-edits.json")
    }

    private var baseFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("trip-edits-sync-base.json")
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
    }

    // MARK: - Cihazlar arası senkron

    /// Web'deki düzenlemeleri çeker; bu cihazda henüz gönderilmemiş yerel
    /// değişiklikleri koruyarak birleştirir. Gün düzenlemesini herkes
    /// yapabildiği için sahip cihaz da çeker. Birleşik hâl uzaktakinden
    /// farklıysa (yerel değişiklik varsa) geri gönderilir.
    func syncFromWeb() async {
        guard !syncing, let url = Config.editsURL else { return }
        syncing = true
        defer { syncing = false }

        guard let remote = await Self.fetchRemote(url: url) else { return }
        lastSyncedAt = Date()
        let merged = merge(local: edits, base: syncBase, remote: remote)
        syncBase = remote
        persistBase()

        if merged != edits {
            edits = merged
            persist()
            onChange?(edits)
            objectWillChange.send()
        }
        // Yerel değişiklikler uzaktakinde yoksa birleşik hâli geri gönder.
        if merged != remote { enqueue(merged, url: url) }
    }

    /// Düzenlemeleri web'e yazar. Gün düzenlemelerini HER cihaz gönderebilir;
    /// kalkış tarihi yalnızca sahip/sürücü yükünde yer alır. Gönderimden önce
    /// uzak hâl çekilip yerel değişikliklerle birleştirilir: bayat cihaz
    /// başkasının yeni düzenlemesini ezemez. Gönderim outbox üzerinden
    /// sıralı + yeniden denemeli yapılır.
    private func pushToWeb() {
        guard let url = Config.editsURL else { return }
        Task {
            var outgoing = edits
            if let remote = await Self.fetchRemote(url: url) {
                outgoing = merge(local: edits, base: syncBase, remote: remote)
                if outgoing != edits {
                    edits = outgoing
                    persist()
                    onChange?(edits)
                    objectWillChange.send()
                }
            }
            enqueue(outgoing, url: url)
        }
    }

    /// Uzak düzenlemeleri GET ile çeker; hata/eksik veride nil.
    private static func fetchRemote(url: URL) async -> TripEdits? {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let remote = try? decoder.decode(TripEdits.self, from: data)
        else { return nil }
        return remote
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

    /// Yükü outbox'a bırakır. Takipçi yükünde departureAt ANAHTARI HİÇ
    /// GÖNDERİLMEZ: takipçi kalkışı asla taşıyamaz (sunucu eksik anahtarı
    /// "mevcudu koru" sayar — bkz. src/pages/api/edits.ts).
    private func enqueue(_ outgoing: TripEdits, url: URL) {
        var payload: [String: Any] = ["days": Self.encodeDays(outgoing.days)]
        if canMoveDeparture {
            if let dep = outgoing.departureAt {
                payload["departureAt"] = ISO8601DateFormatter().string(from: dep)
            } else {
                payload["departureAt"] = NSNull()
            }
        }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        let signature = String(data: body, encoding: .utf8) ?? ""
        PublishOutbox.shared.enqueue(key: "edits", url: url, body: body, signature: signature)
        syncBase = outgoing
        persistBase()
    }

    private static func encodeDays(_ days: [String: DayEdit]) -> [String: Any] {
        let safeDays = days.mapValues { edit in
            var safe = edit
            safe.arrivalTarget = edit.arrivalTarget?.publicSummary
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

    func setArrivalTarget(_ target: ArrivalTarget, stay: StayDetails, slug: String) {
        update(slug: slug) { edit in
            edit.arrivalTarget = target.publicSummary
            var safeStay = stay
            safeStay.reservationReference = nil
            safeStay.note = nil
            safeStay.lastContactedAt = nil
            edit.stayDetails = safeStay
        }
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
}
