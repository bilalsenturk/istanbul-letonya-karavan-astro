enum LocationPermissionStatus: Sendable {
    case notDetermined
    case restricted
    case denied
    case whenInUse
    case always
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
