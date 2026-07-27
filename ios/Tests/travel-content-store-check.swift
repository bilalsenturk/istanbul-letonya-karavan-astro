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
        let statusCode: Int?
        let contentType: String?
    }

    private static let lock = NSLock()
    private static var responses: [Response] = []
    private static var requests: [URLRequest] = []

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests.count
    }

    static var lastRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests.last
    }
    private var stopped = false

    static func enqueue(_ response: Response) {
        lock.lock()
        responses.append(response)
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        responses = []
        requests = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let response = Self.responses.isEmpty
            ? Response(data: nil, error: FixtureError.offline, delay: 0, ignoresCancellation: false,
                       statusCode: 200, contentType: "application/json")
            : Self.responses.removeFirst()
        Self.lock.unlock()

        DispatchQueue.global().asyncAfter(deadline: .now() + response.delay) { [weak self] in
            guard let self, response.ignoresCancellation || !self.stopped else { return }
            if let error = response.error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }
            let responseObject: URLResponse
            if let statusCode = response.statusCode {
                responseObject = HTTPURLResponse(
                    url: self.request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1",
                    headerFields: response.contentType.map { ["Content-Type": $0] }
                )!
            } else {
                responseObject = URLResponse(
                    url: self.request.url!, mimeType: response.contentType,
                    expectedContentLength: response.data?.count ?? 0, textEncodingName: nil
                )
            }
            self.client?.urlProtocol(self, didReceive: responseObject, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: response.data ?? Data())
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() { stopped = true }
}

private enum FixtureError: Error { case offline }

