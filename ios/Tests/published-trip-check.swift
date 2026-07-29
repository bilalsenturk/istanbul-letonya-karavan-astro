import Foundation

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
private final class CapturingSender: AuthenticatedRequestSending {
    private(set) var calls: [(path: String, method: String, body: Data?)] = []
    var statusCode = 200
    var responseOK = true
    var hasSession: Bool { true }

    func data(path: String, method: String, body: Data?) async throws -> (Data, HTTPURLResponse) {
        calls.append((path, method, body))
        let response = HTTPURLResponse(
            url: URL(string: "https://example.test/api/v2/\(path)")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        let ok = responseOK ? "true" : "false"
        return (Data("{\"ok\":\(ok),\"revision\":2,\"updatedAt\":\"2026-07-29T12:00:00Z\"}".utf8), response)
    }
}

@MainActor
private final class FailingSender: PublishedTripSending {
    func put(scope: PublishedTripScope, resource: PublishedTripResource, body: Data) async throws {
        throw URLError(.notConnectedToInternet)
    }
}

@MainActor
private final class ScriptedSender: PublishedTripSending {
    var succeeds = false
    private(set) var calls: [(tripID: String, resource: PublishedTripResource)] = []

    func put(scope: PublishedTripScope, resource: PublishedTripResource, body: Data) async throws {
        calls.append((scope.tripID, resource))
        if !succeeds { throw URLError(.notConnectedToInternet) }
    }
}

@main
struct PublishedTripCheck {
    @MainActor
    static func main() async throws {
        let kuzey = trip(id: "kuzey-2026", kind: .kuzey2026, features: .kuzey)
        let standard = trip(id: "balkan-2026", kind: .standard, features: .standard)

        print("\n=== Yayın kapsamı ===")
        expect(PublishedTripScope(trip: kuzey)?.tripID == "kuzey-2026", "public Kuzey yayınlanır")
        expect(PublishedTripScope(trip: standard) == nil, "standart rota reddedilir")
        expect(PublishedTripScope(trip: trip(id: "kuzey-private", kind: .kuzey2026, features: .standard)) == nil,
               "publicTracking kapalı Kuzey reddedilir")

        let revoked = trip(id: kuzey.id, kind: .kuzey2026, features: .standard)
        let refreshedRevoked = PublishedTripScope.reconciledTrip(selected: kuzey, in: [revoked])
        let refreshedMissing = PublishedTripScope.reconciledTrip(selected: kuzey, in: [standard])
        expect(PublishedTripScope(trip: refreshedRevoked) == nil, "yenilenen aynı rota public değilse kapsam kapanır")
        expect(refreshedMissing == nil, "seçili rota yenilenen listeden silindiyse seçim kapanır")

        print("\n=== Kimlik bilgisiz outbox ===")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("publish-outbox.json")
        let outbox = PublishOutbox(fileURL: fileURL, sender: FailingSender(), observeLifecycle: false)
        outbox.setScope(PublishedTripScope(trip: kuzey))
        outbox.enqueue(resource: .expenseSummary, body: Data("{\"totalEur\":12}".utf8))
        await waitUntil { outbox.persistedKeys == ["kuzey-2026:expense-summary"] }
        expect(outbox.persistedKeys == ["kuzey-2026:expense-summary"], "anahtar trip kapsamlıdır")
        let diskJSON = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        expect(!diskJSON.contains("Bearer") && !diskJSON.contains("Authorization"), "kimlik bilgisi/header diske yazılmaz")
        expect(!diskJSON.contains("http"), "mutlak URL diske yazılmaz")

        outbox.setScope(nil)
        expect(outbox.persistedKeys == ["kuzey-2026:expense-summary"], "kapsam kapanınca bekleyen yük silinmez")

        try Data(#"{"pending":{"expenses":{"url":"https://old.example/api/expenses","body":"e30=","signature":"secret"}},"lastSent":{}}"#.utf8)
            .write(to: fileURL, options: .atomic)
        let migrated = PublishOutbox(fileURL: fileURL, sender: FailingSender(), observeLifecycle: false)
        expect(migrated.persistedKeys.isEmpty, "eski kimlik bilgili kayıtlar atılır")

        print("\n=== Duraklatma ve teslim onayı ===")
        let drainURL = root.appendingPathComponent("drain-outbox.json")
        let drainSender = ScriptedSender()
        let draining = PublishOutbox(fileURL: drainURL, sender: drainSender, observeLifecycle: false)
        draining.setScope(PublishedTripScope(trip: kuzey))
        var acknowledged = false
        draining.enqueue(resource: .liveLocation, body: Data("{\"lat\":41}".utf8)) {
            acknowledged = true
        }
        await waitUntil { drainSender.calls.count == 1 }
        expect(!acknowledged, "çevrimdışı kuyruk yayınlandı sayılmaz")
        draining.setScope(nil)
        drainSender.succeeds = true
        draining.retryPending()
        await settle()
        expect(draining.persistedKeys == ["kuzey-2026:live-location"], "nil kapsam bekleyen kaydı korur")
        expect(drainSender.calls.count == 1, "nil kapsam gönderim yapmaz")
        draining.setScope(PublishedTripScope(trip: kuzey))
        await waitUntil { draining.persistedKeys.isEmpty }
        expect(acknowledged, "yalnız başarılı teslim yayın onayı verir")
        expect(draining.persistedKeys.isEmpty, "eşleşen kapsam bekleyen kaydı teslim edip siler")

        let staleURL = root.appendingPathComponent("stale-selection-outbox.json")
        let staleSender = ScriptedSender()
        staleSender.succeeds = true
        let staleOutbox = PublishOutbox(fileURL: staleURL, sender: staleSender, observeLifecycle: false)
        staleOutbox.setScope(PublishedTripScope(trip: refreshedRevoked))
        staleOutbox.enqueue(resource: .expenseSummary, body: Data("{}".utf8))
        await settle()
        expect(staleSender.calls.isEmpty, "yenilemeyle kapsamı kapanan rota gönderim yapmaz")
        staleOutbox.setScope(PublishedTripScope(trip: refreshedMissing))
        staleOutbox.enqueue(resource: .publishedPlan, body: Data("{}".utf8))
        await settle()
        expect(staleSender.calls.isEmpty, "listeden silinen seçili rota gönderim yapmaz")

        print("\n=== Bearer trip isteği ===")
        let sender = CapturingSender()
        let client = PublishedTripClient(authenticated: sender)
        let body = Data("{\"lat\":41.0}".utf8)
        let resources: [PublishedTripResource] = [.liveLocation, .expenseSummary, .publishedPlan, .sharedJournal]
        for resource in resources {
            try await client.put(scope: PublishedTripScope(trip: kuzey)!, resource: resource, body: body)
        }
        expect(sender.calls.map(\.path) == resources.map { "trips/kuzey-2026/\($0.rawValue)" },
               "dört kaynak da trip kapsamlı v2 yolunu kullanır")
        expect(sender.calls.allSatisfy { $0.method == "PUT" }, "dört yayın isteği PUT kullanır")
        expect(sender.calls.allSatisfy { $0.body == body }, "yayın gövdeleri değiştirilmez")

        sender.statusCode = 500
        do {
            try await client.put(scope: PublishedTripScope(trip: kuzey)!, resource: .liveLocation, body: body)
            expect(false, "5xx yayın onayı vermez")
        } catch {
            expect(true, "5xx yayın onayı vermez")
        }

        let rejectedURL = root.appendingPathComponent("rejected-outbox.json")
        let rejectedOutbox = PublishOutbox(fileURL: rejectedURL, sender: client, observeLifecycle: false)
        rejectedOutbox.setScope(PublishedTripScope(trip: kuzey))
        var rejectionAcknowledged = false
        rejectedOutbox.enqueue(resource: .liveLocation, body: body) { rejectionAcknowledged = true }
        await waitUntil { sender.calls.count == resources.count + 2 }
        expect(!rejectionAcknowledged, "sunucu reddi lastPublished onayı üretmez")
        expect(!rejectedOutbox.persistedKeys.isEmpty, "sunucu reddi yükü kuyrukta tutar")
        sender.statusCode = 200
        rejectedOutbox.retryPending()
        await waitUntil { rejectedOutbox.persistedKeys.isEmpty }
        expect(rejectionAcknowledged, "sunucu 2xx yanıtı teslim onayı üretir")

        print("\n" + (failures == 0 ? "✅ YAYIN KONTROLLERİ GEÇTİ" : "❌ \(failures) KONTROL BAŞARISIZ"))
        exit(failures == 0 ? 0 : 1)
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

    @MainActor
    private static func settle() async {
        for _ in 0..<5 { await Task.yield() }
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
            access: TripAccess(tripRole: .owner, canEditTrip: true, canEditStops: true,
                                canEditJournal: true, canManageMembers: true,
                                canStartRoute: true, canDeleteTrip: true)
        )
    }
}
