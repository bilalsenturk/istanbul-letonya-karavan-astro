import Foundation

enum AccountGlobalRole: String, Codable {
    case globalAdmin
    case user
}

enum AccountTripRole: String, Codable, CaseIterable {
    case owner
    case member
    case viewer

    var title: String {
        switch self {
        case .owner: "Sahip"
        case .member: "Üye"
        case .viewer: "Görüntüleyen"
        }
    }
}

enum AccountTripKind: String, Codable {
    case kuzey2026
    case standard
}

enum RouteTransportMode: String, Codable, CaseIterable, Identifiable {
    case automobile
    case walking
    case flight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automobile: "Otomobil"
        case .walking: "Yürüyüş"
        case .flight: "Uçak"
        }
    }

    var symbol: String {
        switch self {
        case .automobile: "car.fill"
        case .walking: "figure.walk"
        case .flight: "airplane"
        }
    }

    var guidance: String {
        switch self {
        case .automobile: "Apple trafik ve karayolu rotası"
        case .walking: "Yaya yolları ve yürüyüş süresi"
        case .flight: "Kuş uçuşu mesafe + her uçuş için 2 saat işlem"
        }
    }
}

enum RouteStopSource: String, Codable, Equatable {
    case place
    case currentLocation
}

struct AccountArrivalTarget: Codable, Equatable {
    let id: String
    var mapItemIdentifier: String?
    var name: String
    var kind: ArrivalTargetKind
    var latitude: Double
    var longitude: Double
    var formattedAddress: String
    var phone: String?
    var whatsAppPhone: String?
    var email: String?
    var websiteURL: String?
    var source: ArrivalTargetSource
    var updatedAt: String

    init(_ target: ArrivalTarget) {
        id = target.id
        mapItemIdentifier = target.mapItemIdentifier
        name = target.name
        kind = target.kind
        latitude = target.latitude
        longitude = target.longitude
        formattedAddress = target.formattedAddress
        phone = target.phone
        whatsAppPhone = target.whatsAppPhone
        email = target.email
        websiteURL = target.websiteURL?.absoluteString
        source = target.source
        updatedAt = ISO8601DateFormatter().string(from: target.updatedAt)
    }

    var resolved: ArrivalTarget? {
        guard let updatedAt = Self.parseDate(updatedAt) else { return nil }
        return ArrivalTarget(
            id: id,
            mapItemIdentifier: mapItemIdentifier,
            name: name,
            kind: kind,
            latitude: latitude,
            longitude: longitude,
            formattedAddress: formattedAddress,
            phone: phone,
            whatsAppPhone: whatsAppPhone,
            email: email,
            websiteURL: websiteURL.flatMap(URL.init(string:)),
            source: source,
            updatedAt: updatedAt
        )
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

struct AccountStayDetails: Codable, Equatable {
    var checkIn: String?
    var checkOut: String?
    var reservationStatus: StayReservationStatus
    var reservationReference: String?
    var note: String?
    var estimatedArrival: String?
    var lastContactedAt: String?

    init(_ stay: StayDetails) {
        let formatter = ISO8601DateFormatter()
        checkIn = stay.checkIn.map(formatter.string(from:))
        checkOut = stay.checkOut.map(formatter.string(from:))
        reservationStatus = stay.reservationStatus
        reservationReference = stay.reservationReference
        note = stay.note
        estimatedArrival = stay.estimatedArrival
        lastContactedAt = stay.lastContactedAt.map(formatter.string(from:))
    }

    var resolved: StayDetails {
        StayDetails(
            checkIn: checkIn.flatMap(ISO8601DateFormatter().date(from:)),
            checkOut: checkOut.flatMap(ISO8601DateFormatter().date(from:)),
            reservationStatus: reservationStatus,
            reservationReference: reservationReference,
            note: note,
            estimatedArrival: estimatedArrival,
            lastContactedAt: lastContactedAt.flatMap(ISO8601DateFormatter().date(from:))
        )
    }
}

struct AccountUser: Codable, Identifiable, Equatable {
    let id: String
    let email: String?
    let displayName: String?
    let globalRole: AccountGlobalRole
    let createdAt: String
    let updatedAt: String
    var travelProfile: AccountTravelProfile

    private enum CodingKeys: String, CodingKey {
        case id, email, displayName, globalRole, createdAt, updatedAt, travelProfile
    }

    init(
        id: String,
        email: String?,
        displayName: String?,
        globalRole: AccountGlobalRole,
        createdAt: String,
        updatedAt: String,
        travelProfile: AccountTravelProfile? = nil
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.globalRole = globalRole
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.travelProfile = travelProfile
            ?? AccountTravelProfile(contactName: displayName ?? "", contactEmail: email, updatedAt: updatedAt)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(String.self, forKey: .id),
            email: try values.decodeIfPresent(String.self, forKey: .email),
            displayName: try values.decodeIfPresent(String.self, forKey: .displayName),
            globalRole: try values.decode(AccountGlobalRole.self, forKey: .globalRole),
            createdAt: try values.decode(String.self, forKey: .createdAt),
            updatedAt: try values.decode(String.self, forKey: .updatedAt),
            travelProfile: try values.decodeIfPresent(AccountTravelProfile.self, forKey: .travelProfile)
        )
    }

    var visibleName: String { displayName ?? email ?? "Kuzey kullanıcısı" }
    var isAdmin: Bool { globalRole == .globalAdmin }
}

struct AccountTravelProfile: Codable, Equatable {
    var contactName: String
    var contactEmail: String?
    var adults: Int
    var children: Int
    var vehicleDescription: String
    var totalLengthMeters: Double?
    var needsElectricity: Bool
    var hasPet: Bool
    var additionalNeeds: String
    var preferredLanguage: StayMessageLanguage
    var updatedAt: String

