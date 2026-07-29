import Foundation

@MainActor
protocol AuthenticatedRequestSending: AnyObject {
    var hasSession: Bool { get }
    func data(path: String, method: String, body: Data?) async throws -> (Data, HTTPURLResponse)
}

@MainActor
final class BearerSessionCoordinator: AuthenticatedRequestSending {
    static let shared = BearerSessionCoordinator()

    var onRevoked: (() -> Void)?

    private let session: URLSession
    private let tokenStore: AccountTokenStoring
    private var tokens: AccountTokens?
    private var refreshTask: Task<AccountTokens, Error>?

    init(session: URLSession = .shared, tokenStore: AccountTokenStoring = KeychainTokenStore()) {
        self.session = session
        self.tokenStore = tokenStore
    }

    var hasSession: Bool { tokens != nil }

    func install(_ tokens: AccountTokens) throws {
        try tokenStore.save(tokens)
        self.tokens = tokens
    }

    @discardableResult
    func restore() -> Bool {
        tokens = tokenStore.load()
        return tokens != nil
    }

    func clear() {
        refreshTask?.cancel()
        refreshTask = nil
        tokens = nil
        tokenStore.clear()
    }

    func data(path: String, method: String, body: Data?) async throws -> (Data, HTTPURLResponse) {
        guard let rejectedTokens = tokens else { throw URLError(.userAuthenticationRequired) }

        let initial = try await send(path: path, method: method, body: body, accessToken: rejectedTokens.accessToken)
        guard initial.1.statusCode == 401 else { return initial }

        let currentTokens = try await refreshedTokens(afterRejecting: rejectedTokens.accessToken)
        let retried = try await send(path: path, method: method, body: body, accessToken: currentTokens.accessToken)
        if retried.1.statusCode == 401 {
            revoke()
            throw BearerSessionError.unauthorized
        }
        return retried
    }

    private func refreshedTokens(afterRejecting rejectedAccessToken: String) async throws -> AccountTokens {
        guard let currentTokens = tokens else { throw URLError(.userAuthenticationRequired) }
        if currentTokens.accessToken != rejectedAccessToken { return currentTokens }

        if let refreshTask { return try await refreshTask.value }

        let refreshToken = currentTokens.refreshToken
        let task = Task { [weak self, session] () throws -> AccountTokens in
            do {
                let rotatedTokens = try await Self.refresh(using: session, refreshToken: refreshToken)
                guard let self else { return rotatedTokens }
                guard self.tokens?.refreshToken == refreshToken else { throw CancellationError() }
                try self.tokenStore.save(rotatedTokens)
                self.tokens = rotatedTokens
                return rotatedTokens
            } catch BearerSessionError.unauthorized {
                self?.revoke()
                throw BearerSessionError.unauthorized
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func send(
        path: String,
        method: String,
        body: Data?,
        accessToken: String
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = Config.accountAPIBaseURL?.appendingPathComponent(path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, httpResponse)
    }

    private static func refresh(using session: URLSession, refreshToken: String) async throws -> AccountTokens {
        guard let url = Config.accountAPIBaseURL?.appendingPathComponent("auth/refresh") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RefreshRequest(refreshToken: refreshToken))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 { throw BearerSessionError.unauthorized }
            throw BearerSessionError.refreshFailed(status: httpResponse.statusCode)
        }
        return try JSONDecoder().decode(AccountTokens.self, from: data)
    }

    private func revoke() {
        guard tokens != nil else { return }
        clear()
        onRevoked?()
    }
}

private struct RefreshRequest: Encodable {
    let refreshToken: String
}

private enum BearerSessionError: Error {
    case unauthorized
    case refreshFailed(status: Int)
}
