import Foundation

enum LocationPermissionStatus: Sendable {
    case notDetermined
    case restricted
    case denied
    case whenInUse
    case always
}

enum NotificationScheduleIntent: Equatable, Sendable {
    case departure(Date)
    case dailyJournal(hour: Int)
    case dailySummary(hour: Int)
}

struct NotificationAuthorizationLifecycle: Sendable {
    private(set) var isAuthorized: Bool
    private(set) var departure: Date?
    private var dailyJournalHour: Int?
    private var dailySummaryHour: Int?

    init(isAuthorized: Bool) {
        self.isAuthorized = isAuthorized
    }

    mutating func register(_ intent: NotificationScheduleIntent) -> [NotificationScheduleIntent] {
        switch intent {
        case let .departure(date):
            departure = date
        case let .dailyJournal(hour):
            dailyJournalHour = hour
        case let .dailySummary(hour):
            dailySummaryHour = hour
        }
        return isAuthorized ? [intent] : []
    }

    mutating func transitionAuthorization(to isAuthorized: Bool) -> [NotificationScheduleIntent] {
        let becameAuthorized = !self.isAuthorized && isAuthorized
        self.isAuthorized = isAuthorized
        guard becameAuthorized else { return [] }

        var intents: [NotificationScheduleIntent] = []
        if let departure { intents.append(.departure(departure)) }
        if let dailyJournalHour { intents.append(.dailyJournal(hour: dailyJournalHour)) }
        if let dailySummaryHour { intents.append(.dailySummary(hour: dailySummaryHour)) }
        return intents
    }
}

struct LocationAuthorizationLifecycle<CachedLocation> {
    private(set) var status: LocationPermissionStatus
    private(set) var cachedLocation: CachedLocation?

    init(status: LocationPermissionStatus, cachedLocation: CachedLocation?) {
        self.status = status
        self.cachedLocation = cachedLocation
    }

    mutating func transitionAuthorization(to status: LocationPermissionStatus) {
        self.status = status
        switch status {
        case .whenInUse, .always:
            break
        case .notDetermined, .restricted, .denied:
            cachedLocation = nil
        }
    }

    mutating func cache(_ location: CachedLocation) {
        switch status {
        case .whenInUse, .always:
            cachedLocation = location
        case .notDetermined, .restricted, .denied:
            cachedLocation = nil
        }
    }
}

enum LocationPermissionAction: Sendable {
    case requestWhenInUse
    case startIfAuthorized
    case openSettings
}

/// UI'dan bağımsız izin kararı. Sistem istemlerini yalnızca kullanıcının
/// bağlamsal bir eylemine bağlamak için bütün konum yüzeyleri bu politikayı okur.
enum LocationPermissionPolicy {
    static func primaryAction(for status: LocationPermissionStatus) -> LocationPermissionAction {
        switch status {
        case .notDetermined:
            return .requestWhenInUse
        case .whenInUse, .always:
            return .startIfAuthorized
        case .denied, .restricted:
            return .openSettings
        }
    }

    static func showsBackgroundAction(for status: LocationPermissionStatus) -> Bool {
        status == .whenInUse
    }
}
