import Foundation

struct GeoPoint: Codable, Hashable {
    let latitude: Double
    let longitude: Double

    func distanceKm(to other: GeoPoint) -> Double {
        let earthRadiusKm = 6_371.0088
        let latitudeDelta = (other.latitude - latitude).radians
        let longitudeDelta = (other.longitude - longitude).radians
        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(latitude.radians) * cos(other.latitude.radians)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return earthRadiusKm * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

enum CampDistancePolicy: Equatable, Codable, Hashable {
    case city(maximumKm: Double)
    case transit(maximumDetourKm: Double)

    private enum CodingKeys: String, CodingKey {
        case type, maximumKm, maximumDetourKm
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(String.self, forKey: .type) {
        case "city":
            self = .city(maximumKm: min(try values.decode(Double.self, forKey: .maximumKm), 25))
        case "transit":
            self = .transit(maximumDetourKm: min(try values.decode(Double.self, forKey: .maximumDetourKm), 10))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: values, debugDescription: "Unsupported camp distance policy")
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .city(let maximumKm):
            try values.encode("city", forKey: .type)
            try values.encode(min(maximumKm, 25), forKey: .maximumKm)
        case .transit(let maximumDetourKm):
            try values.encode("transit", forKey: .type)
            try values.encode(min(maximumDetourKm, 10), forKey: .maximumDetourKm)
        }
    }

    func accepts(candidate: GeoPoint, destination: GeoPoint, routeDistanceKm: Double?) -> Bool {
        switch self {
        case .city(let maximumKm):
            candidate.distanceKm(to: destination) <= min(maximumKm, 25)
        case .transit(let maximumDetourKm):
            routeDistanceKm.map { $0 <= min(maximumDetourKm, 10) } ?? false
        }
    }
}

struct TravelMedia: Codable, Hashable {
    let url: URL
    let credit: String
    let license: String
}

struct TravelSource: Codable, Hashable {
    let name: String
    let url: URL
}

struct CuratedCamp: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let location: GeoPoint
    let address: String
    let phone: String?
    let email: String?
    let websiteURL: URL
    let supportsCaravan: Bool
    let hasElectricity: Bool?
    let maximumLengthMeters: Double?
    let recommendation: String
    let warning: String?
    let media: TravelMedia
    let source: TravelSource
    let verifiedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, name, location, address, phone, email, websiteURL, supportsCaravan, hasElectricity
        case maximumLengthMeters, recommendation, warning, media, source, verifiedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        location = try values.decode(GeoPoint.self, forKey: .location)
        address = try values.decode(String.self, forKey: .address)
        phone = try values.decodeIfPresent(String.self, forKey: .phone)
        email = try values.decodeIfPresent(String.self, forKey: .email)
        websiteURL = try values.decode(URL.self, forKey: .websiteURL)
        supportsCaravan = try values.decode(Bool.self, forKey: .supportsCaravan)
        hasElectricity = try values.decodeIfPresent(Bool.self, forKey: .hasElectricity)
        maximumLengthMeters = try values.decodeIfPresent(Double.self, forKey: .maximumLengthMeters)
        recommendation = try values.decode(String.self, forKey: .recommendation)
        warning = try values.decodeIfPresent(String.self, forKey: .warning)
        media = try values.decode(TravelMedia.self, forKey: .media)
        source = try values.decode(TravelSource.self, forKey: .source)
        verifiedAt = try values.decodeISO8601Date(forKey: .verifiedAt)
    }

    init(
        id: String,
        name: String,
        location: GeoPoint,
        address: String,
        phone: String? = nil,
        email: String? = nil,
        websiteURL: URL,
        supportsCaravan: Bool,
        hasElectricity: Bool? = nil,
        maximumLengthMeters: Double? = nil,
        recommendation: String,
        warning: String? = nil,
        media: TravelMedia,
        source: TravelSource,
        verifiedAt: Date
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.address = address
        self.phone = phone
        self.email = email
        self.websiteURL = websiteURL
        self.supportsCaravan = supportsCaravan
        self.hasElectricity = hasElectricity
        self.maximumLengthMeters = maximumLengthMeters
        self.recommendation = recommendation
        self.warning = warning
        self.media = media
        self.source = source
        self.verifiedAt = verifiedAt
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(location, forKey: .location)
        try values.encode(address, forKey: .address)
        try values.encodeIfPresent(phone, forKey: .phone)
        try values.encodeIfPresent(email, forKey: .email)
        try values.encode(websiteURL, forKey: .websiteURL)
        try values.encode(supportsCaravan, forKey: .supportsCaravan)
        try values.encodeIfPresent(hasElectricity, forKey: .hasElectricity)
        try values.encodeIfPresent(maximumLengthMeters, forKey: .maximumLengthMeters)
        try values.encode(recommendation, forKey: .recommendation)
        try values.encodeIfPresent(warning, forKey: .warning)
        try values.encode(media, forKey: .media)
        try values.encode(source, forKey: .source)
        try values.encodeISO8601Date(verifiedAt, forKey: .verifiedAt)
    }
}

