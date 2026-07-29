import Foundation

@MainActor
protocol AuthenticatedRequestSending: AnyObject {
    var hasSession: Bool { get }
    func data(path: String, method: String, body: Data?) async throws -> (Data, HTTPURLResponse)
}

@MainActor
final class BearerSessionCoordinator: AuthenticatedRequestSending {
    static let shared = BearerSessionCoordinator()
    var hasSession: Bool { false }

    func data(path: String, method: String, body: Data?) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.userAuthenticationRequired)
    }
}

final class RoleStore {
    static let shared = RoleStore()
    var isDriver = false
}

private var failures = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ✓ \(message)")
    } else {
        failures += 1
        fputs("  ✗ \(message)\n", stderr)
    }
}

@MainActor
private final class CapturingAuthenticatedSender: AuthenticatedRequestSending {
    struct Reply {
        let status: Int
        let body: Data
    }

    var replies: [Reply] = []
    private(set) var calls: [(path: String, method: String, body: Data?)] = []
    var hasSession: Bool { true }

    func data(path: String, method: String, body: Data?) async throws -> (Data, HTTPURLResponse) {
        calls.append((path, method, body))
        let reply = replies.removeFirst()
        let response = HTTPURLResponse(
            url: URL(string: "https://example.test/api/v2/\(path)")!,
            statusCode: reply.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (reply.body, response)
    }
}

@MainActor
private final class ScriptedPlanClient: PlanEditSending {
    enum PutReply {
        case value(RemotePlanEdits)
        case conflict(RemotePlanEdits)
        case offline
    }

    var getReply: Result<RemotePlanEdits, Error>
    var putReplies: [PutReply]
    private(set) var getCalls = 0
    private(set) var puts: [(revision: Int, edits: TripEdits)] = []

    init(get: Result<RemotePlanEdits, Error>, puts: [PutReply] = []) {
        getReply = get
        putReplies = puts
    }

    func getPlanEdits(scope: PublishedTripScope) async throws -> RemotePlanEdits {
        getCalls += 1
        return try getReply.get()
    }

    func putPlanEdits(
        scope: PublishedTripScope,
        baseRevision: Int,
        edits: TripEdits
    ) async throws -> RemotePlanEdits {
        puts.append((baseRevision, edits))
        switch putReplies.removeFirst() {
        case .value(let value): return value
        case .conflict(let current): throw PublishedTripClientError.revisionConflict(current)
        case .offline: throw URLError(.notConnectedToInternet)
        }
    }
}

@MainActor
private final class SuspendedPlanClient: PlanEditSending {
    private(set) var getStarted = false
    private(set) var puts: [(revision: Int, edits: TripEdits)] = []
    private var getContinuation: CheckedContinuation<RemotePlanEdits, Error>?

    func getPlanEdits(scope: PublishedTripScope) async throws -> RemotePlanEdits {
        getStarted = true
        return try await withCheckedThrowingContinuation { continuation in
            getContinuation = continuation
        }
    }

    func putPlanEdits(
        scope: PublishedTripScope,
        baseRevision: Int,
        edits: TripEdits
    ) async throws -> RemotePlanEdits {
        puts.append((baseRevision, edits))
        throw URLError(.notConnectedToInternet)
    }

    func resumeGet(with value: RemotePlanEdits) {
        getContinuation?.resume(returning: value)
        getContinuation = nil
    }
}

@MainActor
private final class SuspendedPutPlanClient: PlanEditSending {
    enum PutReply {
        case value(RemotePlanEdits)
        case conflict(RemotePlanEdits)
    }

    private var immediateGets: [RemotePlanEdits]
    private var immediatePuts: [PutReply]
    private let suspendedPutNumbers: Set<Int>
    private var putContinuations: [Int: CheckedContinuation<RemotePlanEdits, Error>] = [:]
    private var followUpGetContinuation: CheckedContinuation<RemotePlanEdits, Error>?

    private(set) var getCalls = 0
    private(set) var puts: [(revision: Int, edits: TripEdits)] = []
    private(set) var followUpGetStarted = false

    init(
        gets: [RemotePlanEdits],
        suspendPuts: Set<Int>,
        immediatePuts: [PutReply]
    ) {
        immediateGets = gets
        suspendedPutNumbers = suspendPuts
        self.immediatePuts = immediatePuts
    }

    func getPlanEdits(scope: PublishedTripScope) async throws -> RemotePlanEdits {
        getCalls += 1
        if !immediateGets.isEmpty { return immediateGets.removeFirst() }
        followUpGetStarted = true
        return try await withCheckedThrowingContinuation { continuation in
            followUpGetContinuation = continuation
        }
    }

