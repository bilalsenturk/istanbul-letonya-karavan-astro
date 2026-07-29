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

struct RemotePlanEdits: Codable, Equatable {
    let revision: Int
    let departureAt: Date?
    let days: [String: DayEdit]
    let updatedAt: Date

    var edits: TripEdits {
        TripEdits(departureAt: departureAt, days: days)
    }
}

enum PublishedTripClientError: Error {
    case revisionConflict(RemotePlanEdits)
    case rejected(status: Int)
}

@MainActor
protocol PublishedTripSending: AnyObject {
    func put(scope: PublishedTripScope, resource: PublishedTripResource, body: Data) async throws
}

@MainActor
protocol PlanEditSending: AnyObject {
    func getPlanEdits(scope: PublishedTripScope) async throws -> RemotePlanEdits
    func putPlanEdits(
        scope: PublishedTripScope,
        baseRevision: Int,
        edits: TripEdits
    ) async throws -> RemotePlanEdits
}

@MainActor
final class PublishedTripClient: PublishedTripSending, PlanEditSending {
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

    func getPlanEdits(scope: PublishedTripScope) async throws -> RemotePlanEdits {
        let (data, response) = try await authenticated.data(
            path: "trips/\(scope.tripID)/plan-edits",
            method: "GET",
            body: nil
        )
        guard (200..<300).contains(response.statusCode) else {
            throw PublishedTripClientError.rejected(status: response.statusCode)
        }
        return try Self.decoder.decode(RemotePlanEdits.self, from: data)
    }

    func putPlanEdits(
        scope: PublishedTripScope,
        baseRevision: Int,
        edits: TripEdits
    ) async throws -> RemotePlanEdits {
        let safeEdits = Self.safeSharedEdits(edits)
        let body = try Self.encoder.encode(PlanEditsPutBody(
            baseRevision: baseRevision,
            departureAt: safeEdits.departureAt,
            days: safeEdits.days
        ))
        let (data, response) = try await authenticated.data(
            path: "trips/\(scope.tripID)/plan-edits",
            method: "PUT",
            body: body
        )
        if response.statusCode == 409,
           let conflict = try? Self.decoder.decode(PlanEditsConflict.self, from: data),
           conflict.error == "revision_conflict" {
            throw PublishedTripClientError.revisionConflict(conflict.current)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw PublishedTripClientError.rejected(status: response.statusCode)
        }
        return try Self.decoder.decode(RemotePlanEdits.self, from: data)
    }

    private static func safeSharedEdits(_ edits: TripEdits) -> TripEdits {
        var safe = edits.sharedSyncState
        for (slug, edit) in safe.days {
            var day = edit
            day.arrivalTarget = edit.arrivalTarget?.publicSummary
            day.arrivalTargetScope = nil
            if var details = day.stayDetails {
                details.reservationReference = nil
                details.note = nil
                details.lastContactedAt = nil
                day.stayDetails = details
            }
            safe.days[slug] = day
        }
        return safe
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date: \(text)"
            )
        }
        return decoder
    }()
}

private struct PlanEditsPutBody: Encodable {
    let baseRevision: Int
    let departureAt: Date?
    let days: [String: DayEdit]

    private enum CodingKeys: String, CodingKey {
        case baseRevision, departureAt, days
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(baseRevision, forKey: .baseRevision)
        if let departureAt {
            try values.encode(departureAt, forKey: .departureAt)
        } else {
            try values.encodeNil(forKey: .departureAt)
        }
        try values.encode(days, forKey: .days)
    }
}

private struct PlanEditsConflict: Decodable {
    let error: String
    let current: RemotePlanEdits
}

private struct PublishedTripResponse: Decodable {
    let ok: Bool
    let revision: Int
    let updatedAt: String
}
