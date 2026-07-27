import Foundation

enum Config {
    static let editsURL: URL? = nil
}

final class RoleStore {
    static let shared = RoleStore()
    var isDriver = false
}

final class PublishOutbox {
    static let shared = PublishOutbox()

    func enqueue(key: String, url: URL, body: Data, signature: String) {}
}

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
struct TripPlanStoreCheck {
    @MainActor static func main() throws {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try FileManager.default.createDirectory(
            at: documents,
            withIntermediateDirectories: true
        )

        let scope = ArrivalTargetOverrideScope(
            tripID: "trip-private",
            daySlug: "istanbul-sofya",
            userID: "user-private"
        )
        let contactedAt = Date(timeIntervalSince1970: 1_785_146_400)
        let target = ArrivalTarget(
            id: "private-camp",
            mapItemIdentifier: "maps-private-camp",
            name: "Private Camp",
            kind: .campground,
            latitude: 42.66,
            longitude: 23.28,
            formattedAddress: "Sofia, Bulgaria",
            phone: "+359 88 123 4567",
            whatsAppPhone: "+359 88 765 4321",
            email: "private@example.com",
            websiteURL: URL(string: "https://private.example.com/book")!,
            maximumLengthMeters: 11.5,
            source: .user,
            updatedAt: contactedAt
        )
        let stay = StayDetails(
            checkIn: contactedAt.addingTimeInterval(3_600),
            checkOut: contactedAt.addingTimeInterval(90_000),
            reservationStatus: .confirmed,
            reservationReference: "PRIVATE-REF-42",
            note: "Gate code 2468",
            estimatedArrival: "18:00–19:00",
            lastContactedAt: contactedAt
        )

        print("\n=== Private scoped arrival target persistence ===")
        let store = TripPlanStore()
        store.setArrivalTarget(target, stay: stay, slug: scope.daySlug, scope: scope)

        let inProcess = store.arrivalTargetOverride(slug: scope.daySlug, scope: scope)
        check("private store retains every contact channel", inProcess?.target == target)
        check("private store retains reservation and contact state", inProcess?.stay == stay)

        let relaunched = TripPlanStore()
        let restored = relaunched.arrivalTargetOverride(slug: scope.daySlug, scope: scope)
        check("relaunch restores every target field", restored?.target == target)
        check("relaunch restores every stay field", restored?.stay == stay)
        check("relaunch remains trip scoped", relaunched.arrivalTargetOverride(
            slug: scope.daySlug,
            scope: ArrivalTargetOverrideScope(
                tripID: "other-trip", daySlug: scope.daySlug, userID: scope.userID
            )
        ) == nil)
        check("relaunch remains day scoped", relaunched.arrivalTargetOverride(
            slug: "other-day",
            scope: ArrivalTargetOverrideScope(
                tripID: scope.tripID, daySlug: "other-day", userID: scope.userID
            )
        ) == nil)
        check("relaunch remains user scoped", relaunched.arrivalTargetOverride(
            slug: scope.daySlug,
            scope: ArrivalTargetOverrideScope(
                tripID: scope.tripID, daySlug: scope.daySlug, userID: "other-user"
            )
        ) == nil)
        check("private selection never enters shared edits", relaunched.edits == TripEdits())

        print("\n" + (failures == 0 ? "✅ TÜM KONTROLLER GEÇTİ" : "❌ \(failures) KONTROL BAŞARISIZ"))
        exit(failures == 0 ? 0 : 1)
    }
}
