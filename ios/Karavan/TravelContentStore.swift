import Combine
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let travelContentMaximumResponseBytes = 2 * 1_024 * 1_024
private let travelContentExpectedDestinationKeys: Set<String> = [
    "sofia", "novi-sad", "budapest", "krakow", "warsaw", "riga"
]
private let travelContentExpectedCampIDs: [String: Set<String>] = [
    "sofia": ["mega-park-vrana", "camper-parking-sofia"],
    "novi-sad": ["auto-camp-farma-47", "eko-kamp-fruska-gora"],
    "budapest": ["haller-camping", "ave-natura-camping"],
    "krakow": ["camping-smok", "camping-clepardia"],
    "warsaw": ["camping-motel-wok", "camper-park-venessa", "camping-warszawa-184"],
    "riga": ["camping-yachts", "riga-city-camping", "camping-zanzibara"],
]
private let travelContentExpectedAttractionIDs: [String: Set<String>] = [
    "sofia": ["alexander-nevsky", "ancient-serdica", "vrana-park"],
    "novi-sad": ["kovilj-monastery-rit", "petrovaradin-fortress", "sremski-karlovci"],
    "budapest": ["parliament-danube", "buda-castle-fishermans-bastion", "heroes-square-szechenyi"],
    "krakow": ["wawel-hill", "main-market-cloth-hall", "kazimierz"],
    "warsaw": ["wilanow-palace", "royal-lazienki", "old-town-royal-route"],
    "riga": ["old-riga", "art-nouveau-district", "riga-central-market"],
]

actor TravelContentIO {
    enum Stage: Equatable, Sendable {
        case decode
        case cacheRead
        case cacheWrite
    }

    typealias Suspension = @Sendable (Stage, Int) async -> Void

    private let suspension: Suspension
    private var latestGeneration = 0

    init(suspension: @escaping Suspension = { _, _ in }) {
        self.suspension = suspension
    }

    func begin(generation: Int) {
        latestGeneration = max(latestGeneration, generation)
    }

    func decode(_ data: Data, now: Date = Date(), generation: Int) async -> TravelContentBundle? {
        await suspension(.decode, generation)
        guard generation == latestGeneration, !Task.isCancelled else { return nil }
        return TravelContentStore.decodeValid(data, now: now)
    }

    func readAndDecode(_ url: URL, now: Date = Date(), generation: Int) async -> TravelContentBundle? {
        await suspension(.cacheRead, generation)
        guard generation == latestGeneration, !Task.isCancelled else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard generation == latestGeneration, !Task.isCancelled else { return nil }
        return TravelContentStore.decodeValid(data, now: now)
    }

    func writeAtomically(_ data: Data, to url: URL, generation: Int) async {
        await suspension(.cacheWrite, generation)
        guard generation == latestGeneration, !Task.isCancelled else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            // Persistence is best-effort; validated in-memory content stays usable.
        }
    }

    func mainBundleData() async -> Data? {
        await Task.yield()
        guard let url = Bundle.main.url(forResource: "travel-content", withExtension: "json") else { return nil }
        return try? Data(contentsOf: url)
    }
}

private let travelContentBundleReader = TravelContentIO()