private func mutated(_ data: Data, _ change: (inout [String: Any]) -> Void) -> Data {
    var object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    change(&object)
    return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func versioned(_ data: Data, _ version: Int) -> Data {
    mutated(data) { $0["version"] = version }
}

private func mutatedDestination(
    _ data: Data,
    key: String = "sofia",
    _ change: (inout [String: Any]) -> Void
) -> Data {
    mutated(data) { root in
        var destinations = root["destinations"] as! [String: Any]
        var destination = destinations[key] as! [String: Any]
        change(&destination)
        destinations[key] = destination
        root["destinations"] = destinations
    }
}

private func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FixtureURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func fixture(_ data: Data? = nil, error: Error? = nil, delay: TimeInterval = 0,
                     ignoresCancellation: Bool = false, statusCode: Int? = 200,
                     contentType: String? = "application/json") -> FixtureURLProtocol.Response {
    .init(data: data, error: error, delay: delay, ignoresCancellation: ignoresCancellation,
          statusCode: statusCode, contentType: contentType)
}

@main
struct TravelContentStoreCheck {
    @MainActor
    static func main() async {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("travel-content-store-\(UUID().uuidString)", isDirectory: true)
        try! fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let committedEmbedded = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let embedded = versioned(committedEmbedded, 1)
        let remote = versioned(committedEmbedded, 2)
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
        check("istek JSON kabul başlığını taşır",
              FixtureURLProtocol.lastRequest?.value(forHTTPHeaderField: "Accept") == "application/json")
        check("istek 12 saniye zaman aşımı kullanır",
              FixtureURLProtocol.lastRequest?.timeoutInterval == 12)
        check("istek protokol önbellek politikasını kullanır",
              FixtureURLProtocol.lastRequest?.cachePolicy == .useProtocolCachePolicy)

        FixtureURLProtocol.enqueue(fixture(versioned(committedEmbedded, 20), statusCode: 500))
        await store.load()
        check("2xx dışındaki HTTP yanıtları yayınlanmaz", store.bundle?.version == 2)

        FixtureURLProtocol.enqueue(fixture(versioned(committedEmbedded, 21), contentType: "text/html"))
        await store.load()
        check("JSON olmayan MIME türü yayınlanmaz", store.bundle?.version == 2)

        FixtureURLProtocol.enqueue(fixture(versioned(committedEmbedded, 22), contentType: "application/vnd.kuzey+json; charset=utf-8"))
        await store.load()
        check("+json MIME türü ve charset kabul edilir", store.bundle?.version == 22)

        FixtureURLProtocol.enqueue(fixture(Data(repeating: 0x20, count: 2 * 1_024 * 1_024 + 1)))
        await store.load()
        check("2 MiB üzerindeki gövde yayınlanmaz", store.bundle?.version == 22)

        FixtureURLProtocol.enqueue(fixture(error: FixtureError.offline))
        await store.load()
        check("ağ hatası mevcut geçerli paketi korur", store.bundle?.version == 22)

        FixtureURLProtocol.enqueue(fixture(Data("{not-json".utf8)))
        await store.load()
        check("bozuk uzak JSON mevcut geçerli paketi temizlemez", store.bundle?.version == 22)

        let cached = versioned(committedEmbedded, 3)
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

        FixtureURLProtocol.enqueue(fixture(versioned(committedEmbedded, 4), delay: 0.18, ignoresCancellation: true))
        FixtureURLProtocol.enqueue(fixture(versioned(committedEmbedded, 5), delay: 0.01))
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

        FixtureURLProtocol.enqueue(fixture(versioned(committedEmbedded, 6), delay: 0.08, ignoresCancellation: true))
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

        let admissionNow = ISO8601DateFormatter().date(from: "2026-07-27T12:00:00Z")!
        let admits: (Data) -> Bool = { TravelContentStore.decodeValid($0, now: admissionNow) != nil }
        check("tam commitli veri admission politikasını geçer", admits(committedEmbedded))
        check("90 günden eski doğrulama paketi reddettirmez",
              TravelContentStore.decodeValid(committedEmbedded,
                                             now: ISO8601DateFormatter().date(from: "2026-11-01T12:00:00Z")!) != nil)

        let missingDestination = mutated(committedEmbedded) { root in
            var destinations = root["destinations"] as! [String: Any]
            destinations.removeValue(forKey: "riga")
            root["destinations"] = destinations
        }
        check("tam altı destinasyon anahtarı zorunludur", !admits(missingDestination))

        check("pozitif içerik sürümü zorunludur",
              !admits(mutated(committedEmbedded) { $0["version"] = 0 }))
        check("gelecek üretim tarihi reddedilir",
              !admits(mutated(committedEmbedded) { $0["generatedAt"] = "2027-07-27T00:00:00Z" }))

        let tooFewCamps = mutatedDestination(committedEmbedded) { destination in
            destination["camps"] = Array((destination["camps"] as! [[String: Any]]).prefix(1))
        }
        check("her destinasyonda en az iki kamp zorunludur", !admits(tooFewCamps))

        let tooFewAttractions = mutatedDestination(committedEmbedded) { destination in
            destination["attractions"] = Array((destination["attractions"] as! [[String: Any]]).prefix(2))
        }
        check("her destinasyonda en az üç gezi zorunludur", !admits(tooFewAttractions))

        let invalidCoordinate = mutatedDestination(committedEmbedded) { destination in
            var camps = destination["camps"] as! [[String: Any]]
            var camp = camps[0]
            camp["location"] = ["latitude": 120, "longitude": 23]
            camps[0] = camp
            destination["camps"] = camps
        }
        check("geçersiz koordinat reddedilir", !admits(invalidCoordinate))

        let distantCamp = mutatedDestination(committedEmbedded) { destination in
            var camps = destination["camps"] as! [[String: Any]]
            var camp = camps[0]
            camp["location"] = ["latitude": 41.0, "longitude": 29.0]
            camps[0] = camp
            destination["camps"] = camps
        }
        check("şehir merkezinden 25 km dışındaki kamp reddedilir", !admits(distantCamp))

        let excessivePolicy = mutatedDestination(committedEmbedded) { destination in
            destination["policy"] = ["type": "city", "maximumKm": 26]
        }
        check("25 km üzerindeki şehir politikası sessizce kırpılmadan reddedilir", !admits(excessivePolicy))

        let insecureSource = mutatedDestination(committedEmbedded) { destination in
            var camps = destination["camps"] as! [[String: Any]]
            var camp = camps[0]
            camp["source"] = ["name": "Kaynak", "url": "http://example.test/camp"]
            camps[0] = camp
            destination["camps"] = camps
        }
        check("HTTPS olmayan kaynak reddedilir", !admits(insecureSource))

        let insecurePhotoSource = mutatedDestination(committedEmbedded) { destination in
            var camps = destination["camps"] as! [[String: Any]]
            var camp = camps[0]
            var media = camp["media"] as! [String: Any]
            media["source"] = ["url": "http://example.test/photo.jpg"]
            camp["media"] = media
            camps[0] = camp
            destination["camps"] = camps
        }
        check("HTTPS olmayan fotoğraf kaynağı reddedilir", !admits(insecurePhotoSource))

        let futureVerification = mutatedDestination(committedEmbedded) { destination in
            var camps = destination["camps"] as! [[String: Any]]
            camps[0]["verifiedAt"] = "2027-07-27T00:00:00Z"
            destination["camps"] = camps
        }
        check("gelecek doğrulama tarihi reddedilir", !admits(futureVerification))

        let emptyMediaCredit = mutatedDestination(committedEmbedded) { destination in
            var camps = destination["camps"] as! [[String: Any]]
            var camp = camps[0]
            var media = camp["media"] as! [String: Any]
            media["credit"] = "  "
            camp["media"] = media
            camps[0] = camp
            destination["camps"] = camps
        }
        check("boş medya atfı reddedilir", !admits(emptyMediaCredit))

        let undisclosedRepresentative = mutatedDestination(committedEmbedded) { destination in
            var camps = destination["camps"] as! [[String: Any]]
            var camp = camps[0]
            var media = camp["media"] as! [String: Any]
            media["depictsCampground"] = false
            media["role"] = "campground"
            media["disclosure"] = ""
            camp["media"] = media
            camps[0] = camp
            destination["camps"] = camps
        }
        check("temsili kamp görselinde rol ve açıklama zorunludur", !admits(undisclosedRepresentative))

        let brokenWOKRestriction = mutatedDestination(committedEmbedded, key: "warsaw") { destination in
            var camps = destination["camps"] as! [[String: Any]]
            let index = camps.firstIndex { $0["id"] as? String == "camping-motel-wok" }!
            camps[index]["maximumLengthMeters"] = 9
            destination["camps"] = camps
        }
        check("WOK sekiz metre kısıtı korunur", !admits(brokenWOKRestriction))

        let brokenRigaRestriction = mutatedDestination(committedEmbedded, key: "riga") { destination in
            var camps = destination["camps"] as! [[String: Any]]
            let index = camps.firstIndex { $0["id"] as? String == "camping-yachts" }!
            camps[index].removeValue(forKey: "maximumLengthMeters")
            destination["camps"] = camps
        }
        check("Riga 7,5 metre kısıtı korunur", !admits(brokenRigaRestriction))

        FixtureURLProtocol.reset()
        FixtureURLProtocol.enqueue(fixture(versioned(committedEmbedded, 31), delay: 0.08))
        let coalescingStore = TravelContentStore(
            remoteURL: URL(string: "https://example.test/assets/travel-content.json")!,
            session: session,
            cacheURL: root.appendingPathComponent("coalescing.json"),
            embeddedData: { embedded }
        )
        async let firstLoad: Void = coalescingStore.loadIfNeeded()
        async let duplicateLoad: Void = coalescingStore.loadIfNeeded()
        _ = await (firstLoad, duplicateLoad)
        check("eşzamanlı ilk yüklemeler tek HTTP isteğinde birleşir", FixtureURLProtocol.requestCount == 1)

        FixtureURLProtocol.reset()
        FixtureURLProtocol.enqueue(fixture(error: FixtureError.offline))
        let retryStore = TravelContentStore(
            remoteURL: URL(string: "https://example.test/assets/travel-content.json")!,
            session: session,
            cacheURL: root.appendingPathComponent("retry.json"),
            embeddedData: { embedded }
        )
        await retryStore.loadIfNeeded()
        check("ilk çevrimdışı yükleme gömülü içeriğe düşer", retryStore.bundle?.version == 1)
        FixtureURLProtocol.enqueue(fixture(versioned(committedEmbedded, 32)))
        await retryStore.loadIfNeeded()
        check("fallback sonrası sonraki deneme ağı yeniden dener", retryStore.bundle?.version == 32)
        check("fallback sonrası retry ikinci HTTP isteğini üretir", FixtureURLProtocol.requestCount == 2)

        FixtureURLProtocol.reset()
        FixtureURLProtocol.enqueue(fixture(versioned(committedEmbedded, 40)))
        FixtureURLProtocol.enqueue(fixture(versioned(committedEmbedded, 41)))
        let foregroundStore = TravelContentStore(
            remoteURL: URL(string: "https://example.test/assets/travel-content.json")!,
            session: session,
            cacheURL: root.appendingPathComponent("foreground.json"),
            embeddedData: { embedded }
        )
        let foregroundTime = ISO8601DateFormatter().date(from: "2026-07-27T12:00:00Z")!
        await foregroundStore.refreshIfStale(now: foregroundTime)
        await foregroundStore.refreshIfStale(now: foregroundTime.addingTimeInterval(60))
        check("foreground yenilemeleri beş dakika içinde throttle edilir",
              FixtureURLProtocol.requestCount == 1 && foregroundStore.bundle?.version == 40)
        await foregroundStore.refreshIfStale(now: foregroundTime.addingTimeInterval(301))
        check("throttle süresi geçince foreground yenilemesi tekrar çalışır",
              FixtureURLProtocol.requestCount == 2 && foregroundStore.bundle?.version == 41)

        let countBeforeUnsupportedScheme = FixtureURLProtocol.requestCount
        let unsupportedSchemeStore = TravelContentStore(
            remoteURL: URL(string: "file:///tmp/travel-content.json")!,
            session: session,
            cacheURL: root.appendingPathComponent("unsupported-scheme.json"),
            embeddedData: { embedded }
        )
        await unsupportedSchemeStore.load()
        check("HTTP dışındaki uzak URL şeması istek yapılmadan reddedilir",
              FixtureURLProtocol.requestCount == countBeforeUnsupportedScheme
                && unsupportedSchemeStore.bundle?.version == 1)

        FixtureURLProtocol.enqueue(fixture(versioned(committedEmbedded, 33), statusCode: nil,
                                           contentType: "application/json"))
        let nonHTTPStore = TravelContentStore(
            remoteURL: URL(string: "https://example.test/assets/non-http.json")!,
            session: session,
            cacheURL: root.appendingPathComponent("non-http.json"),
            embeddedData: { embedded }
        )
        await nonHTTPStore.load()
        check("HTTPURLResponse olmayan yanıt yayınlanmaz", nonHTTPStore.bundle?.version == 1)

        FixtureURLProtocol.enqueue(fixture(versioned(committedEmbedded, 34)))
        let unwritableCacheStore = TravelContentStore(
            remoteURL: URL(string: "https://example.test/assets/travel-content.json")!,
            session: session,
            cacheURL: URL(fileURLWithPath: "/dev/null/travel-content.json"),
            embeddedData: { embedded }
        )
        await unwritableCacheStore.load()
        check("disk yazma hatası doğrulanmış bellek içeriğini bozmaz",
              unwritableCacheStore.bundle?.version == 34 && unwritableCacheStore.state == .ready)

        FixtureURLProtocol.reset()
        session.invalidateAndCancel()
        if failures > 0 {
            print("\n❌ \(failures) STORE KONTROLÜ BAŞARISIZ")
            exit(1)
        }
        print("\n✅ SEYAHAT İÇERİĞİ STORE KONTROLLERİ GEÇTİ")
    }
}