    func putPlanEdits(
        scope: PublishedTripScope,
        baseRevision: Int,
        edits: TripEdits
    ) async throws -> RemotePlanEdits {
        puts.append((baseRevision, edits))
        let number = puts.count
        if suspendedPutNumbers.contains(number) {
            return try await withCheckedThrowingContinuation { continuation in
                putContinuations[number] = continuation
            }
        }
        return try resolve(immediatePuts.removeFirst())
    }

    func resumePut(_ number: Int, with reply: PutReply) {
        guard let continuation = putContinuations.removeValue(forKey: number) else { return }
        switch reply {
        case .value(let value): continuation.resume(returning: value)
        case .conflict(let current):
            continuation.resume(throwing: PublishedTripClientError.revisionConflict(current))
        }
    }

    func resumeFollowUpGet(with value: RemotePlanEdits) {
        followUpGetContinuation?.resume(returning: value)
        followUpGetContinuation = nil
    }

    private func resolve(_ reply: PutReply) throws -> RemotePlanEdits {
        switch reply {
        case .value(let value): return value
        case .conflict(let current): throw PublishedTripClientError.revisionConflict(current)
        }
    }
}

private enum FixtureError: Error {
    case offline
}

@main
struct TripPlanStoreCheck {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("trip-plan-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        print("\n=== Revision istemcisi ===")
        try await checkPublishedClient()

        print("\n=== Üç yönlü yeniden bindirme ===")
        let base = edits(departure: "2026-08-01T06:00:00Z", notes: ["sofya": "taban"])
        let local = edits(departure: "2026-08-02T06:00:00Z", notes: ["sofya": "yerel"])
        let current = edits(
            departure: "2026-08-03T06:00:00Z",
            notes: ["sofya": "uzak", "riga": "yeni uzak gün"]
        )
        let rebased = PlanEditMerge.rebase(
            local: local,
            base: base,
            remote: current,
            canMoveDeparture: false
        )
        expect(rebased.departureAt == current.departureAt, "takipçi uzak kalkışı korur")
        expect(rebased.days["sofya"] == local.days["sofya"], "yerel gün yeniden bindirilir")
        expect(rebased.days["riga"] == current.days["riga"], "ilgili olmayan uzak gün korunur")

        print("\n=== 409 üzerinden tek yeniden deneme ===")
        let conflictRoot = root.appendingPathComponent("conflict", isDirectory: true)
        try seed(local: local, base: base, at: conflictRoot)
        let fetched = remote(revision: 7, edits: edits(
            departure: "2026-08-03T06:00:00Z",
            notes: ["sofya": "ilk uzak"]
        ))
        let conflict = remote(revision: 8, edits: current)
        let acceptedEdits = PlanEditMerge.rebase(
            local: PlanEditMerge.rebase(local: local, base: base, remote: fetched.edits, canMoveDeparture: false),
            base: fetched.edits,
            remote: conflict.edits,
            canMoveDeparture: false
        )
        let accepted = remote(revision: 9, edits: acceptedEdits)
        let conflictClient = ScriptedPlanClient(
            get: .success(fetched),
            puts: [.conflict(conflict), .value(accepted)]
        )
        let conflictStore = TripPlanStore(
            planEditsClient: conflictClient,
            storageDirectory: conflictRoot,
            canMoveDeparture: { false }
        )
        conflictStore.setPublishedTripScope(PublishedTripScope(trip: kuzeyTrip()))
        await conflictStore.syncFromWeb()

        expect(conflictClient.puts.map(\.revision) == [7, 8], "409 yalnız current revision ile bir kez yeniden denenir")
        expect(conflictClient.puts.last?.edits.days["sofya"] == local.days["sofya"], "409 sonrası yerel gün korunur")
        expect(conflictStore.edits.departureAt == current.departureAt, "409 sonrası takipçi current kalkışını kullanır")
        expect(conflictStore.edits.days["riga"] == current.days["riga"], "409 current uzak günü korunur")
        let persistedAccepted = try decodeDiskEdits(conflictRoot, "trip-edits-sync-base.json")
        expect(persistedAccepted == accepted.edits, "başarılı PUT tabanını diske yazar")

        print("\n=== Çevrimdışı ön plan yeniden denemesi ===")
        let offlineRoot = root.appendingPathComponent("offline", isDirectory: true)
        try seed(local: local, base: base, at: offlineRoot)
        let offlineRemote = remote(revision: 12, edits: current)
        let offlineClient = ScriptedPlanClient(get: .success(offlineRemote), puts: [.offline])
        let offlineStore = TripPlanStore(
            planEditsClient: offlineClient,
            storageDirectory: offlineRoot,
            canMoveDeparture: { false }
        )
        offlineStore.setPublishedTripScope(PublishedTripScope(trip: kuzeyTrip()))
        await offlineStore.syncFromWeb()
        let retainedLocal = try decodeDiskEdits(offlineRoot, "trip-edits.json")
        let retainedBase = try decodeDiskEdits(offlineRoot, "trip-edits-sync-base.json")
        expect(retainedLocal.days["sofya"] == local.days["sofya"], "ağ hatası yerel günü diskte tutar")
        expect(retainedBase == offlineRemote.edits, "ağ hatası yeniden deneme tabanını diskte tutar")

        offlineClient.getReply = .success(offlineRemote)
        offlineClient.putReplies = [.value(remote(revision: 13, edits: retainedLocal))]
        await offlineStore.syncFromWeb()
        expect(offlineClient.puts.map(\.revision) == [12, 12], "ön plana geliş bekleyen yerel farkı yeniden dener")

        print("\n=== Uygun olmayan gezi ağ geçidi ===")
        let standardClient = ScriptedPlanClient(get: .failure(FixtureError.offline))
        let standardStore = TripPlanStore(
            planEditsClient: standardClient,
            storageDirectory: root.appendingPathComponent("standard"),
            canMoveDeparture: { false }
        )
        standardStore.setPublishedTripScope(PublishedTripScope(trip: standardTrip()))
        await standardStore.syncFromWeb()
        standardStore.update(slug: "sofya") { $0.note = "yalnızca cihaz" }
        await settle()
        expect(standardClient.getCalls == 0 && standardClient.puts.isEmpty,
               "standart gezi GET veya PUT yapmaz")

        let transitionRoot = root.appendingPathComponent("scope-transition", isDirectory: true)
        try seed(local: local, base: base, at: transitionRoot)
        let transitionClient = SuspendedPlanClient()
        let transitionStore = TripPlanStore(
            planEditsClient: transitionClient,
            storageDirectory: transitionRoot,
            canMoveDeparture: { false }
        )
        transitionStore.setPublishedTripScope(PublishedTripScope(trip: kuzeyTrip()))
        let inFlight = Task { await transitionStore.syncFromWeb() }
        await waitUntil { transitionClient.getStarted }
        transitionStore.setPublishedTripScope(PublishedTripScope(trip: standardTrip()))
        transitionClient.resumeGet(with: remote(revision: 20, edits: current))
        await inFlight.value
        expect(transitionClient.puts.isEmpty, "standart geziye geçiş eski kapsam için PUT yapmaz")
        expect(transitionStore.edits == local, "eski kapsam yanıtı standart gezi durumunu değiştirmez")

        print("\n=== PUT sırasında yerel düzenleme ===")
        try await checkSuccessfulPutRace(at: root.appendingPathComponent("put-race"))

        print("\n=== 409/retry sırasında yerel düzenleme ===")
        try await checkConflictPutRace(at: root.appendingPathComponent("conflict-race"))

        try checkPrivateScopedPersistence(at: root.appendingPathComponent("private"))

        print("\n" + (failures == 0 ? "✅ TÜM KONTROLLER GEÇTİ" : "❌ \(failures) KONTROL BAŞARISIZ"))
        exit(failures == 0 ? 0 : 1)
    }