@MainActor
final class TravelContentStore: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case unavailable
    }

    @Published private(set) var bundle: TravelContentBundle?
    @Published private(set) var state: LoadState = .idle

    private let remoteURL: URL
    private let session: URLSession
    private let cacheURL: URL
    private let embeddedData: @Sendable () async -> Data?
    private let io: TravelContentIO
    private var generation = 0
    private var activeTask: Task<(Data, URLResponse), Error>?
    private var coalescedTask: Task<Void, Never>?
    private var coalescedTaskID: UUID?
    private var remoteLoadSucceeded = false
    private var lastForegroundRefresh: Date?

    init(
        remoteURL: URL,
        session: URLSession = .shared,
        cacheURL: URL = TravelContentStore.defaultCacheURL(),
        embeddedData: @escaping @Sendable () async -> Data? = {
            await travelContentBundleReader.mainBundleData()
        },
        io: TravelContentIO = TravelContentIO()
    ) {
        self.remoteURL = remoteURL
        self.session = session
        self.cacheURL = cacheURL
        self.embeddedData = embeddedData
        self.io = io
    }

    func loadIfNeeded() async {
        guard !remoteLoadSucceeded else { return }
        await coalescedLoad()
    }

    func refreshIfStale(
        now: Date = Date(),
        minimumInterval: TimeInterval = 5 * 60
    ) async {
        if let lastForegroundRefresh,
           now.timeIntervalSince(lastForegroundRefresh) < minimumInterval {
            return
        }
        lastForegroundRefresh = now
        await coalescedLoad()
    }

    private func coalescedLoad() async {
        if let coalescedTask {
            await coalescedTask.value
            return
        }
        let id = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.load()
        }
        coalescedTaskID = id
        coalescedTask = task
        await task.value
        if coalescedTaskID == id {
            coalescedTask = nil
            coalescedTaskID = nil
        }
    }

    func load() async {
        generation += 1
        let requestGeneration = generation
        activeTask?.cancel()
        state = .loading
        await io.begin(generation: requestGeneration)
        guard requestGeneration == generation, !Task.isCancelled else { return }

        guard let scheme = remoteURL.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            await useFallbackIfCold(generation: requestGeneration)
            return
        }

        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 12
        request.cachePolicy = .useProtocolCachePolicy
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let session = session
        let fetch = Task<(Data, URLResponse), Error> {
            let result = try await session.data(for: request)
            try Task.checkCancellation()
            return result
        }
        activeTask = fetch

        do {
            let (data, response) = try await withTaskCancellationHandler {
                try await fetch.value
            } onCancel: {
                fetch.cancel()
            }
            guard requestGeneration == generation, !Task.isCancelled else { return }
            guard Self.accepts(response: response, byteCount: data.count) else {
                await useFallbackIfCold(generation: requestGeneration)
                return
            }
            let decoded = await io.decode(data, generation: requestGeneration)
            guard requestGeneration == generation, !Task.isCancelled else { return }
            guard let decoded else {
                await useFallbackIfCold(generation: requestGeneration)
                return
            }
            bundle = decoded
            state = .ready
            remoteLoadSucceeded = true
            await io.writeAtomically(data, to: cacheURL, generation: requestGeneration)
            guard requestGeneration == generation, !Task.isCancelled else { return }
        } catch is CancellationError {
            guard requestGeneration == generation else { return }
            await useFallbackIfCold(generation: requestGeneration)
        } catch {
            guard requestGeneration == generation else { return }
            await useFallbackIfCold(generation: requestGeneration)
        }

        if requestGeneration == generation { activeTask = nil }
    }

    func content(for destination: String) -> TravelDestinationContent? {
        bundle?.content(forDestination: destination)
    }

    private func useFallbackIfCold(generation requestGeneration: Int) async {
        guard requestGeneration == generation, !Task.isCancelled else { return }
        guard bundle == nil else {
            state = .ready
            return
        }
        let cached = await io.readAndDecode(cacheURL, generation: requestGeneration)
        guard requestGeneration == generation, !Task.isCancelled else { return }
        if let decoded = cached {
            bundle = decoded
            state = .ready
            return
        }
        let embedded = await embeddedData()
        guard requestGeneration == generation, !Task.isCancelled else { return }
        if let embedded {
            let decoded = await io.decode(embedded, generation: requestGeneration)
            guard requestGeneration == generation, !Task.isCancelled else { return }
            if let decoded {
                bundle = decoded
                state = .ready
                return
            }
        }
        guard requestGeneration == generation, !Task.isCancelled else { return }
        state = .unavailable
    }

    nonisolated static func decodeValid(_ data: Data, now: Date = Date()) -> TravelContentBundle? {
        guard data.count <= travelContentMaximumResponseBytes,
              rawAdmits(data),
              let value = try? JSONDecoder().decode(TravelContentBundle.self, from: data),
              admits(value, now: now)
        else { return nil }
        return value
    }

    private nonisolated static func rawAdmits(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == ["version", "generatedAt", "destinations"],
              root["version"] as? Int == 1,
              let destinations = root["destinations"] as? [String: Any],
              Set(destinations.keys) == travelContentExpectedDestinationKeys
        else { return false }

        for key in travelContentExpectedDestinationKeys {
            guard let destination = destinations[key] as? [String: Any],
                  let policy = destination["policy"] as? [String: Any],
                  Set(policy.keys) == ["type", "maximumKm"],
                  policy["type"] as? String == "city",
                  policy["maximumKm"] as? Double == 25,
                  let camps = destination["camps"] as? [[String: Any]],
                  let attractions = destination["attractions"] as? [[String: Any]],
                  Set(camps.compactMap { $0["id"] as? String }) == travelContentExpectedCampIDs[key],
                  Set(attractions.compactMap { $0["id"] as? String }) == travelContentExpectedAttractionIDs[key],
                  camps.count == travelContentExpectedCampIDs[key]?.count,
                  attractions.count == travelContentExpectedAttractionIDs[key]?.count
            else { return false }

            for camp in camps {
                guard rawProvenanceAdmits(camp), rawMediaAdmits(camp["media"], isCamp: true)
                else { return false }
            }
            for attraction in attractions {
                guard rawProvenanceAdmits(attraction), rawMediaAdmits(attraction["media"], isCamp: false)
                else { return false }
            }
            guard rawCriticalRestrictionsAdmit(destinationKey: key, camps: camps) else { return false }
        }
        return true
    }

    private nonisolated static func rawProvenanceAdmits(_ item: [String: Any]) -> Bool {
        guard let source = item["source"] as? [String: Any],
              nonempty(source["name"] as? String),
              let sourceText = source["url"] as? String,
              let sourceURL = URL(string: sourceText), https(sourceURL)
        else { return false }
        return true
    }

    private nonisolated static func rawMediaAdmits(_ value: Any?, isCamp: Bool) -> Bool {
        guard let media = value as? [String: Any],
              nonempty(media["credit"] as? String),
              nonempty(media["license"] as? String),
              let mediaText = media["url"] as? String,
              safeMediaURL(mediaText),
              let source = media["source"] as? [String: Any],
              let sourceText = source["url"] as? String,
              let sourceURL = URL(string: sourceText), https(sourceURL)
        else { return false }
        if isCamp {
            guard media["role"] as? String == "nearbyDestination",
                  media["depictsCampground"] as? Bool == false,
                  let alt = media["alt"] as? String,
                  alt.localizedCaseInsensitiveContains("kamp alanını göstermez"),
                  let disclosure = media["disclosure"] as? String,
                  disclosure.localizedCaseInsensitiveContains("temsili"),
                  disclosure.localizedCaseInsensitiveContains("kamp alanını göstermez")
            else { return false }
        }
        return true
    }

    private nonisolated static func safeMediaURL(_ text: String) -> Bool {
        if let url = URL(string: text), https(url) { return true }
        guard text.hasPrefix("/assets/"),
              !text.contains("%"), !text.contains("\\"),
              !text.contains("?"), !text.contains("#"), !text.contains("//"),
              text.range(of: #"^/assets/[A-Za-z0-9._/-]+$"#, options: .regularExpression) != nil
        else { return false }
        return text.split(separator: "/", omittingEmptySubsequences: true)
            .allSatisfy { $0 != "." && $0 != ".." }
    }

    private nonisolated static func rawCriticalRestrictionsAdmit(
        destinationKey: String,
        camps: [[String: Any]]
    ) -> Bool {
        func camp(_ id: String) -> [String: Any]? {
            camps.first { $0["id"] as? String == id }
        }
        func contains(_ value: Any?, _ text: String) -> Bool {
            (value as? String)?.localizedCaseInsensitiveContains(text) == true
        }

        switch destinationKey {
        case "warsaw":
            guard let wok = camp("camping-motel-wok"),
                  wok["maximumLengthMeters"] as? Double == 8,
                  contains(wok["warning"], "8 metreden uzun"),
                  contains(wok["warning"], "kabul etmiyor")
            else { return false }
        case "riga":
            guard let yachts = camp("camping-yachts"),
                  yachts["maximumLengthMeters"] as? Double == 7.5,
                  contains(yachts["warning"], "7,5 metreden uzun"),
                  contains(yachts["warning"], "önceden teyit"),
                  let city = camp("riga-city-camping"),
                  contains(city["openingPeriod"], "15 Mayıs-15 Eylül"),
                  contains(city["warning"], "15 Eylül"),
                  contains(city["warning"], "kapalı")
            else { return false }
        case "budapest":
            guard let aveNatura = camp("ave-natura-camping"),
                  aveNatura["maximumLengthMeters"] as? Double == 6,
                  contains(aveNatura["warning"], "6 metre"),
                  contains(aveNatura["warning"], "keskin viraj")
            else { return false }
        case "krakow":
            guard let clepardia = camp("camping-clepardia"),
                  contains(clepardia["openingPeriod"], "09:00-21:00"),
                  contains(clepardia["reservationMethod"], "Haziran-ağustos"),
                  contains(clepardia["reservationMethod"], "sınırlı olabilir"),
                  contains(clepardia["warning"], "21:00"),
                  contains(clepardia["warning"], "iletişim")
            else { return false }
        case "novi-sad":
            guard let farma = camp("auto-camp-farma-47"),
                  farma["supportsCaravan"] as? Bool == false,
                  let location = farma["location"] as? [String: Any],
                  location["latitude"] as? Double == 45.3886068,
                  location["longitude"] as? Double == 19.8197356,
                  farma["hasWater"] is NSNull,
                  farma["hasWastewaterDisposal"] is NSNull,
                  contains(farma["warning"], "yalnız motorhome"),
                  contains(farma["warning"], "olumlu varsayma")
            else { return false }
        default:
            break
        }
        return true
    }

    private nonisolated static func accepts(response: URLResponse, byteCount: Int) -> Bool {
        guard let http = response as? HTTPURLResponse,
              (200 ... 299).contains(http.statusCode),
              http.expectedContentLength <= 0 || http.expectedContentLength <= travelContentMaximumResponseBytes,
              byteCount <= travelContentMaximumResponseBytes,
              let contentType = http.value(forHTTPHeaderField: "Content-Type")?
                .split(separator: ";", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        else { return false }
        return contentType == "application/json" || contentType.hasSuffix("+json")
    }

    private nonisolated static func admits(_ value: TravelContentBundle, now: Date) -> Bool {
        let earliestSensibleDate = Date(timeIntervalSince1970: 1_577_836_800) // 2020-01-01
        let latestSensibleDate = now.addingTimeInterval(24 * 60 * 60)
        guard value.version == 1,
              value.generatedAt >= earliestSensibleDate,
              value.generatedAt <= latestSensibleDate,
              Set(value.destinations.keys) == travelContentExpectedDestinationKeys
        else { return false }

        for (key, destination) in value.destinations {
            guard nonempty(destination.cityName),
                  let center = destination.cityCenter,
                  valid(center),
                  destination.camps.count >= 2,
                  destination.attractions.count >= 3,
                  uniqueIDs(destination.camps.map(\.id)),
                  uniqueIDs(destination.attractions.map(\.id))
            else { return false }

            guard case .city(let maximumKm) = destination.policy,
                  maximumKm.isFinite, maximumKm > 0, maximumKm <= 25
            else { return false }

            for camp in destination.camps {
                guard valid(camp.location),
                      center.distanceKm(to: camp.location) <= maximumKm,
                      nonempty(camp.id), nonempty(camp.name), nonempty(camp.address),
                      nonempty(camp.recommendation),
                      https(camp.websiteURL),
                      nonempty(camp.source.name), https(camp.source.url),
                      valid(camp.media),
                      sensible(camp.verifiedAt, earliest: earliestSensibleDate, latest: latestSensibleDate),
                      camp.maximumLengthMeters.map({ $0.isFinite && $0 > 0 && $0 <= 30 }) ?? true
                else { return false }

                if camp.media.depictsCampground == false {
                    guard camp.media.role == "nearbyDestination",
                          nonempty(camp.media.disclosure)
                    else { return false }
                }
            }

            for attraction in destination.attractions {
                guard valid(attraction.location),
                      center.distanceKm(to: attraction.location) <= 25,
                      nonempty(attraction.id), nonempty(attraction.name), nonempty(attraction.address),
                      nonempty(attraction.category), nonempty(attraction.recommendation),
                      attraction.visitDurationMinutes > 0,
                      nonempty(attraction.source.name), https(attraction.source.url),
                      valid(attraction.media),
                      sensible(attraction.verifiedAt, earliest: earliestSensibleDate, latest: latestSensibleDate)
                else { return false }
            }

            if key == "warsaw" {
                guard let wok = destination.camps.first(where: { $0.id == "camping-motel-wok" }),
                      wok.maximumLengthMeters == 8,
                      wok.warning?.contains("8") == true
                else { return false }
            }
            if key == "riga" {
                guard let yachts = destination.camps.first(where: { $0.id == "camping-yachts" }),
                      yachts.maximumLengthMeters == 7.5,
                      yachts.warning?.contains("7,5") == true
                else { return false }
            }
        }
        return true
    }

    private nonisolated static func valid(_ point: GeoPoint) -> Bool {
        point.latitude.isFinite && point.longitude.isFinite
            && abs(point.latitude) <= 90 && abs(point.longitude) <= 180
    }

    private nonisolated static func valid(_ media: TravelMedia) -> Bool {
        let localAsset = media.url.scheme == nil && media.url.relativeString.hasPrefix("/assets/")
        return (https(media.url) || localAsset)
            && nonempty(media.credit)
            && nonempty(media.license)
            && media.source.map { https($0.url) } == true
    }

    private nonisolated static func sensible(_ date: Date, earliest: Date, latest: Date) -> Bool {
        date >= earliest && date <= latest
    }

    private nonisolated static func uniqueIDs(_ ids: [String]) -> Bool {
        Set(ids).count == ids.count
    }

    private nonisolated static func nonempty(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private nonisolated static func https(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
    }

    nonisolated static func defaultCacheURL(fileManager: FileManager = .default) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return root
            .appendingPathComponent("Kuzey", isDirectory: true)
            .appendingPathComponent("TravelContent", isDirectory: true)
            .appendingPathComponent("travel-content.json", isDirectory: false)
    }

}
