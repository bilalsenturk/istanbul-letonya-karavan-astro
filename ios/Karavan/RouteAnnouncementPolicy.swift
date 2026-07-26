import Foundation

enum RouteAnnouncementPolicy {
    static func allowsRouteReadyAnnouncement(
        triggeredByUserAction: Bool,
        routeStarted: Bool
    ) -> Bool {
        triggeredByUserAction && !routeStarted
    }

    static func allowsRouteProgressAnnouncement(
        routeStarted: Bool,
        activeStopId: String?,
        activeTargetId: String? = nil,
        nextStopId: String?,
        nextTargetId: String? = nil
    ) -> Bool {
        guard routeStarted,
              let activeStopId,
              let nextStopId,
              activeStopId == nextStopId
        else { return false }
        guard let nextTargetId else { return true }
        return activeTargetId == nextTargetId
    }

    static func allowsArrivalAnnouncement(
        routeStarted: Bool,
        activeStopId: String?,
        enteredStopId: String
    ) -> Bool {
        guard routeStarted,
              let activeStopId,
              activeStopId == enteredStopId
        else { return false }
        return true
    }

    static func allowsDrivingReminder(routeStarted: Bool) -> Bool {
        routeStarted
    }

    static func allowsDeviationAnnouncement(
        routeStarted: Bool,
        activeStopId: String?,
        nextStopId: String?,
        currentLegIndex: Int?,
        speedKmh: Int?,
        hasLegGeometry: Bool
    ) -> Bool {
        guard routeStarted,
              let activeStopId,
              let nextStopId,
              activeStopId == nextStopId,
              currentLegIndex != nil,
              hasLegGeometry,
              (speedKmh ?? 0) > 20
        else { return false }
        return true
    }
}
