import CoreLocation

enum RouteStepState: Equatable {
    case origin
    case completed
    case active
    case available
    case locked
}

enum RouteStepPolicy {
    static func state(for stopId: String,
                      orderedStopIds: [String],
                      completedStopIds: Set<String>,
                      activeStopId: String?) -> RouteStepState {
        guard let index = orderedStopIds.firstIndex(of: stopId) else { return .locked }
        guard index > 0 else { return .origin }

        if activeStopId == stopId { return .active }
        if completedStopIds.contains(stopId) { return .completed }
        if activeStopId != nil { return .locked }

        return nextStartableStopId(orderedStopIds: orderedStopIds,
                                   completedStopIds: completedStopIds) == stopId
            ? .available
            : .locked
    }

    static func nextStartableStopId(orderedStopIds: [String],
                                    completedStopIds: Set<String>) -> String? {
        orderedStopIds.dropFirst().first { !completedStopIds.contains($0) }
    }

    static func isStartable(stopId: String,
                            orderedStopIds: [String],
                            completedStopIds: Set<String>,
                            activeStopId: String?) -> Bool {
        state(for: stopId,
              orderedStopIds: orderedStopIds,
              completedStopIds: completedStopIds,
              activeStopId: activeStopId) == .available
    }
}

struct CoordinateValue: Equatable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum RouteStartOrigin {
    static func coordinate(location: CoordinateValue?,
                           plannedOrigin: CoordinateValue) -> CoordinateValue {
        location ?? plannedOrigin
    }
}
