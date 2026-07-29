import Foundation

struct TravelProfileBinding: Equatable {
    let profile: AccountTravelProfile
    let needsSync: Bool
}

enum TravelProfileEmail {
    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        guard normalized.count <= 254,
              normalized.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
        else { return nil }
        return normalized
    }
}

enum TravelProfileSeed {
    static func make(
        accountName: String?,
        accountEmail: String?,
        vehicleDescription: String?,
        profile: AccountTravelProfile = AccountTravelProfile()
    ) -> AccountTravelProfile {
        var result = profile
        if result.contactName.trimmed.isEmpty { result.contactName = accountName?.trimmed ?? "" }
        if result.contactEmail?.trimmed.isEmpty != false { result.contactEmail = accountEmail?.trimmed.nilIfEmpty }
        if result.vehicleDescription.trimmed.isEmpty { result.vehicleDescription = vehicleDescription?.trimmed ?? "" }
        return result
    }
}

enum TravelProfileMerge {
    static func resolve(local: AccountTravelProfile, remote: AccountTravelProfile) -> AccountTravelProfile {
        switch (date(from: local.updatedAt), date(from: remote.updatedAt)) {
        case let (.some(localDate), .some(remoteDate)): return remoteDate >= localDate ? remote : local
        case (.some, .none): return local
        case (.none, .some): return remote
        case (.none, .none): return remote
        }
    }

    private static func date(from timestamp: String) -> Date? {
        let value = timestamp.trimmed
        guard !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

enum TravelProfileSaveGuard {
    static func accepts(
        currentAccountID: String?,
        requestAccountID: String,
        submittedRevision: Int,
        currentRevision: Int
    ) -> Bool {
        currentAccountID == requestAccountID && submittedRevision == currentRevision
    }
}

/// Saf oturum karşılaştırması: geç gelen bir istek yalnızca aynı kullanıcı ve
/// aynı oturum kimliği hâlâ etkinken oturum durumunu güncelleyebilir.
enum TravelProfileSessionGuard {
    static func accepts(
        currentAccountID: String?,
        currentSessionID: UUID?,
        expectedAccountID: String,
        expectedSessionID: UUID
    ) -> Bool {
        currentAccountID == expectedAccountID && currentSessionID == expectedSessionID
    }
}

/// İptal edilen veya oturum değişmiş bir profil isteğinin UI'da hata olarak
/// görünmemesi için açık sonuç türü.
enum TravelProfileSaveError: Error, Equatable {
    case staleSession
}

enum TravelProfileSaveOperationGuard {
    static func isCurrent(activeOperationID: UUID?, operationID: UUID) -> Bool {
        activeOperationID == operationID
    }
}

/// Kaydetme isteğinin başladığı andaki bütün taslak değerleri. Ham uzunluk
/// metni ayrıca tutulur; `10,5` ile `10.5` aynı sayıya dönüşse bile kullanıcının
/// editörü isteğin ardından değiştirdiğini ayırt eder.
struct TravelProfileDraftFingerprint: Equatable {
    let profile: AccountTravelProfile
    let totalLengthText: String
}

enum TravelProfileReconciliationGuard {
    static func accepts(
        currentAccountID: String?,
        requestAccountID: String,
        activeOperationID: UUID?,
        operationID: UUID,
        currentDraft: TravelProfileDraftFingerprint,
        submittedDraft: TravelProfileDraftFingerprint
    ) -> Bool {
        currentAccountID == requestAccountID
            && TravelProfileSaveOperationGuard.isCurrent(
                activeOperationID: activeOperationID,
                operationID: operationID
            )
            && currentDraft == submittedDraft
    }
}

enum TravelProfileLength {
    enum Error: Swift.Error, Equatable { case invalid, outOfRange }

    static func parse(_ text: String, locale: Locale = .current) -> Result<Double?, Error> {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .success(nil) }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.isLenient = false
        let parsed = formatter.number(from: value)?.doubleValue
            ?? Double(value.replacingOccurrences(of: ",", with: "."))
        guard let parsed, parsed.isFinite else { return .failure(.invalid) }
        guard (1 ... 30).contains(parsed) else { return .failure(.outOfRange) }
        return .success(parsed)
    }
}

enum TravelProfileVehicleSeed {
    static let kuzey = "VW Passat 2016 1.6 TDI Highline (Camlı Tavan) + çekili karavan"
}

@MainActor
final class StayContactProfileStore: ObservableObject {
    @Published var profile: StayContactProfile { didSet { persistSignedOutProfile() } }

    private let routeID: String
    private let defaults: UserDefaults
    private let now: () -> Date
    private var boundAccountID: String?
    private var accountProfile: AccountTravelProfile?

    init(
        routeId: String,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        routeID = routeId
        self.defaults = defaults
        self.now = now
        profile = Self.decode(StayContactProfile.self, from: defaults, key: Self.signedOutKey(routeId))
            ?? Self.decode(StayContactProfile.self, from: defaults, key: Self.legacyKey(routeId))
            ?? StayContactProfile()
    }

