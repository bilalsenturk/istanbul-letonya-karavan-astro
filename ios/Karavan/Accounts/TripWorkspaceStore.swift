import Foundation

@MainActor
final class TripWorkspaceStore: ObservableObject {
    @Published private(set) var trips: [AccountTrip] = []
    @Published var selectedTrip: AccountTrip?
    @Published var isWorking = false
    @Published var errorMessage: String?

    private var activeUserId: String?

    func activate(user: AccountUser, trips: [AccountTrip]) {
        activeUserId = user.id
        self.trips = trips.sorted { $0.updatedAt > $1.updatedAt }
        let saved = UserDefaults.standard.string(forKey: selectionKey(user.id))
        selectedTrip = AccountTrip.preferred(in: trips, savedID: saved)
    }

    func clear() {
        activeUserId = nil
        trips = []
        selectedTrip = nil
        errorMessage = nil
    }

    func reconcile(trips refreshedTrips: [AccountTrip]) {
        trips = refreshedTrips.sorted { $0.updatedAt > $1.updatedAt }
        selectedTrip = PublishedTripScope.reconciledTrip(selected: selectedTrip, in: refreshedTrips)
    }

    func select(_ trip: AccountTrip) {
        selectedTrip = trip
        if let activeUserId { UserDefaults.standard.set(trip.id, forKey: selectionKey(activeUserId)) }
    }

    func closeTrip() {
        selectedTrip = nil
        if let activeUserId { UserDefaults.standard.removeObject(forKey: selectionKey(activeUserId)) }
    }

    func replace(_ trip: AccountTrip) {
        if let index = trips.firstIndex(where: { $0.id == trip.id }) { trips[index] = trip }
        else { trips.append(trip) }
        if selectedTrip?.id == trip.id { selectedTrip = trip }
    }

    func create(_ draft: RouteDraft, account: AccountSessionStore) async {
        guard draft.isSavable else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let trip = try await account.createTrip(draft)
            replace(trip)
            select(trip)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func update(_ draft: RouteDraft, trip: AccountTrip, account: AccountSessionStore) async -> Bool {
        guard draft.isSavable else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            replace(try await account.saveRoute(trip: trip, draft: draft))
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func selectionKey(_ userId: String) -> String { "account-selected-trip-\(userId)" }
}
