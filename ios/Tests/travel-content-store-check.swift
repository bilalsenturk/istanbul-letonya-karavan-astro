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
        let contentLength: Int?
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
                       statusCode: 200, contentType: "application/json", contentLength: nil)
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
                var headers = response.contentType.map { ["Content-Type": $0] } ?? [:]
                if let contentLength = response.contentLength {
                    headers["Content-Length"] = String(contentLength)
                }
                responseObject = HTTPURLResponse(
                    url: self.request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1",
                    headerFields: headers
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

private func versioned(_ data: Data, _ marker: Int) -> Data {
    mutatedDestination(data) { destination in
        destination["cityName"] = "Sofya #\(marker)"
    }
}

private func hasMarker(_ bundle: TravelContentBundle?, _ marker: Int) -> Bool {
    bundle?.content(forDestination: "sofia")?.cityName == "Sofya #\(marker)"
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

private func mutatedCamp(
    _ data: Data,
    destinationKey: String,
    campID: String,
    _ change: (inout [String: Any]) -> Void
) -> Data {
    mutatedDestination(data, key: destinationKey) { destination in
        var camps = destination["camps"] as! [[String: Any]]
        let index = camps.firstIndex { $0["id"] as? String == campID }!
        change(&camps[index])
        destination["camps"] = camps
    }
}

private actor OperationGate {
    private var isPaused = false
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func pause() async {
        isPaused = true
        pauseWaiters.forEach { $0.resume() }
        pauseWaiters = []
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilPaused() async {
        if isPaused { return }
        await withCheckedContinuation { pauseWaiters.append($0) }
    }

    func release() {
        isPaused = false
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters = []
    }
}

private actor EmbeddedSequence {
    private let gate: OperationGate
    private let first: Data
    private let second: Data
    private var callCount = 0

    init(gate: OperationGate, first: Data, second: Data) {
        self.gate = gate
        self.first = first
        self.second = second
    }

    func next() async -> Data? {
        callCount += 1
        if callCount == 1 {
            await gate.pause()
            return first
        }
        return second
    }
}

private func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FixtureURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func fixture(_ data: Data? = nil, error: Error? = nil, delay: TimeInterval = 0,
                     ignoresCancellation: Bool = false, statusCode: Int? = 200,
                     contentType: String? = "application/json",
                     contentLength: Int? = nil) -> FixtureURLProtocol.Response {
    .init(data: data, error: error, delay: delay, ignoresCancellation: ignoresCancellation,
          statusCode: statusCode, contentType: contentType, contentLength: contentLength)
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
        check("geçerli uzak paket gömülü paketin yerini alır", hasMarker(store.bundle, 2))
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
        check("2xx dışındaki HTTP yanıtları yayınlanmaz", hasMarker(store.bundle, 2))

        FixtureURLProtocol.enqueue(fixture(versioned(committedEmbedded, 21), contentType: "text/html"))
        await store.load()
        check("JSON olmayan MIME türü yayınlanmaz", hasMarker(store.bundle, 2))

        FixtureURLProtocol.enqueue(fixture(versioned(committedEmbedded, 22), contentType: "application/vnd.kuzey+json; charset=utf-8"))
        await store.load()
        check("+json MIME türü ve charset kabul edilir", hasMarker(store.bundle, 22))

        FixtureURLProtocol.enqueue(fixture(Data(repeating: 0x20, count: 2 * 1_024 * 1_024 + 1)))
        await store.load()
        check("2 MiB üzerindeki gövde yayınlanmaz", hasMarker(store.bundle, 22))

        FixtureURLProtocol.enqueue(fixture(
            versioned(committedEmbedded, 23),
            contentLength: 2 * 1_024 * 1_024 + 1
        ))
        await store.load()
        check("2 MiB üzerindeki Content-Length önceden reddedilir", hasMarker(store.bundle, 22))

        FixtureURLProtocol.enqueue(fixture(error: FixtureError.offline))
        await store.load()
        check("ağ hatası mevcut geçerli paketi korur", hasMarker(store.bundle, 22))

        FixtureURLProtocol.enqueue(fixture(Data("{not-json".utf8)))
        await store.load()
        check("bozuk uzak JSON mevcut geçerli paketi temizlemez", hasMarker(store.bundle, 22))

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
              hasMarker(cachedStore.bundle, 3))

        try! Data("[]".utf8).write(to: cacheURL, options: .atomic)
        FixtureURLProtocol.enqueue(fixture(error: FixtureError.offline))
        let embeddedStore = TravelContentStore(
            remoteURL: URL(string: "https://example.test/assets/travel-content.json")!,
            session: session,
            cacheURL: cacheURL,
            embeddedData: { embedded }
        )
        await embeddedStore.load()
        check("geçersiz disk önbelleği atlanıp gömülü paket kullanılır", hasMarker(embeddedStore.bundle, 1))

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
        check("geç gelen eski istek yeni paketi ezmez", hasMarker(orderingStore.bundle, 5))

        FixtureURLProtocol.enqueue(fixture(versioned(committedEmbedded, 6), delay: 0.08, ignoresCancellation: true))
        let cancelled = Task { await orderingStore.load() }
        cancelled.cancel()
        await cancelled.value
        check("iptal edilen yükleme geçerli paketi değiştirmez", hasMarker(orderingStore.bundle, 5))

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

        let aliasedDestination = mutated(committedEmbedded) { root in
            var destinations = root["destinations"] as! [String: Any]
            destinations["sofya"] = destinations.removeValue(forKey: "sofia")
            root["destinations"] = destinations
        }
        check("normalize edilebilir alias ham kanonik anahtar yerine kabul edilmez", !admits(aliasedDestination))

        check("pozitif içerik sürümü zorunludur",
              !admits(mutated(committedEmbedded) { $0["version"] = 0 }))
        check("yalnız kanonik sürüm 1 kabul edilir",
              !admits(mutated(committedEmbedded) { $0["version"] = 2 }))
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

        let replacedCampID = mutatedCamp(
            committedEmbedded,
            destinationKey: "sofia",
            campID: "mega-park-vrana"
        ) { $0["id"] = "unapproved-camp" }
        check("onaylı kamp kimliği kümesi birebir korunur", !admits(replacedCampID))

        let replacedAttractionID = mutatedDestination(committedEmbedded) { destination in
            var attractions = destination["attractions"] as! [[String: Any]]
            attractions[0]["id"] = "unapproved-attraction"
            destination["attractions"] = attractions
        }
        check("onaylı gezi kimliği kümesi birebir korunur", !admits(replacedAttractionID))

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

        let contradictoryRepresentative = mutatedCamp(
            committedEmbedded,
            destinationKey: "sofia",
            campID: "mega-park-vrana"
        ) { camp in
            var media = camp["media"] as! [String: Any]
            media["depictsCampground"] = true
            camp["media"] = media
        }
        check("kamp görseli temsilî açıklamayla campground iddiasını birlikte taşıyamaz",
              !admits(contradictoryRepresentative))

        for unsafePath in [
            "/assets/../secret.webp",
            "/assets/%2e%2e/secret.webp",
            "/assets/gallery\\secret.webp",
            "/assets/gallery/photo.webp?raw=1",
            "/assets/gallery/photo.webp#fragment",
        ] {
            let unsafeMedia = mutatedCamp(
                committedEmbedded,
                destinationKey: "sofia",
                campID: "mega-park-vrana"
            ) { camp in
                var media = camp["media"] as! [String: Any]
                media["url"] = unsafePath
                camp["media"] = media
            }
            check("güvensiz yerel medya yolu reddedilir: \(unsafePath)", !admits(unsafeMedia))
        }

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

        let brokenAveNatura = mutatedCamp(
            committedEmbedded,
            destinationKey: "budapest",
            campID: "ave-natura-camping"
        ) { $0["maximumLengthMeters"] = 7 }
        check("Ave Natura altı metre kısıtı korunur", !admits(brokenAveNatura))

        let brokenClepardia = mutatedCamp(
            committedEmbedded,
            destinationKey: "krakow",
            campID: "camping-clepardia"
        ) { $0["openingPeriod"] = "Resepsiyon 09:00-20:00" }
        check("Clepardia güncel resepsiyon rehberi korunur", !admits(brokenClepardia))

        let brokenRigaSeason = mutatedCamp(
            committedEmbedded,
            destinationKey: "riga",
            campID: "riga-city-camping"
        ) { $0["openingPeriod"] = "Yıl boyu" }
        check("Riga City Camping sezon bilgisi korunur", !admits(brokenRigaSeason))

        let brokenFarma = mutatedCamp(
            committedEmbedded,
            destinationKey: "novi-sad",
            campID: "auto-camp-farma-47"
        ) { $0["supportsCaravan"] = true }
        check("Farma 47 çekme karavan kısıtı korunur", !admits(brokenFarma))

        let inventedFarmaService = mutatedCamp(
            committedEmbedded,
            destinationKey: "novi-sad",
            campID: "auto-camp-farma-47"
        ) { $0["hasWater"] = true }
        check("Farma 47 için doğrulanmamış hizmet icat edilmez", !admits(inventedFarmaService))

        let inventedFarmaWastewater = mutatedCamp(
            committedEmbedded,
            destinationKey: "novi-sad",
            campID: "auto-camp-farma-47"
        ) { $0["hasWastewaterDisposal"] = true }
        check("Farma 47 için doğrulanmamış atık hizmeti icat edilmez", !admits(inventedFarmaWastewater))

        let movedFarma = mutatedCamp(
            committedEmbedded,
            destinationKey: "novi-sad",
            campID: "auto-camp-farma-47"
        ) { camp in
            camp["location"] = ["latitude": 45.3887, "longitude": 19.8197356]
        }
        check("Farma 47 resmî koordinatı korunur", !admits(movedFarma))

        let vagueFarmaWarning = mutatedCamp(
            committedEmbedded,
            destinationKey: "novi-sad",
            campID: "auto-camp-farma-47"
        ) { $0["warning"] = "Önceden teyit et." }
        check("Farma 47 motorhome ve hizmet uyarısı korunur", !admits(vagueFarmaWarning))

        FixtureURLProtocol.reset()
        FixtureURLProtocol.enqueue(fixture(versioned(committedEmbedded, 60)))
        FixtureURLProtocol.enqueue(fixture(versioned(committedEmbedded, 61)))
        let decodeGate = OperationGate()
        let decodeIO = TravelContentIO { stage, generation in
            if stage == .decode, generation == 1 { await decodeGate.pause() }
        }
        let decodeRaceCache = root.appendingPathComponent("decode-race.json")
        let decodeRaceStore = TravelContentStore(
            remoteURL: URL(string: "https://example.test/assets/travel-content.json")!,
            session: session,
            cacheURL: decodeRaceCache,
            embeddedData: { embedded },
            io: decodeIO
        )
        let pausedDecode = Task { await decodeRaceStore.load() }
        await decodeGate.waitUntilPaused()
        let newerDecode = Task { await decodeRaceStore.load() }
        await newerDecode.value
        await decodeGate.release()
        await pausedDecode.value
        check("eski decode yeni nesil yayınlandıktan sonra belleği ezemez",
              hasMarker(decodeRaceStore.bundle, 61))
        check("eski decode yeni nesil cache'ini ezemez",
              (try? Data(contentsOf: decodeRaceCache)) == versioned(committedEmbedded, 61))

        FixtureURLProtocol.reset()
        let staleCacheWrite = versioned(committedEmbedded, 66)
        let freshCacheWrite = versioned(committedEmbedded, 67)
        FixtureURLProtocol.enqueue(fixture(staleCacheWrite))
        FixtureURLProtocol.enqueue(fixture(freshCacheWrite))
        let cacheWriteGate = OperationGate()
        let cacheWriteIO = TravelContentIO { stage, generation in
            if stage == .cacheWrite, generation == 1 { await cacheWriteGate.pause() }
        }
        let cacheWriteRaceURL = root.appendingPathComponent("cache-write-race.json")
        let cacheWriteRaceStore = TravelContentStore(
            remoteURL: URL(string: "https://example.test/assets/travel-content.json")!,
            session: session,
            cacheURL: cacheWriteRaceURL,
            embeddedData: { embedded },
            io: cacheWriteIO
        )
        let pausedCacheWrite = Task { await cacheWriteRaceStore.load() }
        await cacheWriteGate.waitUntilPaused()
        check("eski nesil cacheWrite aşamasında belleği yayınlamıştır",
              hasMarker(cacheWriteRaceStore.bundle, 66))
        let newerCacheWrite = Task { await cacheWriteRaceStore.load() }
        await newerCacheWrite.value
        await cacheWriteGate.release()
        await pausedCacheWrite.value
        check("cacheWrite sonrası nesil koruması yeni cache'i korur",
              (try? Data(contentsOf: cacheWriteRaceURL)) == freshCacheWrite)

        FixtureURLProtocol.reset()
        let staleFallback = versioned(committedEmbedded, 62)
        let freshRemote = versioned(committedEmbedded, 63)
        try! staleFallback.write(to: root.appendingPathComponent("fallback-race.json"), options: .atomic)
        FixtureURLProtocol.enqueue(fixture(error: FixtureError.offline))
        FixtureURLProtocol.enqueue(fixture(freshRemote))
        let fallbackGate = OperationGate()
        let fallbackIO = TravelContentIO { stage, generation in
            if stage == .cacheRead, generation == 1 { await fallbackGate.pause() }
        }
        let fallbackRaceStore = TravelContentStore(
            remoteURL: URL(string: "https://example.test/assets/travel-content.json")!,
            session: session,
            cacheURL: root.appendingPathComponent("fallback-race.json"),
            embeddedData: { embedded },
            io: fallbackIO
        )
        let pausedFallback = Task { await fallbackRaceStore.load() }
        await fallbackGate.waitUntilPaused()
        let newerRemote = Task { await fallbackRaceStore.load() }
        await newerRemote.value
        await fallbackGate.release()
        await pausedFallback.value
        check("eski cache fallback yeni uzak nesli ezemez", hasMarker(fallbackRaceStore.bundle, 63))

        let embeddedGate = OperationGate()
        let embeddedSequence = EmbeddedSequence(
            gate: embeddedGate,
            first: versioned(committedEmbedded, 64),
            second: versioned(committedEmbedded, 65)
        )
        let embeddedRaceStore = TravelContentStore(
            remoteURL: URL(string: "file:///tmp/not-remote.json")!,
            session: session,
            cacheURL: root.appendingPathComponent("missing-embedded-race.json"),
            embeddedData: { await embeddedSequence.next() }
        )
        let pausedEmbedded = Task { await embeddedRaceStore.load() }
        await embeddedGate.waitUntilPaused()
        let newerEmbedded = Task { await embeddedRaceStore.load() }
        await newerEmbedded.value
        await embeddedGate.release()
        await pausedEmbedded.value
        check("eski async gömülü yükleyici yeni nesli ezemez", hasMarker(embeddedRaceStore.bundle, 65))

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
        check("ilk çevrimdışı yükleme gömülü içeriğe düşer", hasMarker(retryStore.bundle, 1))
        FixtureURLProtocol.enqueue(fixture(versioned(committedEmbedded, 32)))
        await retryStore.loadIfNeeded()
        check("fallback sonrası sonraki deneme ağı yeniden dener", hasMarker(retryStore.bundle, 32))
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
              FixtureURLProtocol.requestCount == 1 && hasMarker(foregroundStore.bundle, 40))
        await foregroundStore.refreshIfStale(now: foregroundTime.addingTimeInterval(301))
        check("throttle süresi geçince foreground yenilemesi tekrar çalışır",
              FixtureURLProtocol.requestCount == 2 && hasMarker(foregroundStore.bundle, 41))

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
                && hasMarker(unsupportedSchemeStore.bundle, 1))

        FixtureURLProtocol.enqueue(fixture(versioned(committedEmbedded, 33), statusCode: nil,
                                           contentType: "application/json"))
        let nonHTTPStore = TravelContentStore(
            remoteURL: URL(string: "https://example.test/assets/non-http.json")!,
            session: session,
            cacheURL: root.appendingPathComponent("non-http.json"),
            embeddedData: { embedded }
        )
        await nonHTTPStore.load()
        check("HTTPURLResponse olmayan yanıt yayınlanmaz", hasMarker(nonHTTPStore.bundle, 1))

        FixtureURLProtocol.enqueue(fixture(versioned(committedEmbedded, 34)))
        let unwritableCacheStore = TravelContentStore(
            remoteURL: URL(string: "https://example.test/assets/travel-content.json")!,
            session: session,
            cacheURL: URL(fileURLWithPath: "/dev/null/travel-content.json"),
            embeddedData: { embedded }
        )
        await unwritableCacheStore.load()
        check("disk yazma hatası doğrulanmış bellek içeriğini bozmaz",
              hasMarker(unwritableCacheStore.bundle, 34) && unwritableCacheStore.state == .ready)

        FixtureURLProtocol.reset()
        session.invalidateAndCancel()
        if failures > 0 {
            print("\n❌ \(failures) STORE KONTROLÜ BAŞARISIZ")
            exit(1)
        }
        print("\n✅ SEYAHAT İÇERİĞİ STORE KONTROLLERİ GEÇTİ")
    }
}
