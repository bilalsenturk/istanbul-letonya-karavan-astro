import Foundation
import UIKit

@MainActor
final class TripStore: ObservableObject {
    @Published var trip: TripData?
    @Published var lastRefreshed: Date?

    // Deploy edilen sitedeki güncel veri. Site her deploy olduğunda app içeriği
    // de tazelenir — app'i yeniden kurmak gerekmez. (Adres: Config.swift)
    static let remoteDataURL = Config.tripDataURL

    /// Öne gelişte yeniden çekim için son DENEME zamanı (throttle).
    private var lastRefreshAttempt: Date = .distantPast

    init() {
        loadBundled()
        lastRefreshAttempt = Date()
        Task { await refreshFromRemote() }
        // App öne gelince uzak veriyi tazele (willEnterForeground açılışta
        // tetiklenmez; sık öne gelişlerde 60 sn sınırı).
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      Date().timeIntervalSince(self.lastRefreshAttempt) > 60
                else { return }
                self.lastRefreshAttempt = Date()
                await self.refreshFromRemote()
            }
        }
    }

    /// Gömülü gezi verisi (çevrimdışı yedek + arka plan görevleri için).
    static func bundledTrip() -> TripData? {
        guard let url = Bundle.main.url(forResource: "trip", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(TripData.self, from: data)
        else { return nil }
        return decoded
    }

    private func loadBundled() {
        trip = Self.bundledTrip()
        writeSnapshot()
    }

    /// Kullanıcı düzenlemeleri kalkışı değiştirebildiği için snapshot dışarıdan beslenir.
    /// Closure açılışta snapshot'tan SONRA kurulur; kurulunca widget verisini tazele.
    var effectiveDeparture: (() -> Date?)? {
        didSet { writeSnapshot() }
    }

    /// Widget'ların ihtiyacı olan sabitleri App Group'a yaz.
    func writeSnapshot() {
        guard let trip else { return }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let departure = effectiveDeparture?() ?? trip.departureDate
        var values: [String: Any] = [
            SharedSnapshot.Key.departureAt: departure.map { iso.string(from: $0) } ?? trip.departureAt
        ]
        if let max = trip.totalBudget.max {
            values[SharedSnapshot.Key.budgetMax] = Double(max)
        } else {
            // Yeni snapshot'ta olmayan anahtar App Group'ta kalıp bayat
            // değer göstermesin (SharedSnapshot.write yalnızca yazar, silmez).
            SharedSnapshot.defaults?.removeObject(forKey: SharedSnapshot.Key.budgetMax)
        }
        SharedSnapshot.write(values)
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
        writeSnapshot()
    }
}