    func bind(account: AccountUser, vehicleSeed: String?) -> TravelProfileBinding {
        if boundAccountID != account.id {
            boundAccountID = account.id
            accountProfile = Self.decode(AccountTravelProfile.self, from: defaults, key: accountKey(account.id))
        }

        let remote = TravelProfileSeed.make(
            accountName: account.displayName,
            accountEmail: account.email,
            vehicleDescription: vehicleSeed,
            profile: account.travelProfile
        )
        let legacyMigration = consumeLegacyIfNeeded(ownerID: account.id)
        let signedOutMigration = legacyMigration == nil
            ? consumeSignedOutIfNeeded(ownerID: account.id)
            : nil
        if accountProfile == nil, let signedOutMigration {
            let claimed = TravelProfileSeed.make(
                accountName: account.displayName,
                accountEmail: account.email,
                vehicleDescription: vehicleSeed,
                profile: signedOutMigration
            )
            persistAccount(claimed, accountID: account.id)
            return TravelProfileBinding(profile: claimed, needsSync: claimed != remote)
        }
        guard let local = accountProfile ?? legacyMigration else {
            persistAccount(remote, accountID: account.id)
            return TravelProfileBinding(profile: remote, needsSync: false)
        }

        let seededLocal = TravelProfileSeed.make(
            accountName: account.displayName,
            accountEmail: account.email,
            vehicleDescription: vehicleSeed,
            profile: local
        )
        let resolved = TravelProfileMerge.resolve(local: seededLocal, remote: remote)
        persistAccount(resolved, accountID: account.id)
        return TravelProfileBinding(profile: resolved, needsSync: resolved == seededLocal && resolved != remote)
    }

    func signedOutProfile(vehicleSeed: String?) -> AccountTravelProfile {
        TravelProfileSeed.make(
            accountName: nil,
            accountEmail: nil,
            vehicleDescription: vehicleSeed,
            profile: accountProfile(from: profile, updatedAt: profile.updatedAt ?? "")
        )
    }

    func persistAccount(_ value: AccountTravelProfile, accountID: String) {
        guard boundAccountID == accountID else { return }
        accountProfile = value
        Self.encode(value, to: defaults, key: accountKey(accountID))
    }

    func persistSignedOut(_ value: AccountTravelProfile) {
        profile = StayContactProfile(
            contactName: value.contactName,
            contactEmail: TravelProfileEmail.normalized(value.contactEmail),
            adults: value.adults,
            children: value.children,
            vehicleDescription: value.vehicleDescription,
            totalLengthMeters: value.totalLengthMeters,
            needsElectricity: value.needsElectricity,
            hasPet: value.hasPet,
            additionalNeeds: value.additionalNeeds,
            preferredLanguage: value.preferredLanguage,
            updatedAt: value.updatedAt
        )
    }

    private func consumeLegacyIfNeeded(ownerID: String) -> AccountTravelProfile? {
        guard defaults.string(forKey: Self.legacyOwnerKey(routeID)) == nil,
              let legacy = Self.decode(StayContactProfile.self, from: defaults, key: Self.legacyKey(routeID))
        else { return nil }

        // A timestamp-less legacy value is assigned one stable migration timestamp once.
        // It is copied only to the signed-out draft, then removed from the shared key.
        if Self.decode(StayContactProfile.self, from: defaults, key: Self.signedOutKey(routeID)) == nil {
            Self.encode(legacy, to: defaults, key: Self.signedOutKey(routeID))
        }
        defaults.set(ownerID, forKey: Self.legacyOwnerKey(routeID))
        defaults.removeObject(forKey: Self.legacyKey(routeID))
        return accountProfile(from: legacy, updatedAt: ISO8601DateFormatter().string(from: now()))
    }

    private func consumeSignedOutIfNeeded(ownerID: String) -> AccountTravelProfile? {
        let ownerKey = Self.legacyOwnerKey(routeID)
        let claimedOwner = defaults.string(forKey: ownerKey)
        guard claimedOwner == nil || claimedOwner == ownerID,
              let local = Self.decode(StayContactProfile.self, from: defaults, key: Self.signedOutKey(routeID)),
              local.updatedAt?.trimmed.isEmpty == false
        else { return nil }
        defaults.set(ownerID, forKey: ownerKey)
        return accountProfile(from: local, updatedAt: local.updatedAt ?? ISO8601DateFormatter().string(from: now()))
    }

    private func accountProfile(from local: StayContactProfile, updatedAt: String) -> AccountTravelProfile {
        AccountTravelProfile(
            contactName: local.contactName,
            contactEmail: TravelProfileEmail.normalized(local.contactEmail),
            adults: local.adults,
            children: local.children,
            vehicleDescription: local.vehicleDescription,
            totalLengthMeters: local.totalLengthMeters,
            needsElectricity: local.needsElectricity,
            hasPet: local.hasPet,
            additionalNeeds: local.additionalNeeds,
            preferredLanguage: local.preferredLanguage,
            updatedAt: updatedAt
        )
    }

    private func persistSignedOutProfile() {
        Self.encode(profile, to: defaults, key: Self.signedOutKey(routeID))
    }

    private func accountKey(_ accountID: String) -> String { "account-travel-profile-\(accountID)" }
    private static func legacyKey(_ routeID: String) -> String { "stay-contact-profile-\(routeID)" }
    private static func signedOutKey(_ routeID: String) -> String { "stay-contact-profile-signed-out-\(routeID)" }
    private static func legacyOwnerKey(_ routeID: String) -> String { "stay-contact-profile-consumed-owner-\(routeID)" }

    private static func decode<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private static func encode<T: Encodable>(_ value: T, to defaults: UserDefaults, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
