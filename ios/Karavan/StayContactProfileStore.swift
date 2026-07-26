import Foundation

@MainActor
final class StayContactProfileStore: ObservableObject {
    @Published var profile: StayContactProfile {
        didSet { persist() }
    }

    private let key: String

    init(routeId: String) {
        key = "stay-contact-profile-\(routeId)"
        if let data = UserDefaults.standard.data(forKey: key),
           let value = try? JSONDecoder().decode(StayContactProfile.self, from: data) {
            profile = value
        } else {
            profile = StayContactProfile()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
