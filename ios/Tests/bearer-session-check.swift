import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ✓ \(message)")
    } else {
        fputs("  ✗ \(message)\n", stderr)
        exit(1)
    }
}

private enum MockMode {
    case rotate
    case retryUnauthorized
    case refreshUnauthorized
    case offline
}

private final class MockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var mode = MockMode.rotate
    private static var refreshes = 0
    private static var protectedAttempts = 0

    static var refreshCount: Int { lock.withLock { refreshes } }
    static var protectedRequestCount: Int { lock.withLock { protectedAttempts } }

    static func configure(_ nextMode: MockMode) {
        lock.withLock {
            mode = nextMode
            refreshes = 0
            protectedAttempts = 0
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url?.path ?? ""
        let authorization = request.value(forHTTPHeaderField: "Authorization")
        let state = Self.lock.withLock { () -> (MockMode, Int) in
            if path.hasSuffix("/auth/refresh") { Self.refreshes += 1 }
            if !path.hasSuffix("/auth/refresh") { Self.protectedAttempts += 1 }
            return (Self.mode, Self.protectedAttempts)
        }

        if path.hasSuffix("/auth/refresh") {
            switch state.0 {
            case .rotate, .retryUnauthorized:
                respond(status: 200, body: Data(#"{"accessToken":"new-access","refreshToken":"new-refresh"}"#.utf8))
            case .refreshUnauthorized:
                respond(status: 401)
            case .offline:
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            }
            return
        }

        switch state.0 {
        case .rotate:
            respond(status: authorization == "Bearer new-access" ? 200 : 401)
        case .retryUnauthorized:
            respond(status: 401)
        case .refreshUnauthorized, .offline:
            respond(status: 401)
        }
    }

    override func stopLoading() {}

    private func respond(status: Int, body: Data = Data()) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@main
struct BearerSessionCheck {
    @MainActor
    static func main() async throws {
        let store = KeychainTokenStore(
            service: "com.bilalsenturk.kuzey.bearer-session-check",
            account: UUID().uuidString
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let coordinator = BearerSessionCoordinator(session: URLSession(configuration: configuration), tokenStore: store)

        print("\n=== Bearer oturumu ===")
        MockURLProtocol.configure(.rotate)
        try coordinator.install(AccountTokens(accessToken: "old-access", refreshToken: "old-refresh"))
        async let a = coordinator.data(path: "me", method: "GET", body: nil)
        async let b = coordinator.data(path: "trips/kuzey-2026/live-location", method: "PUT", body: Data("{}".utf8))
        _ = try await (a, b)
        expect(MockURLProtocol.refreshCount == 1, "eşzamanlı 401 tek refresh kullanır")
        expect(MockURLProtocol.protectedRequestCount == 4, "iki istek yalnızca bir kez yeniden denenir")
        expect(store.load() == AccountTokens(accessToken: "new-access", refreshToken: "new-refresh"), "dönen token çifti Keychain'e saklanır")

        var revocations = 0
        coordinator.onRevoked = { revocations += 1 }
        MockURLProtocol.configure(.retryUnauthorized)
        try coordinator.install(AccountTokens(accessToken: "expired-access", refreshToken: "expired-refresh"))
        do {
            _ = try await coordinator.data(path: "me", method: "GET", body: nil)
            expect(false, "yeniden denenen 401 hata döndürür")
        } catch {
            expect(MockURLProtocol.refreshCount == 1, "yeniden deneme öncesi token yenilenir")
            expect(MockURLProtocol.protectedRequestCount == 2, "401 sonrası yalnız bir yeniden deneme yapılır")
            expect(!coordinator.hasSession && store.load() == nil, "yeniden deneme 401'i oturumu siler")
            expect(revocations == 1, "yeniden deneme 401'i iptal bildirimi yapar")
        }

        MockURLProtocol.configure(.refreshUnauthorized)
        try coordinator.install(AccountTokens(accessToken: "expired-access", refreshToken: "expired-refresh"))
        do {
            _ = try await coordinator.data(path: "me", method: "GET", body: nil)
            expect(false, "refresh 401 hata döndürür")
        } catch {
            expect(!coordinator.hasSession && store.load() == nil, "refresh 401'i oturumu siler")
            expect(revocations == 2, "refresh 401'i iptal bildirimi yapar")
        }

        let offlineTokens = AccountTokens(accessToken: "offline-access", refreshToken: "offline-refresh")
        MockURLProtocol.configure(.offline)
        try coordinator.install(offlineTokens)
        do {
            _ = try await coordinator.data(path: "me", method: "GET", body: nil)
            expect(false, "çevrimdışı refresh hata döndürür")
        } catch {
            expect(coordinator.hasSession && store.load() == offlineTokens, "çevrimdışı refresh tokenları korur")
            expect(revocations == 2, "çevrimdışı refresh oturum iptali bildirmez")
        }

        coordinator.clear()
        print("\n✅ BEARER OTURUM KONTROLLERİ GEÇTİ")
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