struct NearbyAttraction: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let location: GeoPoint
    let address: String
    let category: String
    let visitDurationMinutes: Int
    let recommendation: String
    let media: TravelMedia
    let source: TravelSource
    let verifiedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, name, location, address, category, visitDurationMinutes, recommendation, media, source, verifiedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        location = try values.decode(GeoPoint.self, forKey: .location)
        address = try values.decode(String.self, forKey: .address)
        category = try values.decode(String.self, forKey: .category)
        visitDurationMinutes = try values.decode(Int.self, forKey: .visitDurationMinutes)
        recommendation = try values.decode(String.self, forKey: .recommendation)
        media = try values.decode(TravelMedia.self, forKey: .media)
        source = try values.decode(TravelSource.self, forKey: .source)
        verifiedAt = try values.decodeISO8601Date(forKey: .verifiedAt)
    }

    init(
        id: String,
        name: String,
        location: GeoPoint,
        address: String,
        category: String,
        visitDurationMinutes: Int,
        recommendation: String,
        media: TravelMedia,
        source: TravelSource,
        verifiedAt: Date
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.address = address
        self.category = category
        self.visitDurationMinutes = visitDurationMinutes
        self.recommendation = recommendation
        self.media = media
        self.source = source
        self.verifiedAt = verifiedAt
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(location, forKey: .location)
        try values.encode(address, forKey: .address)
        try values.encode(category, forKey: .category)
        try values.encode(visitDurationMinutes, forKey: .visitDurationMinutes)
        try values.encode(recommendation, forKey: .recommendation)
        try values.encode(media, forKey: .media)
        try values.encode(source, forKey: .source)
        try values.encodeISO8601Date(verifiedAt, forKey: .verifiedAt)
    }
}

struct TravelDestinationContent: Codable, Hashable {
    let cityName: String
    let policy: CampDistancePolicy
    let camps: [CuratedCamp]
    let attractions: [NearbyAttraction]
}

struct TravelContentBundle: Codable, Hashable {
    let version: Int
    let generatedAt: Date
    let destinations: [String: TravelDestinationContent]

    private enum CodingKeys: String, CodingKey {
        case version, generatedAt, destinations
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        generatedAt = try values.decodeISO8601Date(forKey: .generatedAt)
        destinations = Self.normalizedDestinations(try values.decode([String: TravelDestinationContent].self, forKey: .destinations))
    }

    init(version: Int, generatedAt: Date, destinations: [String: TravelDestinationContent]) {
        self.version = version
        self.generatedAt = generatedAt
        self.destinations = Self.normalizedDestinations(destinations)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        try values.encodeISO8601Date(generatedAt, forKey: .generatedAt)
        try values.encode(destinations, forKey: .destinations)
    }

    func content(forDestination destination: String) -> TravelDestinationContent? {
        destinations[DestinationKey.resolve(destination)]
    }

    private static func normalizedDestinations(
        _ destinations: [String: TravelDestinationContent]
    ) -> [String: TravelDestinationContent] {
        destinations.reduce(into: [:]) { normalized, destination in
            normalized[DestinationKey.resolve(destination.key)] = destination.value
        }
    }
}

enum ContentFreshness {
    static func requiresReverification(verifiedAt: Date, on now: Date = Date(), calendar: Calendar = .current) -> Bool {
        (calendar.dateComponents([.day], from: verifiedAt, to: now).day ?? 0) > 90
    }
}

enum DestinationKey {
    static func resolve(_ destination: String) -> String {
        destination
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "ı", with: "i")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
    }
}

private extension Double {
    var radians: Double { self * .pi / 180 }
}

private extension KeyedDecodingContainer {
    func decodeISO8601Date(forKey key: Key) throws -> Date {
        let value = try decode(String.self, forKey: key)
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected an ISO 8601 date")
        }
        return date
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeISO8601Date(_ date: Date, forKey key: Key) throws {
        try encode(ISO8601DateFormatter().string(from: date), forKey: key)
    }
}