    init(
        contactName: String = "",
        contactEmail: String? = nil,
        adults: Int = 2,
        children: Int = 0,
        vehicleDescription: String = "",
        totalLengthMeters: Double? = nil,
        needsElectricity: Bool = true,
        hasPet: Bool = false,
        additionalNeeds: String = "",
        preferredLanguage: StayMessageLanguage = .english,
        updatedAt: String = ""
    ) {
        self.contactName = contactName
        self.contactEmail = contactEmail
        self.adults = adults
        self.children = children
        self.vehicleDescription = vehicleDescription
        self.totalLengthMeters = totalLengthMeters
        self.needsElectricity = needsElectricity
        self.hasPet = hasPet
        self.additionalNeeds = additionalNeeds
        self.preferredLanguage = preferredLanguage
        self.updatedAt = updatedAt
    }
}

struct TripFeatures: Codable, Equatable {
    let latvian: Bool
    let kuzeyMusic: Bool
    let publicTracking: Bool

    static let standard = TripFeatures(latvian: false, kuzeyMusic: false, publicTracking: false)
    static let kuzey = TripFeatures(latvian: true, kuzeyMusic: true, publicTracking: true)
}

struct TripAccess: Codable, Equatable {
    let tripRole: AccountTripRole?
    let canEditTrip: Bool
    let canEditStops: Bool
    let canEditJournal: Bool
    let canManageMembers: Bool
    let canStartRoute: Bool
    let canDeleteTrip: Bool
}

struct AccountRouteStop: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var lat: Double
    var lng: Double
    var order: Int
    var source: RouteStopSource? = nil
    var note: String?
    var arrivalAt: String?
    var accommodation: String?
    var link: String?
    var arrivalTarget: AccountArrivalTarget? = nil
    var stayDetails: AccountStayDetails? = nil

    var resolvedSource: RouteStopSource { source ?? .place }
    var resolvedArrivalTarget: ArrivalTarget? { arrivalTarget?.resolved }
    var resolvedStayDetails: StayDetails? { stayDetails?.resolved }
}

struct AccountTripMember: Codable, Equatable {
    let userId: String
    var role: AccountTripRole
}

struct AccountTripInvite: Codable, Equatable, Identifiable {
    let email: String
    var role: AccountTripRole

    var id: String { email }
}

struct AccountTrip: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    let kind: AccountTripKind
    var transportMode: RouteTransportMode?
    var revision: Int
    let createdAt: String
    var updatedAt: String
    var stops: [AccountRouteStop]
    var members: [AccountTripMember]
    var invites: [AccountTripInvite]
    let features: TripFeatures
    let access: TripAccess

    var roleTitle: String {
        access.tripRole?.title ?? "Admin"
    }

    static func preferred(in trips: [AccountTrip], savedID: String?) -> AccountTrip? {
        if let savedID, let saved = trips.first(where: { $0.id == savedID }) {
            return saved
        }
        return trips.first(where: { $0.kind == .kuzey2026 }) ?? trips.first
    }
}

struct AccountAuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let sessionId: String
    let accessExpiresAt: String
    let user: AccountUser
    let trips: [AccountTrip]
}

struct AccountMeResponse: Codable {
    let user: AccountUser
    let trips: [AccountTrip]
}

struct AccountTripsResponse: Codable {
    let trips: [AccountTrip]
}

struct AccountTripResponse: Codable {
    let trip: AccountTrip
}

struct AccountAPIError: Codable, Error {
    let error: String
    let message: String
    let current: AccountTrip?
}
