import Foundation

private var failures = 0

private func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    if condition() {
        print("  ✓ \(name)")
    } else {
        failures += 1
        print("  ✗ \(name)")
    }
}

/// UNUserNotificationCenter'ın `.notificationsNotAllowed` davranışını taklit
/// eder: yetkisiz teslim denemeleri kabul listesine girmez ve ayrı sayılır.
private struct FakeNotificationScheduleCenter {
    var allowsNotifications = false
    private(set) var accepted: [NotificationScheduleIntent] = []
    private(set) var notificationsNotAllowedCount = 0

    mutating func submit(_ intents: [NotificationScheduleIntent]) {
        for intent in intents {
            if allowsNotifications {
                accepted.append(intent)
            } else {
                notificationsNotAllowedCount += 1
            }
        }
    }
}

@main
struct PermissionPolicyCheck {
    static func main() {
        print("\n=== Konum izni eylem politikası ===")
        check(
            "ilk eylem yalnızca Kullanırken izni ister",
            LocationPermissionPolicy.primaryAction(for: .notDetermined) == .requestWhenInUse
        )
        check(
            "Kullanırken izninde konum takibi başlatılabilir",
            LocationPermissionPolicy.primaryAction(for: .whenInUse) == .startIfAuthorized
        )
        check(
            "Her Zaman izninde konum takibi başlatılabilir",
            LocationPermissionPolicy.primaryAction(for: .always) == .startIfAuthorized
        )
        check(
            "reddedilen izin Ayarlar'a yönlendirir",
            LocationPermissionPolicy.primaryAction(for: .denied) == .openSettings
        )
        check(
            "kısıtlı izin Ayarlar'a yönlendirir",
            LocationPermissionPolicy.primaryAction(for: .restricted) == .openSettings
        )

        print("\n=== Arka plan izni görünürlüğü ===")
        check(
            "arka plan eylemi yalnızca Kullanırken izninde görünür",
            LocationPermissionPolicy.showsBackgroundAction(for: .whenInUse)
                && !LocationPermissionPolicy.showsBackgroundAction(for: .notDetermined)
                && !LocationPermissionPolicy.showsBackgroundAction(for: .always)
                && !LocationPermissionPolicy.showsBackgroundAction(for: .denied)
                && !LocationPermissionPolicy.showsBackgroundAction(for: .restricted)
        )

        print("\n=== Bildirim yetki yaşam döngüsü ===")
        let firstDeparture = Date(timeIntervalSince1970: 1_785_300_000)
        let latestDeparture = Date(timeIntervalSince1970: 1_785_386_400)
        var notificationLifecycle = NotificationAuthorizationLifecycle(isAuthorized: false)
        var notificationCenter = FakeNotificationScheduleCenter()

        notificationCenter.submit(notificationLifecycle.register(.departure(firstDeparture)))
        notificationCenter.submit(notificationLifecycle.register(.departure(latestDeparture)))
        notificationCenter.submit(notificationLifecycle.register(.dailyJournal(hour: 21)))
        notificationCenter.submit(notificationLifecycle.register(.dailySummary(hour: 8)))
        check(
            "yetki yokken merkezde reddedilecek teslim yapılmaz",
            notificationCenter.accepted.isEmpty
                && notificationCenter.notificationsNotAllowedCount == 0
        )

        notificationCenter.allowsNotifications = true
        notificationCenter.submit(notificationLifecycle.transitionAuthorization(to: true))
        check(
            "ilk yetki geçişi son kalkış ve iki günlük hatırlatmayı birer kez kurar",
            notificationCenter.accepted.count == 3
                && notificationCenter.accepted.filter { $0 == .departure(latestDeparture) }.count == 1
                && notificationCenter.accepted.filter { $0 == .dailyJournal(hour: 21) }.count == 1
                && notificationCenter.accepted.filter { $0 == .dailySummary(hour: 8) }.count == 1
        )
        notificationCenter.submit(notificationLifecycle.transitionAuthorization(to: true))
        check(
            "aynı yetkinin yeniden tazelenmesi programı çoğaltmaz",
            notificationCenter.accepted.count == 3
        )

        print("\n=== Konum yetki yaşam döngüsü ===")
        var deniedLocation = LocationAuthorizationLifecycle(
            status: LocationPermissionStatus.always,
            cachedLocation: "56.9496,24.1052"
        )
        deniedLocation.transitionAuthorization(to: .denied)
        check(
            "ret geçişi önceden önbelleklenmiş konumu siler ve Ayarlar eylemini açar",
            deniedLocation.cachedLocation == nil
                && LocationPermissionPolicy.primaryAction(for: deniedLocation.status) == .openSettings
        )
        deniedLocation.cache("gecikmiş GPS örneği")
        check(
            "ret sonrasında gelen gecikmiş GPS örneği önbelleği yeniden doldurmaz",
            deniedLocation.cachedLocation == nil
        )

        var restrictedLocation = LocationAuthorizationLifecycle(
            status: LocationPermissionStatus.whenInUse,
            cachedLocation: "41.0082,28.9784"
        )
        restrictedLocation.transitionAuthorization(to: .restricted)
        check("kısıtlı geçiş de konum önbelleğini siler", restrictedLocation.cachedLocation == nil)

        var resetLocation = LocationAuthorizationLifecycle(
            status: LocationPermissionStatus.always,
            cachedLocation: "52.2297,21.0122"
        )
        resetLocation.transitionAuthorization(to: .notDetermined)
        check("belirsiz yetkiye dönüş konum önbelleğini siler", resetLocation.cachedLocation == nil)

        var foregroundLocation = LocationAuthorizationLifecycle(
            status: LocationPermissionStatus.always,
            cachedLocation: "54.6872,25.2797"
        )
        foregroundLocation.transitionAuthorization(to: .whenInUse)
        foregroundLocation.cache("56.9496,24.1052")
        check(
            "yetkili geçiş yeni konum örneğini kabul eder",
            foregroundLocation.cachedLocation == "56.9496,24.1052"
        )

        print(failures == 0 ? "\n✅ izin politikası geçti\n" : "\n❌ \(failures) başarısız\n")
        exit(failures == 0 ? 0 : 1)
    }
}
