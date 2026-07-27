import Combine
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let travelContentMaximumResponseBytes = 2 * 1_024 * 1_024
private let travelContentExpectedDestinationKeys: Set<String> = [
    "sofia", "novi-sad", "budapest", "krakow", "warsaw", "riga"
]

private actor TravelContentIO {
    func decode(_ data: Data, now: Date = Date()) -> TravelContentBundle? {
        TravelContentStore.decodeValid(data, now: now)
    }

    func readAndDecode(_ url: URL, now: Date = Date()) -> TravelContentBundle? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return TravelContentStore.decodeValid(data, now: now)
    }

    func writeAtomically(_ data: Data, to url: URL) {
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
}

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
    private let embeddedData: () -> Data?
    private let io = TravelContentIO()
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
        embeddedData: @escaping () -> Data? = TravelContentStore.mainBundleData
    ) {
        self.remoteURL = remoteURL
        self.session = session
        self.cacheURL = cacheURL
        self.embeddedData = embeddedData
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

        guard let scheme = remoteURL.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            await useFallbackIfCold()
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
            guard requestGeneration == generation, !Task.isCancelled,
                  Self.accepts(response: response, byteCount: data.count),
                  let decoded = await io.decode(data)
            else {
                if requestGeneration == generation { await useFallbackIfCold() }
                return
            }
            bundle = decoded
            state = .ready
            remoteLoadSucceeded = true
            await io.writeAtomically(data, to: cacheURL)
        } catch is CancellationError {
            guard requestGeneration == generation else { return }
            await useFallbackIfCold()
        } catch {
            guard requestGeneration == generation else { return }
            await useFallbackIfCold()
        }

        if requestGeneration == generation { activeTask = nil }
    }

    func content(for destination: String) -> TravelDestinationContent? {
        bundle?.content(forDestination: destination)
    }

    private func useFallbackIfCold() async {
        guard bundle == nil else {
            state = .ready
            return
        }
        if let decoded = await io.readAndDecode(cacheURL) {
            bundle = decoded
            state = .ready
            return
        }
        if let embedded = embeddedData(),
           let decoded = await io.decode(embedded) {
            bundle = decoded
            state = .ready
            return
        }
        state = .unavailable
    }

    nonisolated static func decodeValid(_ data: Data, now: Date = Date()) -> TravelContentBundle? {
        guard data.count <= travelContentMaximumResponseBytes,
              let value = try? JSONDecoder().decode(TravelContentBundle.self, from: data),
              admits(value, now: now)
        else { return nil }
        return value
    }

    private nonisolated static func accepts(response: URLResponse, byteCount: Int) -> Bool {
        guard let http = response as? HTTPURLResponse,
              (200 ... 299).contains(http.statusCode),
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
        guard value.version > 0,
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

    nonisolated static func mainBundleData() -> Data? {
        guard let url = Bundle.main.url(forResource: "travel-content", withExtension: "json") else { return nil }
        return try? Data(contentsOf: url)
    }
}
