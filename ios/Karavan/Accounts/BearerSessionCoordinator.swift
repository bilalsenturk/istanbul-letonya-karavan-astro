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
    private var sessionGeneration: UInt64 = 0
    private var refreshTask: Task<AccountTokens, Error>?
    private var refreshTaskID: UInt64?
    private var refreshTaskGeneration: UInt64?
    private var nextRefreshTaskID: UInt64 = 0

    init(session: URLSession = .shared, tokenStore: AccountTokenStoring = KeychainTokenStore()) {
        self.session = session
        self.tokenStore = tokenStore
    }

    var hasSession: Bool { tokens != nil }

    func install(_ tokens: AccountTokens) throws {
        try tokenStore.save(tokens)
        sessionGeneration &+= 1
        refreshTask = nil
        refreshTaskID = nil
        refreshTaskGeneration = nil
        self.tokens = tokens
    }

    @discardableResult
    func restore() -> Bool {
        sessionGeneration &+= 1
        refreshTask = nil
        refreshTaskID = nil
        refreshTaskGeneration = nil
        tokens = tokenStore.load()
        return tokens != nil
    }

    func clear() {
        let task = refreshTask
        sessionGeneration &+= 1
        refreshTask = nil
        refreshTaskID = nil
        refreshTaskGeneration = nil
        tokens = nil
        tokenStore.clear()
        task?.cancel()
    }

    func data(path: String, method: String, body: Data?) async throws -> (Data, HTTPURLResponse) {
        guard let rejectedTokens = currentSession else { throw URLError(.userAuthenticationRequired) }

        let initial = try await send(path: path, method: method, body: body, accessToken: rejectedTokens.tokens.accessToken)
        guard initial.1.statusCode == 401 else { return initial }

        let retrySession = try await refreshedTokens(afterRejecting: rejectedTokens)
        let retried = try await send(path: path, method: method, body: body, accessToken: retrySession.tokens.accessToken)
        if retried.1.statusCode == 401 {
            revokeRetry(ifCurrent: retrySession)
            throw BearerSessionError.unauthorized
        }
        return retried
    }

    private var currentSession: BearerSession? {
        guard let tokens else { return nil }
        return BearerSession(tokens: tokens, generation: sessionGeneration)
    }

    private func refreshedTokens(afterRejecting rejectedSession: BearerSession) async throws -> BearerSession {
        guard let currentSession else { throw URLError(.userAuthenticationRequired) }
        if currentSession.generation != rejectedSession.generation
            || currentSession.tokens.accessToken != rejectedSession.tokens.accessToken {
            return currentSession
        }

        if let refreshTask,
           let refreshTaskID,
           refreshTaskGeneration == currentSession.generation {
            return try await awaitRefresh(
                refreshTask,
                id: refreshTaskID,
                generation: currentSession.generation
            )
        }

        let refreshToken = currentSession.tokens.refreshToken
        let refreshGeneration = currentSession.generation
        nextRefreshTaskID &+= 1
        let taskID = nextRefreshTaskID
        let task = Task { [weak self, session] () throws -> AccountTokens in
            do {
                let rotatedTokens = try await Self.refresh(using: session, refreshToken: refreshToken)
                guard let self else { return rotatedTokens }
                guard self.sessionGeneration == refreshGeneration,
                      self.tokens?.refreshToken == refreshToken
                else { throw CancellationError() }
                try self.tokenStore.save(rotatedTokens)
                self.tokens = rotatedTokens
                return rotatedTokens
            } catch BearerSessionError.unauthorized {
                self?.revokeRefresh(
                    expectedGeneration: refreshGeneration,
                    expectedRefreshToken: refreshToken
                )
                throw BearerSessionError.unauthorized
            }
        }
        refreshTask = task
        refreshTaskID = taskID
        refreshTaskGeneration = refreshGeneration
        return try await awaitRefresh(task, id: taskID, generation: refreshGeneration)
    }

    private func awaitRefresh(
        _ task: Task<AccountTokens, Error>,
        id: UInt64,
        generation: UInt64
    ) async throws -> BearerSession {
        defer { clearRefreshTask(ifMatching: id) }
        return BearerSession(tokens: try await task.value, generation: generation)
    }

    private func clearRefreshTask(ifMatching id: UInt64) {
        guard refreshTaskID == id else { return }
        refreshTask = nil
        refreshTaskID = nil
        refreshTaskGeneration = nil
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
        let refreshed = try JSONDecoder().decode(RefreshResponse.self, from: data)
        return AccountTokens(accessToken: refreshed.accessToken, refreshToken: refreshed.refreshToken)
    }

    private func revokeRetry(ifCurrent session: BearerSession) {
        guard sessionGeneration == session.generation,
              tokens?.accessToken == session.tokens.accessToken
        else { return }
        clear()
        onRevoked?()
    }

    private func revokeRefresh(expectedGeneration: UInt64, expectedRefreshToken: String) {
        guard sessionGeneration == expectedGeneration,
              tokens?.refreshToken == expectedRefreshToken
        else { return }
        clear()
        onRevoked?()
    }
}

private struct BearerSession {
    let tokens: AccountTokens
    let generation: UInt64
}

private struct RefreshRequest: Encodable {
    let refreshToken: String
}

private struct RefreshResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let sessionId: String
    let accessExpiresAt: String
}

private enum BearerSessionError: Error {
    case unauthorized
    case refreshFailed(status: Int)
}
