import Foundation

enum PublishedTripResource: String, Codable {
    case liveLocation = "live-location"
    case expenseSummary = "expense-summary"
    case publishedPlan = "published-plan"
    case sharedJournal = "shared-journal"
}

struct PublishedTripScope: Equatable {
    let tripID: String

    init?(trip: AccountTrip?) {
        guard let trip, trip.kind == .kuzey2026, trip.features.publicTracking else { return nil }
        tripID = trip.id
    }

    /// Resolve the selected ID against the latest account payload so revoked
    /// feature flags and removed trips cannot keep an eligible stale copy alive.
    static func reconciledTrip(selected: AccountTrip?, in trips: [AccountTrip]) -> AccountTrip? {
        guard let selected else { return nil }
        return trips.first { $0.id == selected.id }
    }
}

@MainActor
protocol PublishedTripSending: AnyObject {
    func put(scope: PublishedTripScope, resource: PublishedTripResource, body: Data) async throws
}

@MainActor
final class PublishedTripClient: PublishedTripSending {
    static let shared = PublishedTripClient()

    private let authenticated: AuthenticatedRequestSending

    init(authenticated: AuthenticatedRequestSending? = nil) {
        self.authenticated = authenticated ?? BearerSessionCoordinator.shared
    }

    func put(scope: PublishedTripScope, resource: PublishedTripResource, body: Data) async throws {
        let (data, response) = try await authenticated.data(
            path: "trips/\(scope.tripID)/\(resource.rawValue)",
            method: "PUT",
            body: body
        )
        guard (200..<300).contains(response.statusCode),
              (try? JSONDecoder().decode(PublishedTripResponse.self, from: data).ok) == true
        else { throw URLError(.badServerResponse) }
    }
}

private struct PublishedTripResponse: Decodable {
    let ok: Bool
    let revision: Int
    let updatedAt: String
}
