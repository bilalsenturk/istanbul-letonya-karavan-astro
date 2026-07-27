import Combine
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
    private var generation = 0
    private var activeTask: Task<Data, Error>?
    private var didRequestInitialLoad = false

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
        guard !didRequestInitialLoad else { return }
        didRequestInitialLoad = true
        await load()
    }

    func load() async {
        generation += 1
        let requestGeneration = generation
        activeTask?.cancel()
        state = .loading

        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 12
        request.cachePolicy = .useProtocolCachePolicy
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let session = session
        let fetch = Task<Data, Error> {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            if let http = response as? HTTPURLResponse,
               !(200 ... 299).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            return data
        }
        activeTask = fetch

        do {
            let data = try await withTaskCancellationHandler {
                try await fetch.value
            } onCancel: {
                fetch.cancel()
            }
            guard requestGeneration == generation, !Task.isCancelled,
                  let decoded = Self.decodeValid(data) else {
                if requestGeneration == generation { await useFallbackIfCold() }
                return
            }
            bundle = decoded
            state = .ready
            writeCache(data)
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
        if let cached = try? Data(contentsOf: cacheURL),
           let decoded = Self.decodeValid(cached) {
            bundle = decoded
            state = .ready
            return
        }
        if let embedded = embeddedData(),
           let decoded = Self.decodeValid(embedded) {
            bundle = decoded
            state = .ready
            return
        }
        state = .unavailable
    }

    private func writeCache(_ data: Data) {
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // Disk persistence is best-effort; the already validated in-memory bundle remains usable.
        }
    }

    private static func decodeValid(_ data: Data) -> TravelContentBundle? {
        guard let value = try? JSONDecoder().decode(TravelContentBundle.self, from: data),
              value.version > 0,
              !value.destinations.isEmpty,
              value.destinations.values.allSatisfy({ !$0.cityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { return nil }
        return value
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
