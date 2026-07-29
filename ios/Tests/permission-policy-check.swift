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

        print(failures == 0 ? "\n✅ izin politikası geçti\n" : "\n❌ \(failures) başarısız\n")
        exit(failures == 0 ? 0 : 1)
    }
}
