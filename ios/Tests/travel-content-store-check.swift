import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private var failures = 0

private func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    if condition() {
        print("  ✓ \(name)")
    } else {
        failures += 1
        print("  ✗ \(name)")
    }
}

private final class FixtureURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        let data: Data?
        let error: Error?
        let delay: TimeInterval
        let ignoresCancellation: Bool
    }

    private static let lock = NSLock()
    private static var responses: [Response] = []
    private var stopped = false

    static func enqueue(_ response: Response) {
        lock.lock()
        responses.append(response)
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        responses = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let response = Self.responses.isEmpty
            ? Response(data: nil, error: FixtureError.offline, delay: 0, ignoresCancellation: false)
            : Self.responses.removeFirst()
        Self.lock.unlock()

        DispatchQueue.global().asyncAfter(deadline: .now() + response.delay) { [weak self] in
            guard let self, response.ignoresCancellation || !self.stopped else { return }
            if let error = response.error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }
            let http = HTTPURLResponse(
                url: self.request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            self.client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: response.data ?? Data())
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() { stopped = true }
}

private enum FixtureError: Error { case offline }

private func bundle(version: Int, city: String) -> TravelContentBundle {
    TravelContentBundle(
        version: version,
        generatedAt: Date(timeIntervalSince1970: TimeInterval(version)),
        destinations: [
            city: TravelDestinationContent(
                cityName: city,
                policy: .city(maximumKm: 25),
                camps: [],
                attractions: []
            )
        ]
    )
}

private func encoded(_ bundle: TravelContentBundle) -> Data {
    try! JSONEncoder().encode(bundle)
}

private func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FixtureURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func fixture(_ data: Data? = nil, error: Error? = nil, delay: TimeInterval = 0,
                     ignoresCancellation: Bool = false) -> FixtureURLProtocol.Response {
    .init(data: data, error: error, delay: delay, ignoresCancellation: ignoresCancellation)
}

@main
struct TravelContentStoreCheck {
    @MainActor
    static func main() async {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("travel-content-store-\(UUID().uuidString)", isDirectory: true)
        try! fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let embedded = encoded(bundle(version: 1, city: "Sofya"))
        let committedEmbedded = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let remote = encoded(bundle(version: 2, city: "Riga"))
        let cacheURL = root.appendingPathComponent("travel-content.json")
        let session = makeSession()

        FixtureURLProtocol.enqueue(fixture(remote))
        let store = TravelContentStore(
            remoteURL: URL(string: "https://example.test/assets/travel-content.json")!,
            session: session,
            cacheURL: cacheURL,
            embeddedData: { embedded }
        )
        await store.load()
        check("geçerli uzak paket gömülü paketin yerini alır", store.bundle?.version == 2)
        check("son geçerli uzak veri atomik disk önbelleğine yazılır",
              (try? Data(contentsOf: cacheURL)) == remote)

        FixtureURLProtocol.enqueue(fixture(error: FixtureError.offline))
        await store.load()
        check("ağ hatası mevcut geçerli paketi korur", store.bundle?.version == 2)

        FixtureURLProtocol.enqueue(fixture(Data("{not-json".utf8)))
        await store.load()
        check("bozuk uzak JSON mevcut geçerli paketi temizlemez", store.bundle?.version == 2)

        let cached = encoded(bundle(version: 3, city: "Kraków"))
        try! cached.write(to: cacheURL, options: .atomic)
        FixtureURLProtocol.enqueue(fixture(error: FixtureError.offline))
        let cachedStore = TravelContentStore(
            remoteURL: URL(string: "https://example.test/assets/travel-content.json")!,
            session: session,
            cacheURL: cacheURL,
            embeddedData: { embedded }
        )
        await cachedStore.load()
        check("soğuk başlangıçta ağ hatasından sonra geçerli disk önbelleği kullanılır",
              cachedStore.bundle?.version == 3)

        try! Data("[]".utf8).write(to: cacheURL, options: .atomic)
        FixtureURLProtocol.enqueue(fixture(error: FixtureError.offline))
        let embeddedStore = TravelContentStore(
            remoteURL: URL(string: "https://example.test/assets/travel-content.json")!,
            session: session,
            cacheURL: cacheURL,
            embeddedData: { embedded }
        )
        await embeddedStore.load()
        check("geçersiz disk önbelleği atlanıp gömülü paket kullanılır", embeddedStore.bundle?.version == 1)

        FixtureURLProtocol.enqueue(fixture(error: FixtureError.offline))
        let invalidColdStore = TravelContentStore(
            remoteURL: URL(string: "https://example.test/assets/travel-content.json")!,
            session: session,
            cacheURL: cacheURL,
            embeddedData: { Data("null".utf8) }
        )
        await invalidColdStore.load()
        check("geçersiz disk ve gömülü içerik yayınlanmaz", invalidColdStore.bundle == nil)

        FixtureURLProtocol.enqueue(fixture(encoded(bundle(version: 4, city: "Varşova")), delay: 0.18, ignoresCancellation: true))
        FixtureURLProtocol.enqueue(fixture(encoded(bundle(version: 5, city: "Budapeşte")), delay: 0.01))
        let orderingStore = TravelContentStore(
            remoteURL: URL(string: "https://example.test/assets/travel-content.json")!,
            session: session,
            cacheURL: root.appendingPathComponent("ordering.json"),
            embeddedData: { embedded }
        )
        let oldLoad = Task { await orderingStore.load() }
        try? await Task.sleep(for: .milliseconds(30))
        let newLoad = Task { await orderingStore.load() }
        await newLoad.value
        await oldLoad.value
        check("geç gelen eski istek yeni paketi ezmez", orderingStore.bundle?.version == 5)

        FixtureURLProtocol.enqueue(fixture(encoded(bundle(version: 6, city: "Novi Sad")), delay: 0.08, ignoresCancellation: true))
        let cancelled = Task { await orderingStore.load() }
        cancelled.cancel()
        await cancelled.value
        check("iptal edilen yükleme geçerli paketi değiştirmez", orderingStore.bundle?.version == 5)

        FixtureURLProtocol.enqueue(fixture(error: FixtureError.offline))
        let committedStore = TravelContentStore(
            remoteURL: URL(string: "https://example.test/assets/travel-content.json")!,
            session: session,
            cacheURL: root.appendingPathComponent("committed-embedded.json"),
            embeddedData: { committedEmbedded }
        )
        await committedStore.load()
        check("commitli gömülü paket altı destinasyonu tam çözer", committedStore.bundle?.destinations.count == 6)
        check("Türkçe rota adları altı desteklenen hedefe doğru eşlenir",
              ["Sofya", "Novi Sad", "Budapeşte", "Krakow", "Varşova", "Riga"]
                .allSatisfy { committedStore.content(for: $0) != nil })
        check("kamp temsili görsel açıklaması uygulama modeline taşınır",
              committedStore.content(for: "Sofya")?.camps.first?.media.depictsCampground == false
                && committedStore.content(for: "Sofya")?.camps.first?.media.disclosure?.isEmpty == false)

        FixtureURLProtocol.reset()
        session.invalidateAndCancel()
        if failures > 0 {
            print("\n❌ \(failures) STORE KONTROLÜ BAŞARISIZ")
            exit(1)
        }
        print("\n✅ SEYAHAT İÇERİĞİ STORE KONTROLLERİ GEÇTİ")
    }
}
