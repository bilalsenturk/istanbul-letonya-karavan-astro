import Foundation
import UIKit

// TestFlight'tan dağıtılan uygulama kendi kendini GÜNCELLEYEMEZ — iOS buna izin
// vermez. Yapılabilen tek şey: sitedeki /kuzey-version.json manifest'inden güncel
// build numarasını öğrenip kullanıcıyı bilgilendirmek ve TestFlight sayfasına
// yönlendirmek. Asıl kurulum her cihazda TestFlight'ın "Otomatik Güncelleme"
// ayarıyla olur (bak. ios/README.md → Sürüm yayınlama).
@MainActor
final class UpdateChecker: NSObject, ObservableObject {
    static let shared = UpdateChecker()

    enum State: Equatable {
        /// Henüz kontrol edilmedi veya erişilemedi (sessiz — çevrimdışı da buraya düşer)
        case unknown
        /// Kurulu build güncel
        case upToDate
        /// Yeni build var — banner gösterilebilir ("Sonra" ile geçiştirilebilir)
        case updateAvailable(latest: Int)
        /// Kurulu build minimumun altında — banner kapatılamaz
        case updateRequired(min: Int, latest: Int)
    }

    @Published private(set) var state: State = .unknown

    /// Manifest'ten okunan TestFlight katılım linki (banner düğmesi bunu açar).
    @Published private(set) var testflightURL: URL?

    /// "Sonra" denen build — o numara için banner bir daha gösterilmez.
    @Published private(set) var snoozedBuild: Int {
        didSet { UserDefaults.standard.set(snoozedBuild, forKey: Self.snoozedKey) }
    }

    private static let lastCheckKey = "updatecheck-last"
    private static let snoozedKey = "updatecheck-snoozed-build"

    /// Tekrar kontroller arası asgari süre (site her öne gelişte yorulmasın).
    private let minInterval: TimeInterval = 6 * 3600

    private var lastCheck: Date? {
        let t = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// Banner gösterilsin mi? (zorunluysa her zaman, değilse "Sonra" denmemişse)
    var shouldShowBanner: Bool {
        switch state {
        case .updateRequired: return true
        case .updateAvailable(let latest): return latest != snoozedBuild
        case .unknown, .upToDate: return false
        }
    }

    /// Zorunlu güncelleme mi? (kurulu build minimumun altında)
    var isRequired: Bool {
        if case .updateRequired = state { return true }
        return false
    }

    /// Güncel build numarası (banner metni için)
    var latestBuild: Int? {
        switch state {
        case .updateAvailable(let latest), .updateRequired(_, let latest): return latest
        case .unknown, .upToDate: return nil
        }
    }

    private override init() {
        snoozedBuild = UserDefaults.standard.integer(forKey: Self.snoozedKey)
        super.init()
        // KaravanApp'e dokunmadan ön plan kontrolü: DashboardView .task'ten
        // checkIfNeeded() çağrılır; burada da uygulama öne dönünce kendini tetikler.
        NotificationCenter.default.addObserver(
            self, selector: #selector(onForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil
        )
    }

    @objc private nonisolated func onForeground() {
        Task { @MainActor in await self.checkIfNeeded() }
    }

    /// Açılışta + öne gelince çağrılır; asgari aralık dolmadıysa atlar.
    func checkIfNeeded() async {
        if let last = lastCheck, Date().timeIntervalSince(last) < minInterval { return }

        guard var comps = Config.versionManifestURL
            .flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        else { return }
        // Vercel CDN önbelleğini kır
        comps.queryItems = [URLQueryItem(name: "t", value: "\(Int(Date().timeIntervalSince1970))")]
        guard let url = comps.url else { return }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        struct Manifest: Decodable { let latestBuild: Int; let minBuild: Int; let testflightURL: String }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return }  // çevrimdışı / bozuk manifest → sessiz geç

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
        testflightURL = URL(string: manifest.testflightURL)

        let current = Self.currentBuild
        if current < manifest.minBuild {
            state = .updateRequired(min: manifest.minBuild, latest: manifest.latestBuild)
        } else if manifest.latestBuild > current {
            state = .updateAvailable(latest: manifest.latestBuild)
        } else {
            state = .upToDate
        }
    }

    /// "Sonra": bu build için banner'ı gizle (daha yeni build çıkınca tekrar görünür).
    func snoozeLatest() {
        if case .updateAvailable(let latest) = state { snoozedBuild = latest }
    }

    /// Kurulu build numarası (CFBundleVersion).
    static var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }
}
