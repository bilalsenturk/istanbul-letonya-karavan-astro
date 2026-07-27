import AuthenticationServices
import CryptoKit
import Foundation
import Security

@MainActor
final class AccountSessionStore: ObservableObject {
    @Published private(set) var user: AccountUser?
    @Published private(set) var initialTrips: [AccountTrip] = []
    @Published private(set) var isRestoring = true
    @Published private(set) var isSigningIn = false
    @Published var errorMessage: String?

    private let api: AccountAPI
    private let tokens: AccountTokenStoring
    private var currentTokens: AccountTokens?
    private var pendingNonce: String?

    init(api: AccountAPI = AccountAPI(), tokens: AccountTokenStoring = KeychainTokenStore()) {
        self.api = api
        self.tokens = tokens
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-preview-account") {
            user = .previewAdmin
            initialTrips = [.previewKuzey, .previewStandard]
            isRestoring = false
        }
        #endif
    }

    var isSignedIn: Bool { user != nil }
    var accessToken: String? { currentTokens?.accessToken }

    func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        pendingNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func completeAppleAuthorization(_ result: Result<ASAuthorization, Error>) async {
        guard !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityData = credential.identityToken,
                  let identityToken = String(data: identityData, encoding: .utf8),
                  let nonce = pendingNonce
            else { throw AccountSignInError.invalidCredential }
            let response = try await api.signIn(
                identityToken: identityToken,
                rawNonce: nonce,
                givenName: credential.fullName?.givenName,
                familyName: credential.fullName?.familyName
            )
            let accountTokens = AccountTokens(accessToken: response.accessToken, refreshToken: response.refreshToken)
            try tokens.save(accountTokens)
            currentTokens = accountTokens
            user = response.user
            initialTrips = response.trips
            errorMessage = nil
        } catch let error as ASAuthorizationError where error.code == .canceled {
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        pendingNonce = nil
    }

    func restore() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-preview-signed-out") {
            isRestoring = false
            return
        }
        #endif
        guard user == nil else { isRestoring = false; return }
        defer { isRestoring = false }
        guard let stored = tokens.load() else { return }
        do {
            let response = try await api.me(accessToken: stored.accessToken)
            currentTokens = stored
            user = response.user
            initialTrips = response.trips
        } catch let error as AccountHTTPError where error.status == 401 {
            do {
                let refreshed = try await api.refresh(stored.refreshToken)
                try tokens.save(refreshed)
                let response = try await api.me(accessToken: refreshed.accessToken)
                currentTokens = refreshed
                user = response.user
                initialTrips = response.trips
            } catch {
                clearLocalSession()
            }
        } catch {
            errorMessage = "Hesap bilgileri yenilenemedi. Bağlantınızı kontrol edin."
        }
    }

    func reload() async throws -> AccountMeResponse {
        guard let accessToken else { throw AccountSignInError.sessionRequired }
        let response = try await api.me(accessToken: accessToken)
        user = response.user
        initialTrips = response.trips
        return response
    }

    func saveTravelProfile(_ profile: AccountTravelProfile) async throws -> AccountUser {
        guard let accessToken else { throw AccountSignInError.sessionRequired }
        let updatedUser = try await api.updateTravelProfile(profile, accessToken: accessToken)
        user = updatedUser
        return updatedUser
    }

    func createTrip(_ draft: RouteDraft) async throws -> AccountTrip {
        guard let accessToken else { throw AccountSignInError.sessionRequired }
        let trip = try await api.createTrip(draft, accessToken: accessToken)
        initialTrips.append(trip)
        return trip
    }

    func invite(trip: AccountTrip, email: String, role: AccountTripRole) async throws -> AccountTrip {
        guard let accessToken else { throw AccountSignInError.sessionRequired }
        return try await api.invite(tripId: trip.id, revision: trip.revision, email: email, role: role, accessToken: accessToken)
    }

    func updateStop(trip: AccountTrip, stop: AccountRouteStop) async throws -> AccountTrip {
        guard let accessToken else { throw AccountSignInError.sessionRequired }
        return try await api.updateStop(tripId: trip.id, revision: trip.revision, stop: stop, accessToken: accessToken)
    }

    func addStop(trip: AccountTrip, stop: RouteDraftStop) async throws -> AccountTrip {
        guard let accessToken else { throw AccountSignInError.sessionRequired }
        let apiStop = AccountRouteStop(
            id: stop.id,
            name: stop.name,
            lat: stop.lat,
            lng: stop.lng,
            order: trip.stops.count,
            source: stop.source,
            note: stop.note.isEmpty ? nil : stop.note,
            arrivalAt: stop.arrivalAt.map(ISO8601DateFormatter().string(from:)),
            accommodation: stop.accommodation.isEmpty ? nil : stop.accommodation,
            link: stop.link.isEmpty ? nil : stop.link,
            arrivalTarget: stop.arrivalTarget.map(AccountArrivalTarget.init),
            stayDetails: stop.stayDetails.map(AccountStayDetails.init)
        )
        return try await api.addStop(tripId: trip.id, revision: trip.revision, stop: apiStop, accessToken: accessToken)
    }

    func saveRoute(trip: AccountTrip, draft: RouteDraft) async throws -> AccountTrip {
        guard let accessToken else { throw AccountSignInError.sessionRequired }
        var current = trip
        if trip.access.canEditTrip,
           trip.name != draft.name || (trip.transportMode ?? .automobile) != draft.transportMode {
            current = try await api.updateTrip(
                tripId: trip.id,
                revision: current.revision,
                name: draft.name,
                transportMode: draft.transportMode,
                accessToken: accessToken
            )
        }
        if trip.access.canEditStops {
            current = try await api.replaceStops(
                tripId: trip.id,
                revision: current.revision,
                stops: draft.apiStops,
                accessToken: accessToken
            )
        }
        if let index = initialTrips.firstIndex(where: { $0.id == current.id }) {
            initialTrips[index] = current
        }
        return current
    }

    func signOut() async {
        if let accessToken { await api.logout(accessToken: accessToken) }
        clearLocalSession()
    }

    private func clearLocalSession() {
        tokens.clear()
        currentTokens = nil
        user = nil
        initialTrips = []
        errorMessage = nil
    }

    private static func randomNonce(length: Int = 32) -> String {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var bytes = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { continue }
            for byte in bytes where remaining > 0 && byte < alphabet.count {
                result.append(alphabet[Int(byte)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private enum AccountSignInError: LocalizedError {
    case invalidCredential
    case sessionRequired

    var errorDescription: String? {
        switch self {
        case .invalidCredential: "Apple hesabı doğrulanamadı."
        case .sessionRequired: "Oturum açmanız gerekiyor."
        }
    }
}
