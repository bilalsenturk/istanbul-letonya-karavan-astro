import Foundation

@MainActor
final class TripStore: ObservableObject {
    @Published var trip: TripData?
    @Published var lastRefreshed: Date?

    // Deploy edilen sitedeki güncel veri. Site her deploy olduğunda app içeriği
    // de tazelenir — app'i yeniden kurmak gerekmez. (Adres: Config.swift)
    static let remoteDataURL = Config.tripDataURL

    init() {
        loadBundled()
        Task { await refreshFromRemote() }
    }

    private func loadBundled() {
        guard let url = Bundle.main.url(forResource: "trip", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(TripData.self, from: data)
        else { return }
        trip = decoded
    }

    func refreshFromRemote() async {
        guard let url = Self.remoteDataURL else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(TripData.self, from: data)
        else { return }
        trip = decoded
        lastRefreshed = Date()
    }
}
