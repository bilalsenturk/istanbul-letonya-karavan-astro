import Foundation

private enum CheckResult {
    static var failureCount = 0
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ✓ \(message)")
    } else {
        fputs("  ✗ \(message)\n", stderr)
        CheckResult.failureCount += 1
    }
}

private enum MockMode {
    case rotate
    case retryUnauthorized
    case refreshUnauthorized
    case offline
    case scripted
}

private final class MockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var mode = MockMode.rotate
    private static var refreshes = 0
    private static var protectedAttempts = 0
    private static var pending: [MockURLProtocol] = []
    private static var received: [URLRequest] = []

    static var refreshCount: Int { lock.withLock { refreshes } }
    static var protectedRequestCount: Int { lock.withLock { protectedAttempts } }

    static func configure(_ nextMode: MockMode) {
        lock.withLock {
            mode = nextMode
            refreshes = 0
            protectedAttempts = 0
            pending = []
            received = []
        }
    }

    static func hasPending(where predicate: (URLRequest) -> Bool) -> Bool {
        lock.withLock { pending.contains(where: { predicate($0.request) }) }
    }

    @discardableResult
    static func respondNext(
        where predicate: (URLRequest) -> Bool,
        status: Int,
        body: Data = Data()
    ) -> Bool {
        let protocolInstance = lock.withLock { () -> MockURLProtocol? in
            guard let index = pending.firstIndex(where: { predicate($0.request) }) else { return nil }
            return pending.remove(at: index)
        }
        guard let protocolInstance else { return false }
        protocolInstance.respond(status: status, body: body)
        return true
    }

    static func receivedCount(where predicate: (URLRequest) -> Bool) -> Int {
        lock.withLock { received.filter(predicate).count }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url?.path ?? ""
        let authorization = request.value(forHTTPHeaderField: "Authorization")
        let state = Self.lock.withLock { () -> (MockMode, Int) in
            Self.received.append(request)
            if path.hasSuffix("/auth/refresh") { Self.refreshes += 1 }
            if !path.hasSuffix("/auth/refresh") { Self.protectedAttempts += 1 }
            return (Self.mode, Self.protectedAttempts)
        }

        if case .scripted = state.0 {
            Self.lock.withLock { Self.pending.append(self) }
            return
        }

        if path.hasSuffix("/auth/refresh") {
            switch state.0 {
            case .rotate, .retryUnauthorized:
                respond(status: 200, body: Data(#"{"accessToken":"new-access","refreshToken":"new-refresh","sessionId":"new-session","accessExpiresAt":"2026-07-29T12:15:00.000Z"}"#.utf8))
            case .refreshUnauthorized:
                respond(status: 401)
            case .offline:
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            case .scripted:
                break
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
        case .scripted:
            break
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
        let accountAPIURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../Karavan/Accounts/AccountAPI.swift")
            .standardized
        let accountAPISource = try String(contentsOf: accountAPIURL, encoding: .utf8)
        let protectedOperations = [
            "func me(", "func updateTravelProfile(", "func logout(", "func createTrip(",
            "func invite(", "func updateStop(", "func addStop(", "func updateTrip(",
            "func replaceStops("
        ]
        let protectedDeclarationsCarryTokens = protectedOperations.contains { operation in
            guard let start = accountAPISource.range(of: operation)?.lowerBound else { return true }
            let declaration = accountAPISource[start...].split(separator: "{", maxSplits: 1).first ?? ""
            return declaration.contains("accessToken:")
        }
        expect(!protectedDeclarationsCarryTokens, "korumalı AccountAPI işlemleri token parametresi istemez")

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

        print("\n=== Eski isteklerin yeni oturuma etkisi ===")
        MockURLProtocol.configure(.scripted)
        let sessionA = AccountTokens(accessToken: "a-access", refreshToken: "a-refresh")
        let sessionB = AccountTokens(accessToken: "b-access", refreshToken: "b-refresh")
        try coordinator.install(sessionA)
        let staleRetry = Task {
            try await coordinator.data(path: "stale-retry", method: "GET", body: nil)
        }
        await waitForPending("A ilk isteği", matching: protectedRequest(token: "a-access"))
        expect(MockURLProtocol.respondNext(where: protectedRequest(token: "a-access"), status: 401), "A ilk 401'i teslim edilir")
        await waitForPending("A refresh isteği", matching: refreshRequest)
        expect(MockURLProtocol.respondNext(
            where: refreshRequest,
            status: 200,
            body: refreshResponse(access: "a-rotated", refresh: "a-refresh-rotated", session: "a-session")
        ), "A token rotasyonu teslim edilir")
        await waitForPending("A yeniden denemesi", matching: protectedRequest(token: "a-rotated"))
        let revocationsBeforeStaleRetry = revocations
        try coordinator.install(sessionB)
        expect(MockURLProtocol.respondNext(where: protectedRequest(token: "a-rotated"), status: 401), "A eski yeniden deneme 401'i teslim edilir")
        _ = await staleRetry.result
        expect(coordinator.hasSession && store.load() == sessionB, "eski yeniden deneme 401'i B oturumunu korur")
        expect(revocations == revocationsBeforeStaleRetry, "eski yeniden deneme 401'i iptal bildirimi yapmaz")

        MockURLProtocol.configure(.scripted)
        try coordinator.install(sessionA)
        let staleRefresh = Task {
            try await coordinator.data(path: "stale-refresh", method: "GET", body: nil)
        }
        await waitForPending("A ilk isteği", matching: protectedRequest(token: "a-access"))
        expect(MockURLProtocol.respondNext(where: protectedRequest(token: "a-access"), status: 401), "A refresh öncesi 401'i teslim edilir")
        await waitForPending("A bekleyen refresh isteği", matching: refreshRequest)
        let revocationsBeforeStaleRefresh = revocations
        try coordinator.install(sessionB)
        expect(MockURLProtocol.respondNext(where: refreshRequest, status: 401), "A eski refresh 401'i teslim edilir")
        _ = await staleRefresh.result
        expect(coordinator.hasSession && store.load() == sessionB, "eski refresh 401'i B oturumunu korur")
        expect(revocations == revocationsBeforeStaleRefresh, "eski refresh 401'i iptal bildirimi yapmaz")

        print("\n=== Refresh uçuş sahipliği ===")
        MockURLProtocol.configure(.scripted)
        try coordinator.install(sessionA)
        let oldFlight = Task {
            try await coordinator.data(path: "old-flight", method: "GET", body: nil)
        }
        await waitForPending("A uçuşu ilk isteği", matching: protectedRequest(token: "a-access"))
        expect(MockURLProtocol.respondNext(where: protectedRequest(token: "a-access"), status: 401), "A uçuşu refresh'e yönelir")
        await waitForPending("A uçuşu refresh isteği", matching: refreshRequest)

        try coordinator.install(sessionB)
        let firstB = Task {
            try await coordinator.data(path: "first-b", method: "GET", body: nil)
        }
        await waitForPending("B ilk isteği", matching: protectedRequest(token: "b-access"))
        expect(MockURLProtocol.respondNext(where: protectedRequest(token: "b-access"), status: 401), "B ilk isteği refresh'e yönelir")
        await waitForPendingCount(2, description: "B refresh uçuşu", matching: refreshRequest)

        expect(MockURLProtocol.respondNext(
            where: refreshRequest,
            status: 200,
            body: refreshResponse(access: "a-too-late", refresh: "a-too-late-refresh", session: "a-late-session")
        ), "A eski uçuşu B uçuşundan sonra tamamlanır")
        _ = await oldFlight.result

        let secondB = Task {
            try await coordinator.data(path: "second-b", method: "GET", body: nil)
        }
        await waitForPending("B geç çağrısı", matching: protectedRequest(token: "b-access"))
        expect(MockURLProtocol.respondNext(where: protectedRequest(token: "b-access"), status: 401), "B geç çağrısı bekleyen refresh'e yönelir")
        await Task.yield()
        await Task.yield()
        expect(MockURLProtocol.receivedCount(where: refreshRequest) == 2, "A temizliği B refresh sahipliğini silemez")

        expect(MockURLProtocol.respondNext(
            where: refreshRequest,
            status: 200,
            body: refreshResponse(access: "b-rotated", refresh: "b-refresh-rotated", session: "b-session")
        ), "B refresh uçuşu tamamlanır")
        await waitForPending("B ilk yeniden denemesi", matching: protectedRequest(token: "b-rotated"))
        await waitForPendingCount(2, description: "iki B yeniden denemesi", matching: protectedRequest(token: "b-rotated"))
        expect(MockURLProtocol.respondNext(where: protectedRequest(token: "b-rotated"), status: 200), "B ilk yeniden denemesi başarılıdır")
        expect(MockURLProtocol.respondNext(where: protectedRequest(token: "b-rotated"), status: 200), "B ikinci yeniden denemesi başarılıdır")
        _ = await firstB.result
        _ = await secondB.result
        expect(store.load() == AccountTokens(accessToken: "b-rotated", refreshToken: "b-refresh-rotated"), "B uçuşunun tokenları saklanır")

        coordinator.clear()
        guard CheckResult.failureCount == 0 else {
            fputs("\n❌ \(CheckResult.failureCount) BEARER OTURUM KONTROLÜ BAŞARISIZ\n", stderr)
            exit(1)
        }
        print("\n✅ BEARER OTURUM KONTROLLERİ GEÇTİ")
    }
}

private func protectedRequest(token: String) -> (URLRequest) -> Bool {
    { request in
        !(request.url?.path.hasSuffix("/auth/refresh") ?? false)
            && request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)"
    }
}

private func refreshRequest(_ request: URLRequest) -> Bool {
    request.url?.path.hasSuffix("/auth/refresh") == true
}

private func refreshResponse(access: String, refresh: String, session: String) -> Data {
    Data("""
    {"accessToken":"\(access)","refreshToken":"\(refresh)","sessionId":"\(session)","accessExpiresAt":"2026-07-29T12:15:00.000Z"}
    """.utf8)
}

private func waitForPending(
    _ description: String,
    matching predicate: @escaping (URLRequest) -> Bool
) async {
    await waitForPendingCount(1, description: description, matching: predicate)
}

private func waitForPendingCount(
    _ expectedCount: Int,
    description: String,
    matching predicate: @escaping (URLRequest) -> Bool
) async {
    for _ in 0..<2_000 {
        let count = MockURLProtocol.receivedCount(where: predicate)
        if count >= expectedCount && MockURLProtocol.hasPending(where: predicate) { return }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    expect(false, "\(description) zamanında ulaşır")
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
