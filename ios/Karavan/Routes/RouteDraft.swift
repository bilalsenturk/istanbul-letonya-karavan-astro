import Foundation

struct RouteDraftStop: Identifiable, Equatable, Hashable, Codable {
    let id: String
    var name: String
    var lat: Double
    var lng: Double
    var source: RouteStopSource = .place
    var note: String = ""
    var arrivalAt: Date?
    var accommodation: String = ""
    var link: String = ""
    var arrivalTarget: ArrivalTarget?
    var stayDetails: StayDetails?

    var hasValidCoordinate: Bool {
        lat.isFinite && lng.isFinite && abs(lat) <= 90 && abs(lng) <= 180
    }

    static func currentLocation(latitude: Double, longitude: Double) -> RouteDraftStop {
        RouteDraftStop(
            id: "current-location",
            name: "Konumum",
            lat: latitude,
            lng: longitude,
            source: .currentLocation
        )
    }
}

struct RouteDraft: Equatable {
    var name: String
    var transportMode: RouteTransportMode = .automobile
    var startsAt: Date?
    private(set) var stops: [RouteDraftStop] = []

    init(
        name: String,
        transportMode: RouteTransportMode = .automobile,
        startsAt: Date? = nil,
        stops: [RouteDraftStop] = []
    ) {
        self.name = name
        self.transportMode = transportMode
        self.startsAt = startsAt
        self.stops = stops
    }

    var isSavable: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && stops.count >= 2
            && stops.allSatisfy(\.hasValidCoordinate)
    }

    var apiStops: [AccountRouteStop] {
        let iso = ISO8601DateFormatter()
        return stops.enumerated().map { index, stop in
            AccountRouteStop(
                id: stop.id,
                name: stop.name,
                lat: stop.lat,
                lng: stop.lng,
                order: index,
                source: stop.source,
                note: stop.note.nilIfEmpty,
                arrivalAt: stop.arrivalAt.map(iso.string(from:)),
                accommodation: stop.accommodation.nilIfEmpty,
                link: stop.link.nilIfEmpty,
                arrivalTarget: stop.arrivalTarget.map(AccountArrivalTarget.init),
                stayDetails: stop.stayDetails.map(AccountStayDetails.init)
            )
        }
    }

    mutating func add(_ stop: RouteDraftStop) {
        guard stop.hasValidCoordinate, !stops.contains(where: { $0.id == stop.id }) else { return }
        stops.append(stop)
    }

    mutating func update(_ stop: RouteDraftStop) {
        guard stop.hasValidCoordinate, let index = stops.firstIndex(where: { $0.id == stop.id }) else { return }
        stops[index] = stop
    }

    mutating func replace(at index: Int, with stop: RouteDraftStop) {
        guard stops.indices.contains(index), stop.hasValidCoordinate else { return }
        stops[index] = RouteDraftStop(
            id: stops[index].id,
            name: stop.name,
            lat: stop.lat,
            lng: stop.lng,
            source: stop.source,
            note: stops[index].note,
            arrivalAt: stops[index].arrivalAt,
            accommodation: stops[index].accommodation,
            link: stops[index].link,
            arrivalTarget: stops[index].arrivalTarget,
            stayDetails: stops[index].stayDetails
        )
    }

    mutating func remove(id: String) {
        stops.removeAll { $0.id == id }
    }

    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let indexes = source.sorted()
        let moving = indexes.map { stops[$0] }
        for index in indexes.reversed() { stops.remove(at: index) }
        let removedBeforeDestination = indexes.filter { $0 < destination }.count
        let insertion = max(0, min(stops.count, destination - removedBeforeDestination))
        stops.insert(contentsOf: moving, at: insertion)
    }

    mutating func reverseStops() {
        stops.reverse()
    }

    mutating func updateCurrentLocation(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite,
              abs(latitude) <= 90, abs(longitude) <= 180,
              let index = stops.firstIndex(where: { $0.source == .currentLocation })
        else { return }
        stops[index].lat = latitude
        stops[index].lng = longitude
        stops[index].name = "Konumum"
    }

    init(trip: AccountTrip) {
        name = trip.name
        transportMode = trip.transportMode ?? .automobile
        stops = trip.stops.sorted(by: { $0.order < $1.order }).map { stop in
            RouteDraftStop(
                id: stop.id,
                name: stop.resolvedSource == .currentLocation ? "Konumum" : stop.name,
                lat: stop.lat,
                lng: stop.lng,
                source: stop.resolvedSource,
                note: stop.note ?? "",
                arrivalAt: stop.arrivalAt.flatMap(ISO8601DateFormatter().date(from:)),
                accommodation: stop.accommodation ?? "",
                link: stop.link ?? "",
                arrivalTarget: stop.resolvedArrivalTarget,
                stayDetails: stop.resolvedStayDetails
            )
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
