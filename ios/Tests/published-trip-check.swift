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
    var hasSession: Bool { true }

    func data(path: String, method: String, body: Data?) async throws -> (Data, HTTPURLResponse) {
        calls.append((path, method, body))
        let response = HTTPURLResponse(
            url: URL(string: "https://example.test/api/v2/\(path)")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(#"{"ok":true,"revision":2,"updatedAt":"2026-07-29T12:00:00Z"}"#.utf8), response)
    }
}

@MainActor
private final class FailingSender: PublishedTripSending {
    func put(scope: PublishedTripScope, resource: PublishedTripResource, body: Data) async throws {
        throw URLError(.notConnectedToInternet)
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

        print("\n=== Kimlik bilgisiz outbox ===")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("publish-outbox.json")
        let outbox = PublishOutbox(fileURL: fileURL, sender: FailingSender(), observeLifecycle: false)
        outbox.setScope(PublishedTripScope(trip: kuzey))
        outbox.enqueue(resource: .expenseSummary, body: Data("{\"totalEur\":12}".utf8))
        await Task.yield()
        expect(outbox.persistedKeys == ["kuzey-2026:expense-summary"], "anahtar trip kapsamlıdır")
        expect(!outbox.persistedJSON.contains("Bearer"), "kimlik bilgisi diske yazılmaz")
        expect(!outbox.persistedJSON.contains("http"), "mutlak URL diske yazılmaz")

        outbox.setScope(nil)
        expect(outbox.persistedKeys == ["kuzey-2026:expense-summary"], "kapsam kapanınca bekleyen yük silinmez")

        try Data(#"{"pending":{"expenses":{"url":"https://old.example/api/expenses","body":"e30=","signature":"secret"}},"lastSent":{}}"#.utf8)
            .write(to: fileURL, options: .atomic)
        let migrated = PublishOutbox(fileURL: fileURL, sender: FailingSender(), observeLifecycle: false)
        expect(migrated.persistedKeys.isEmpty, "eski kimlik bilgili kayıtlar atılır")

        print("\n=== Bearer trip isteği ===")
        let sender = CapturingSender()
        let client = PublishedTripClient(authenticated: sender)
        let body = Data("{\"lat\":41.0}".utf8)
        try await client.put(scope: PublishedTripScope(trip: kuzey)!, resource: .liveLocation, body: body)
        expect(sender.calls.count == 1, "yayın isteği bir kez gönderilir")
        expect(sender.calls.first?.path == "trips/kuzey-2026/live-location", "trip kapsamlı v2 yolu kullanılır")
        expect(sender.calls.first?.method == "PUT", "yayın isteği PUT kullanır")
        expect(sender.calls.first?.body == body, "yayın gövdesi değiştirilmez")

        print("\n" + (failures == 0 ? "✅ YAYIN KONTROLLERİ GEÇTİ" : "❌ \(failures) KONTROL BAŞARISIZ"))
        exit(failures == 0 ? 0 : 1)
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
