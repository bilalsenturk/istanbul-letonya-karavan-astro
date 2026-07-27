import Foundation

struct AccountHTTPError: LocalizedError {
    let status: Int
    let response: AccountAPIError?

    var errorDescription: String? { response?.message ?? "Sunucuya ulaşılamadı." }
}

final class AccountAPI {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func signIn(identityToken: String, rawNonce: String, givenName: String?, familyName: String?) async throws -> AccountAuthResponse {
        struct Body: Encodable {
            let identityToken: String
            let rawNonce: String
            let givenName: String?
            let familyName: String?
        }
        return try await send(path: "auth/apple", method: "POST", body: Body(
            identityToken: identityToken,
            rawNonce: rawNonce,
            givenName: givenName,
            familyName: familyName
        ))
    }

    func refresh(_ refreshToken: String) async throws -> AccountTokens {
        struct Body: Encodable { let refreshToken: String }
        struct Response: Decodable { let accessToken: String; let refreshToken: String }
        let response: Response = try await send(path: "auth/refresh", method: "POST", body: Body(refreshToken: refreshToken))
        return AccountTokens(accessToken: response.accessToken, refreshToken: response.refreshToken)
    }

    func me(accessToken: String) async throws -> AccountMeResponse {
        try await send(path: "me", accessToken: accessToken)
    }

    func updateTravelProfile(_ profile: AccountTravelProfile, accessToken: String) async throws -> AccountUser {
        struct Body: Encodable { let travelProfile: AccountTravelProfile }
        struct Response: Decodable { let user: AccountUser }
        let response: Response = try await send(
            path: "me",
            method: "PATCH",
            accessToken: accessToken,
            body: Body(travelProfile: profile)
        )
        return response.user
    }

    func logout(accessToken: String) async {
        let _: EmptyResponse? = try? await send(path: "auth/logout", method: "POST", accessToken: accessToken)
    }

    func createTrip(_ draft: RouteDraft, accessToken: String) async throws -> AccountTrip {
        struct Body: Encodable {
            let name: String
            let kind: String
            let transportMode: String
            let stops: [AccountRouteStop]
        }
        let response: AccountTripResponse = try await send(
            path: "trips",
            method: "POST",
            accessToken: accessToken,
            body: Body(name: draft.name, kind: "standard", transportMode: draft.transportMode.rawValue, stops: draft.apiStops)
        )
        return response.trip
    }

    func invite(tripId: String, revision: Int, email: String, role: AccountTripRole, accessToken: String) async throws -> AccountTrip {
        struct Body: Encodable { let baseRevision: Int; let email: String; let role: String }
        let response: AccountTripResponse = try await send(
            path: "trips/\(tripId)/members",
            method: "POST",
            accessToken: accessToken,
            body: Body(baseRevision: revision, email: email, role: role.rawValue)
        )
        return response.trip
    }

    func updateStop(tripId: String, revision: Int, stop: AccountRouteStop, accessToken: String) async throws -> AccountTrip {
        struct Changes: Encodable {
            let name: String; let lat: Double; let lng: Double; let note: String?
            let arrivalAt: String?; let accommodation: String?; let link: String?
            let arrivalTarget: AccountArrivalTarget?; let stayDetails: AccountStayDetails?
        }
        struct Body: Encodable { let baseRevision: Int; let stopId: String; let changes: Changes }
        let changes = Changes(name: stop.name, lat: stop.lat, lng: stop.lng, note: stop.note,
                              arrivalAt: stop.arrivalAt, accommodation: stop.accommodation, link: stop.link,
                              arrivalTarget: stop.arrivalTarget, stayDetails: stop.stayDetails)
        let response: AccountTripResponse = try await send(
            path: "trips/\(tripId)/stops",
            method: "PATCH",
            accessToken: accessToken,
            body: Body(baseRevision: revision, stopId: stop.id, changes: changes)
        )
        return response.trip
    }

    func addStop(tripId: String, revision: Int, stop: AccountRouteStop, accessToken: String) async throws -> AccountTrip {
        struct Body: Encodable { let baseRevision: Int; let stop: AccountRouteStop }
        let response: AccountTripResponse = try await send(
            path: "trips/\(tripId)/stops",
            method: "POST",
            accessToken: accessToken,
            body: Body(baseRevision: revision, stop: stop)
        )
        return response.trip
    }

    func updateTrip(
        tripId: String,
        revision: Int,
        name: String,
        transportMode: RouteTransportMode,
        accessToken: String
    ) async throws -> AccountTrip {
        struct Body: Encodable {
            let baseRevision: Int
            let name: String
            let transportMode: String
        }
        let response: AccountTripResponse = try await send(
            path: "trips/\(tripId)",
            method: "PATCH",
            accessToken: accessToken,
            body: Body(baseRevision: revision, name: name, transportMode: transportMode.rawValue)
        )
        return response.trip
    }

    func replaceStops(
        tripId: String,
        revision: Int,
        stops: [AccountRouteStop],
        accessToken: String
    ) async throws -> AccountTrip {
        struct Body: Encodable { let baseRevision: Int; let stops: [AccountRouteStop] }
        let response: AccountTripResponse = try await send(
            path: "trips/\(tripId)/stops",
            method: "PATCH",
            accessToken: accessToken,
            body: Body(baseRevision: revision, stops: stops)
        )
        return response.trip
    }

    private func send<Response: Decodable>(
        path: String,
        method: String = "GET",
        accessToken: String? = nil
    ) async throws -> Response {
        try await send(path: path, method: method, accessToken: accessToken, bodyData: nil)
    }

    private func send<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        accessToken: String? = nil,
        body: Body
    ) async throws -> Response {
        try await send(path: path, method: method, accessToken: accessToken, bodyData: encoder.encode(body))
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        accessToken: String?,
        bodyData: Data?
    ) async throws -> Response {
        guard let url = Config.accountAPIBaseURL?.appendingPathComponent(path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        let (data, rawResponse) = try await session.data(for: request)
        guard let response = rawResponse as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else {
            throw AccountHTTPError(status: response.statusCode, response: try? decoder.decode(AccountAPIError.self, from: data))
        }
        if Response.self == EmptyResponse.self, data.isEmpty {
            return EmptyResponse() as! Response
        }
        return try decoder.decode(Response.self, from: data)
    }
}

private struct EmptyResponse: Codable {}
