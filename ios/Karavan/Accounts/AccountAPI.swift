import Foundation

struct AccountHTTPError: LocalizedError {
    let status: Int
    let response: AccountAPIError?

    var errorDescription: String? { response?.message ?? "Sunucuya ulaşılamadı." }
}

@MainActor
final class AccountAPI {
    private let session: URLSession
    private let authenticated: AuthenticatedRequestSending
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        session: URLSession = .shared,
        authenticated: AuthenticatedRequestSending? = nil
    ) {
        self.session = session
        self.authenticated = authenticated ?? BearerSessionCoordinator.shared
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

    func me() async throws -> AccountMeResponse {
        try await sendAuthenticated(path: "me")
    }

    func updateTravelProfile(_ profile: AccountTravelProfile) async throws -> AccountUser {
        struct Body: Encodable { let travelProfile: AccountTravelProfile }
        struct Response: Decodable { let user: AccountUser }
        let response: Response = try await sendAuthenticated(
            path: "me",
            method: "PATCH",
            body: Body(travelProfile: profile)
        )
        return response.user
    }

    func logout() async {
        let _: EmptyResponse? = try? await sendAuthenticated(path: "auth/logout", method: "POST")
    }

    func createTrip(_ draft: RouteDraft) async throws -> AccountTrip {
        struct Body: Encodable {
            let name: String
            let kind: String
            let transportMode: String
            let stops: [AccountRouteStop]
        }
        let response: AccountTripResponse = try await sendAuthenticated(
            path: "trips",
            method: "POST",
            body: Body(name: draft.name, kind: "standard", transportMode: draft.transportMode.rawValue, stops: draft.apiStops)
        )
        return response.trip
    }

    func invite(tripId: String, revision: Int, email: String, role: AccountTripRole) async throws -> AccountTrip {
        struct Body: Encodable { let baseRevision: Int; let email: String; let role: String }
        let response: AccountTripResponse = try await sendAuthenticated(
            path: "trips/\(tripId)/members",
            method: "POST",
            body: Body(baseRevision: revision, email: email, role: role.rawValue)
        )
        return response.trip
    }

    func updateStop(tripId: String, revision: Int, stop: AccountRouteStop) async throws -> AccountTrip {
        struct Changes: Encodable {
            let name: String; let lat: Double; let lng: Double; let note: String?
            let arrivalAt: String?; let accommodation: String?; let link: String?
            let arrivalTarget: AccountArrivalTarget?; let stayDetails: AccountStayDetails?
        }
        struct Body: Encodable { let baseRevision: Int; let stopId: String; let changes: Changes }
        let changes = Changes(name: stop.name, lat: stop.lat, lng: stop.lng, note: stop.note,
                              arrivalAt: stop.arrivalAt, accommodation: stop.accommodation, link: stop.link,
                              arrivalTarget: stop.arrivalTarget, stayDetails: stop.stayDetails)
        let response: AccountTripResponse = try await sendAuthenticated(
            path: "trips/\(tripId)/stops",
            method: "PATCH",
            body: Body(baseRevision: revision, stopId: stop.id, changes: changes)
        )
        return response.trip
    }

    func addStop(tripId: String, revision: Int, stop: AccountRouteStop) async throws -> AccountTrip {
        struct Body: Encodable { let baseRevision: Int; let stop: AccountRouteStop }
        let response: AccountTripResponse = try await sendAuthenticated(
            path: "trips/\(tripId)/stops",
            method: "POST",
            body: Body(baseRevision: revision, stop: stop)
        )
        return response.trip
    }

    func updateTrip(
        tripId: String,
        revision: Int,
        name: String,
        transportMode: RouteTransportMode
    ) async throws -> AccountTrip {
        struct Body: Encodable {
            let baseRevision: Int
            let name: String
            let transportMode: String
        }
        let response: AccountTripResponse = try await sendAuthenticated(
            path: "trips/\(tripId)",
            method: "PATCH",
            body: Body(baseRevision: revision, name: name, transportMode: transportMode.rawValue)
        )
        return response.trip
    }

    func replaceStops(
        tripId: String,
        revision: Int,
        stops: [AccountRouteStop]
    ) async throws -> AccountTrip {
        struct Body: Encodable { let baseRevision: Int; let stops: [AccountRouteStop] }
        let response: AccountTripResponse = try await sendAuthenticated(
            path: "trips/\(tripId)/stops",
            method: "PATCH",
            body: Body(baseRevision: revision, stops: stops)
        )
        return response.trip
    }

    private func send<Response: Decodable>(
        path: String,
        method: String = "GET"
    ) async throws -> Response {
        try await send(path: path, method: method, bodyData: nil)
    }

    private func send<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) async throws -> Response {
        try await send(path: path, method: method, bodyData: encoder.encode(body))
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        bodyData: Data?
    ) async throws -> Response {
        guard let url = Config.accountAPIBaseURL?.appendingPathComponent(path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, rawResponse) = try await session.data(for: request)
        return try decode(data: data, response: rawResponse)
    }

    private func sendAuthenticated<Response: Decodable>(
        path: String,
        method: String = "GET"
    ) async throws -> Response {
        try await sendAuthenticated(path: path, method: method, bodyData: nil)
    }

    private func sendAuthenticated<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) async throws -> Response {
        try await sendAuthenticated(path: path, method: method, bodyData: encoder.encode(body))
    }

    private func sendAuthenticated<Response: Decodable>(
        path: String,
        method: String,
        bodyData: Data?
    ) async throws -> Response {
        let (data, response) = try await authenticated.data(path: path, method: method, body: bodyData)
        return try decode(data: data, response: response)
    }

    private func decode<Response: Decodable>(data: Data, response rawResponse: URLResponse) throws -> Response {
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
