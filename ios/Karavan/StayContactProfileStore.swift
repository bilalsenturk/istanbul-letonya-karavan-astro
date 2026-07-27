import Foundation

enum TravelProfileSeed {
    static func make(
        accountName: String?,
        accountEmail: String?,
        vehicleDescription: String?,
        profile: AccountTravelProfile = AccountTravelProfile()
    ) -> AccountTravelProfile {
        var result = profile
        if result.contactName.trimmed.isEmpty {
            result.contactName = accountName?.trimmed ?? ""
        }
        if result.contactEmail?.trimmed.isEmpty != false {
            result.contactEmail = accountEmail?.trimmed.nilIfEmpty
        }
        if result.vehicleDescription.trimmed.isEmpty {
            result.vehicleDescription = vehicleDescription?.trimmed ?? ""
        }
        return result
    }
}

enum TravelProfileMerge {
    static func resolve(local: AccountTravelProfile, remote: AccountTravelProfile) -> AccountTravelProfile {
        switch (date(from: local.updatedAt), date(from: remote.updatedAt)) {
        case let (.some(localDate), .some(remoteDate)):
            return remoteDate >= localDate ? remote : local
        case (.some, .none):
            return local
        case (.none, .some):
            return remote
        case (.none, .none):
            // Both timestamps are unusable: the signed-in account remains the stable source.
            return remote
        }
    }

    private static func date(from timestamp: String) -> Date? {
        let value = timestamp.trimmed
        guard !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

enum TravelProfileVehicleSeed {
    // Kuzey'in gömülü rota verisindeki model ve çekili karavan tanımı.
    static let kuzey = "VW Passat 2016 1.6 TDI Highline (Camlı Tavan) + çekili karavan"
}

@MainActor
final class StayContactProfileStore: ObservableObject {
    @Published var profile: StayContactProfile {
        didSet { persistLegacyProfile() }
    }

    private let key: String
    private var accountProfile: AccountTravelProfile?
    private var boundAccountID: String?

    init(routeId: String) {
        key = "stay-contact-profile-\(routeId)"
        if let data = UserDefaults.standard.data(forKey: key),
           let value = try? JSONDecoder().decode(StayContactProfile.self, from: data) {
            profile = value
        } else {
            profile = StayContactProfile()
        }
    }

    func bind(account: AccountUser, vehicleSeed: String?) -> AccountTravelProfile {
        if boundAccountID != account.id {
            boundAccountID = account.id
            accountProfile = UserDefaults.standard.data(forKey: accountKey(for: account.id))
                .flatMap { try? JSONDecoder().decode(AccountTravelProfile.self, from: $0) }
        }
        let local = accountProfile ?? AccountTravelProfile(
            contactName: profile.contactName,
            adults: profile.adults,
            children: profile.children,
            vehicleDescription: profile.vehicleDescription,
            totalLengthMeters: profile.totalLengthMeters,
            needsElectricity: profile.needsElectricity,
            hasPet: profile.hasPet,
            additionalNeeds: profile.additionalNeeds,
            preferredLanguage: profile.preferredLanguage
        )
        let seededLocal = TravelProfileSeed.make(
            accountName: account.displayName,
            accountEmail: account.email,
            vehicleDescription: vehicleSeed,
            profile: local
        )
        let seededRemote = TravelProfileSeed.make(
            accountName: account.displayName,
            accountEmail: account.email,
            vehicleDescription: vehicleSeed,
            profile: account.travelProfile
        )
        let resolved = TravelProfileMerge.resolve(local: seededLocal, remote: seededRemote)
        persist(resolved)
        return resolved
    }

    func persist(_ value: AccountTravelProfile) {
        accountProfile = value
        if let boundAccountID, let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: accountKey(for: boundAccountID))
        }
        profile = StayContactProfile(
            contactName: value.contactName,
            adults: value.adults,
            children: value.children,
            vehicleDescription: value.vehicleDescription,
            totalLengthMeters: value.totalLengthMeters,
            needsElectricity: value.needsElectricity,
            hasPet: value.hasPet,
            additionalNeeds: value.additionalNeeds,
            preferredLanguage: value.preferredLanguage
        )
    }

    private func persistLegacyProfile() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func accountKey(for accountID: String) -> String {
        "account-travel-profile-\(accountID)-\(key)"
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