    @MainActor
    private static func checkPublishedClient() async throws {
        let sender = CapturingAuthenticatedSender()
        sender.replies = [
            .init(status: 200, body: Data(#"{"revision":3,"departureAt":"2026-08-01T06:00:00.123Z","days":{},"updatedAt":"2026-07-29T12:00:00.456Z"}"#.utf8)),
            .init(status: 409, body: Data(#"{"error":"revision_conflict","current":{"revision":4,"departureAt":"2026-08-02T06:00:00Z","days":{},"updatedAt":"2026-07-29T12:01:00Z"}}"#.utf8)),
            .init(status: 200, body: Data(#"{"revision":5,"departureAt":null,"days":{},"updatedAt":"2026-07-29T12:02:00Z"}"#.utf8)),
        ]
        let client = PublishedTripClient(authenticated: sender)
        let scope = PublishedTripScope(trip: kuzeyTrip())!
        let fetched = try await client.getPlanEdits(scope: scope)
        expect(fetched.revision == 3, "GET revision zarfını çözer")
        expect(fetched.departureAt == date("2026-08-01T06:00:00.123Z"), "kesirli ISO-8601 kalkışı çözer")
        expect(fetched.updatedAt == date("2026-07-29T12:00:00.456Z"), "kesirli ISO-8601 updatedAt'i çözer")

        do {
            _ = try await client.putPlanEdits(scope: scope, baseRevision: 3, edits: fetched.edits)
            expect(false, "409 current typed conflict üretir")
        } catch PublishedTripClientError.revisionConflict(let current) {
            expect(current.revision == 4, "409 current revision'ı taşır")
            expect(current.departureAt == date("2026-08-02T06:00:00Z"), "kesirsiz ISO-8601 current'ı çözer")
        } catch {
            expect(false, "409 current typed conflict üretir")
        }

        _ = try await client.putPlanEdits(scope: scope, baseRevision: 4, edits: TripEdits())

        expect(sender.calls.map(\.path) == [
            "trips/kuzey-2026/plan-edits",
            "trips/kuzey-2026/plan-edits",
            "trips/kuzey-2026/plan-edits",
        ], "GET ve PUT trip kapsamındaki plan-edits yolunu kullanır")
        expect(sender.calls.map(\.method) == ["GET", "PUT", "PUT"], "istemci GET ve PUT yöntemlerini korur")
        let payload = try JSONSerialization.jsonObject(with: sender.calls[1].body!) as? [String: Any]
        expect(payload?["baseRevision"] as? Int == 3, "PUT baseRevision gönderir")
        expect(payload?["days"] is [String: Any], "PUT days nesnesi gönderir")
        let resetPayload = try JSONSerialization.jsonObject(with: sender.calls[2].body!) as? [String: Any]
        expect(resetPayload?["departureAt"] is NSNull, "kalkış sıfırlama PUT'ta null gönderir")
    }

    @MainActor
    private static func checkSuccessfulPutRace(at root: URL) async throws {
        let base = edits(departure: "2026-08-10T06:00:00Z", notes: ["sofya": "taban"])
        let submitted = edits(departure: "2026-08-11T06:00:00Z", notes: ["sofya": "ilk yerel"])
        let postSubmit = edits(
            departure: "2026-08-12T06:00:00Z",
            notes: ["sofya": "ilk yerel", "riga": "PUT beklerken"]
        )
        try seed(local: submitted, base: base, at: root)

        let fetched = remote(revision: 30, edits: base)
        let accepted = remote(revision: 31, edits: submitted)
        let final = remote(revision: 32, edits: postSubmit)
        let client = SuspendedPutPlanClient(
            gets: [fetched],
            suspendPuts: [1],
            immediatePuts: [.value(final)]
        )
        let store = TripPlanStore(
            planEditsClient: client,
            storageDirectory: root,
            canMoveDeparture: { true }
        )
        store.setPublishedTripScope(PublishedTripScope(trip: kuzeyTrip()))

        let sync = Task { await store.syncFromWeb() }
        await waitUntil { client.puts.count == 1 }
        store.update(slug: "riga") { $0.note = "PUT beklerken" }
        store.setDeparture(date("2026-08-12T06:00:00Z"))
        let diskWhileFirstPutWaits = try decodeDiskEdits(root, "trip-edits.json")
        expect(diskWhileFirstPutWaits == postSubmit,
               "askıdaki ilk PUT sırasında yeni yerel durum diske yazılır")

        client.resumePut(1, with: .value(accepted))
        await sync.value
        await waitUntil { client.followUpGetStarted }

        expect(store.edits == postSubmit, "eski 2xx yeni yerel gün ve kalkışı ezmez")
        let diskAfterFirstSuccess = try decodeDiskEdits(root, "trip-edits.json")
        let baseAfterFirstSuccess = try decodeDiskEdits(root, "trip-edits-sync-base.json")
        expect(diskAfterFirstSuccess == postSubmit, "eski 2xx diskteki yeni yerel durumu ezmez")
        expect(baseAfterFirstSuccess == accepted.edits,
               "eski 2xx yalnızca kabul edilen sync tabanını ilerletir")

        client.resumeFollowUpGet(with: accepted)
        await waitUntil { client.puts.count == 2 && !store.syncing }
        await settle()
        expect(client.puts.map(\.revision) == [30, 31], "2xx sonrası tam bir takip PUT'u yapılır")
        expect(client.puts.dropFirst().first?.edits == postSubmit, "takip PUT'u yeni yerel durumu gönderir")
        expect(client.getCalls == 2, "2xx sonrası yalnız bir takip senkronu yapılır")
        expect(store.edits == postSubmit, "takip senkronu son yerel durumu korur")
        let finalBase = try decodeDiskEdits(root, "trip-edits-sync-base.json")
        expect(finalBase == final.edits,
               "takip PUT'u başarısı diskteki tabanı ilerletir")
    }

    @MainActor
    private static func checkConflictPutRace(at root: URL) async throws {
        let base = edits(departure: "2026-08-20T06:00:00Z", notes: ["sofya": "taban"])
        let submitted = edits(departure: "2026-08-21T06:00:00Z", notes: ["sofya": "ilk yerel"])
        let currentEdits = edits(
            departure: "2026-08-24T06:00:00Z",
            notes: ["sofya": "uzak çakışma", "tallinn": "uzak gün"]
        )
        let retryEdits = edits(
            departure: "2026-08-22T06:00:00Z",
            notes: ["sofya": "ilk yerel", "riga": "ilk PUT beklerken", "tallinn": "uzak gün"]
        )
        let postRetry = edits(
            departure: "2026-08-23T06:00:00Z",
            notes: [
                "sofya": "ilk yerel",
                "riga": "ilk PUT beklerken",
                "tallinn": "uzak gün",
                "kaunas": "retry beklerken",
            ]
        )
        try seed(local: submitted, base: base, at: root)

        let fetched = remote(revision: 40, edits: base)
        let current = remote(revision: 41, edits: currentEdits)
        let retryAccepted = remote(revision: 42, edits: retryEdits)
        let final = remote(revision: 43, edits: postRetry)
        let client = SuspendedPutPlanClient(
            gets: [fetched],
            suspendPuts: [1, 2],
            immediatePuts: [.value(final)]
        )
        let store = TripPlanStore(
            planEditsClient: client,
            storageDirectory: root,
            canMoveDeparture: { true }
        )
        store.setPublishedTripScope(PublishedTripScope(trip: kuzeyTrip()))

        let sync = Task { await store.syncFromWeb() }
        await waitUntil { client.puts.count == 1 }
        store.update(slug: "riga") { $0.note = "ilk PUT beklerken" }
        store.setDeparture(date("2026-08-22T06:00:00Z"))
        client.resumePut(1, with: .conflict(current))
        await waitUntil { client.puts.count == 2 }

        expect(client.puts.dropFirst().first?.revision == 41, "409 retry current revision ile yapılır")
        expect(client.puts.dropFirst().first?.edits == retryEdits, "409 retry uzak current ile PUT sırası yerel farklarını birleştirir")
        expect(store.edits == retryEdits, "409 current bellekte yeni yerel farkları korur")
        let diskAfterConflict = try decodeDiskEdits(root, "trip-edits.json")
        let baseAfterConflict = try decodeDiskEdits(root, "trip-edits-sync-base.json")
        expect(diskAfterConflict == retryEdits, "409 current diskte yeni yerel farkları korur")
        expect(baseAfterConflict == current.edits,
               "409 current diskteki sync tabanını ilerletir")

        store.update(slug: "kaunas") { $0.note = "retry beklerken" }
        store.setDeparture(date("2026-08-23T06:00:00Z"))
        client.resumePut(2, with: .value(retryAccepted))
        await sync.value
        await waitUntil { client.followUpGetStarted }

        expect(store.edits == postRetry, "retry 2xx retry sırasındaki yerel farkı ezmez")
        let diskAfterRetrySuccess = try decodeDiskEdits(root, "trip-edits.json")
        let baseAfterRetrySuccess = try decodeDiskEdits(root, "trip-edits-sync-base.json")
        expect(diskAfterRetrySuccess == postRetry, "retry 2xx diskteki son yerel durumu ezmez")
        expect(baseAfterRetrySuccess == retryAccepted.edits,
               "retry 2xx yalnızca kabul edilen sync tabanını ilerletir")

        client.resumeFollowUpGet(with: retryAccepted)
        await waitUntil { client.puts.count == 3 && !store.syncing }
        await settle()
        expect(client.puts.map(\.revision) == [40, 41, 42], "409 bir retry ve bir takip PUT'u ile sınırlıdır")
        expect(client.puts.dropFirst(2).first?.edits == postRetry, "409 takip PUT'u retry sırasındaki farkı gönderir")
        expect(client.getCalls == 2, "409/retry sonrası yalnız bir takip senkronu yapılır")
        expect(store.edits == postRetry, "409 takip senkronu son yerel durumu korur")
        let finalBase = try decodeDiskEdits(root, "trip-edits-sync-base.json")
        expect(finalBase == final.edits,
               "409 takip PUT'u diskteki tabanı son duruma ilerletir")
    }

    @MainActor
    private static func checkPrivateScopedPersistence(at root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let scope = ArrivalTargetOverrideScope(
            tripID: "trip-private",
            daySlug: "istanbul-sofya",
            userID: "user-private"
        )
        let contactedAt = Date(timeIntervalSince1970: 1_785_146_400)
        let target = ArrivalTarget(
            id: "private-camp",
            mapItemIdentifier: "maps-private-camp",
            name: "Private Camp",
            kind: .campground,
            latitude: 42.66,
            longitude: 23.28,
            formattedAddress: "Sofia, Bulgaria",
            phone: "+359 88 123 4567",
            whatsAppPhone: "+359 88 765 4321",
            email: "private@example.com",
            websiteURL: URL(string: "https://private.example.com/book")!,
            maximumLengthMeters: 11.5,
            source: .user,
            updatedAt: contactedAt
        )
        let stay = StayDetails(
            checkIn: contactedAt.addingTimeInterval(3_600),
            checkOut: contactedAt.addingTimeInterval(90_000),
            reservationStatus: .confirmed,
            reservationReference: "PRIVATE-REF-42",
            note: "Gate code 2468",
            estimatedArrival: "18:00–19:00",
            lastContactedAt: contactedAt
        )

        print("\n=== Private scoped arrival target persistence ===")
        let store = TripPlanStore(storageDirectory: root)
        store.setArrivalTarget(target, stay: stay, slug: scope.daySlug, scope: scope)
        let relaunched = TripPlanStore(storageDirectory: root)
        expect(relaunched.arrivalTargetOverride(slug: scope.daySlug, scope: scope)?.target == target,
               "relaunch restores every target field")
        expect(relaunched.arrivalTargetOverride(slug: scope.daySlug, scope: scope)?.stay == stay,
               "relaunch restores every stay field")
        expect(relaunched.edits == TripEdits(), "private selection never enters shared edits")
    }

    private static func seed(local: TripEdits, base: TripEdits, at root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(local).write(
            to: root.appendingPathComponent("trip-edits.json"), options: .atomic
        )
        try JSONEncoder().encode(base).write(
            to: root.appendingPathComponent("trip-edits-sync-base.json"), options: .atomic
        )
    }

    private static func decodeDiskEdits(_ root: URL, _ filename: String) throws -> TripEdits {
        try JSONDecoder().decode(
            TripEdits.self,
            from: Data(contentsOf: root.appendingPathComponent(filename))
        )
    }

    private static func edits(departure: String?, notes: [String: String]) -> TripEdits {
        var value = TripEdits()
        value.departureAt = departure.map(date)
        for (slug, note) in notes {
            var edit = DayEdit()
            edit.note = note
            value.days[slug] = edit
        }
        return value
    }

    private static func remote(revision: Int, edits: TripEdits) -> RemotePlanEdits {
        RemotePlanEdits(
            revision: revision,
            departureAt: edits.departureAt,
            days: edits.days,
            updatedAt: date("2026-07-29T12:00:00Z")
        )
    }

    private static func date(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = formatter.date(from: text) { return value }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)!
    }

    private static func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @MainActor
    private static func waitUntil(
        attempts: Int = 100,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<attempts where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func kuzeyTrip() -> AccountTrip {
        trip(id: "kuzey-2026", kind: .kuzey2026, features: .kuzey)
    }

    private static func standardTrip() -> AccountTrip {
        trip(id: "standard-2026", kind: .standard, features: .standard)
    }

    private static func trip(id: String, kind: AccountTripKind, features: TripFeatures) -> AccountTrip {
        AccountTrip(
            id: id,
            name: id,
            kind: kind,
            transportMode: nil,
            revision: 1,
            createdAt: "2026-07-29T00:00:00Z",
            updatedAt: "2026-07-29T00:00:00Z",
            stops: [],
            members: [],
            invites: [],
            features: features,
            access: TripAccess(
                tripRole: .owner,
                canEditTrip: true,
                canEditStops: true,
                canEditJournal: true,
                canManageMembers: true,
                canStartRoute: true,
                canDeleteTrip: true
            )
        )
    }
}
