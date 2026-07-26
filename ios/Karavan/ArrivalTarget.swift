import Foundation

enum ArrivalTargetKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case campground
    case hotel
    case apartment
    case caravanPark
    case parking
    case address
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .campground: "Kamp"
        case .hotel: "Otel"
        case .apartment: "Apart"
        case .caravanPark: "Karavan parkı"
        case .parking: "Otopark"
        case .address: "Adres"
        case .other: "Diğer"
        }
    }

    var symbol: String {
        switch self {
        case .campground: "tent.fill"
        case .hotel: "bed.double.fill"
        case .apartment: "building.2.fill"
        case .caravanPark: "caravan.fill"
        case .parking: "parkingsign.circle.fill"
        case .address: "mappin.and.ellipse"
        case .other: "location.fill"
        }
    }
}

enum ArrivalTargetSource: String, Codable, Hashable {
    case appleMaps
    case user
    case migrated
}

struct ArrivalTarget: Codable, Equatable, Identifiable, Hashable {
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
    var websiteURL: URL?
    var source: ArrivalTargetSource
    var updatedAt: Date

    init(
        id: String,
        mapItemIdentifier: String? = nil,
        name: String,
        kind: ArrivalTargetKind,
        latitude: Double,
        longitude: Double,
        formattedAddress: String,
        phone: String? = nil,
        whatsAppPhone: String? = nil,
        email: String? = nil,
        websiteURL: URL? = nil,
        source: ArrivalTargetSource = .appleMaps,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.mapItemIdentifier = mapItemIdentifier
        self.name = name
        self.kind = kind
        self.latitude = latitude
        self.longitude = longitude
        self.formattedAddress = formattedAddress
        self.phone = phone
        self.whatsAppPhone = whatsAppPhone
        self.email = email
        self.websiteURL = websiteURL
        self.source = source
        self.updatedAt = updatedAt
    }

    var hasValidCoordinate: Bool {
        latitude.isFinite && longitude.isFinite
            && abs(latitude) <= 90 && abs(longitude) <= 180
    }
}

struct ArrivalPlaceSnapshot: Equatable, Identifiable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let formattedAddress: String
    let phone: String?
    let websiteURL: URL?
    let kind: ArrivalTargetKind
    let mapItemIdentifier: String?

    init(
        id: String,
        name: String,
        latitude: Double,
        longitude: Double,
        formattedAddress: String,
        phone: String? = nil,
        websiteURL: URL? = nil,
        kind: ArrivalTargetKind,
        mapItemIdentifier: String? = nil
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.formattedAddress = formattedAddress
        self.phone = phone
        self.websiteURL = websiteURL
        self.kind = kind
        self.mapItemIdentifier = mapItemIdentifier
    }

    func makeTarget() -> ArrivalTarget {
        ArrivalTarget(
            id: id,
            mapItemIdentifier: mapItemIdentifier,
            name: name,
            kind: kind,
            latitude: latitude,
            longitude: longitude,
            formattedAddress: formattedAddress,
            phone: phone,
            websiteURL: websiteURL,
            source: .appleMaps
        )
    }
}

enum StayReservationStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case notContacted
    case awaitingReply
    case confirmed
    case unavailable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notContacted: "İletişim kurulmadı"
        case .awaitingReply: "Yanıt bekleniyor"
        case .confirmed: "Onaylandı"
        case .unavailable: "Yer yok"
        }
    }
}

struct StayDetails: Codable, Equatable, Hashable {
    var checkIn: Date?
    var checkOut: Date?
    var reservationStatus: StayReservationStatus
    var reservationReference: String?
    var note: String?
    var estimatedArrival: String?
    var lastContactedAt: Date?

    init(
        checkIn: Date? = nil,
        checkOut: Date? = nil,
        reservationStatus: StayReservationStatus = .notContacted,
        reservationReference: String? = nil,
        note: String? = nil,
        estimatedArrival: String? = nil,
        lastContactedAt: Date? = nil
    ) {
        self.checkIn = checkIn
        self.checkOut = checkOut
        self.reservationStatus = reservationStatus
        self.reservationReference = reservationReference
        self.note = note
        self.estimatedArrival = estimatedArrival
        self.lastContactedAt = lastContactedAt
    }
}

enum StayMessageLanguage: String, Codable, CaseIterable, Identifiable {
    case english
    case turkish

    var id: String { rawValue }
    var title: String { self == .english ? "English" : "Türkçe" }
}

struct StayContactProfile: Codable, Equatable {
    var contactName: String
    var adults: Int
    var children: Int
    var vehicleDescription: String
    var totalLengthMeters: Double?
    var needsElectricity: Bool
    var hasPet: Bool
    var additionalNeeds: String
    var preferredLanguage: StayMessageLanguage

    init(
        contactName: String = "",
        adults: Int = 2,
        children: Int = 0,
        vehicleDescription: String = "",
        totalLengthMeters: Double? = nil,
        needsElectricity: Bool = true,
        hasPet: Bool = false,
        additionalNeeds: String = "",
        preferredLanguage: StayMessageLanguage = .english
    ) {
        self.contactName = contactName
        self.adults = max(0, adults)
        self.children = max(0, children)
        self.vehicleDescription = vehicleDescription
        self.totalLengthMeters = totalLengthMeters
        self.needsElectricity = needsElectricity
        self.hasPet = hasPet
        self.additionalNeeds = additionalNeeds
        self.preferredLanguage = preferredLanguage
    }
}

struct StayMessage: Equatable {
    let subject: String
    let body: String
}

enum ArrivalTargetRequirement {
    static func canStart(isRestDay: Bool, target: ArrivalTarget?) -> Bool {
        isRestDay || target?.hasValidCoordinate == true
    }
}

enum StayMessageComposer {
    private static let englishDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter
    }()

    static func compose(
        target: ArrivalTarget,
        stay: StayDetails,
        profile: StayContactProfile
    ) -> StayMessage {
        switch profile.preferredLanguage {
        case .english: englishMessage(target: target, stay: stay, profile: profile)
        case .turkish: turkishMessage(target: target, stay: stay, profile: profile)
        }
    }

    private static func englishMessage(
        target: ArrivalTarget,
        stay: StayDetails,
        profile: StayContactProfile
    ) -> StayMessage {
        let dates = dateRange(stay)
        let guests = englishGuests(profile)
        var lines = ["Hello,"]
        lines.append("")
        lines.append("I would like to ask about availability at \(target.name) for \(dates.longText).")
        if !guests.isEmpty { lines.append("We are \(guests).") }
        if !profile.vehicleDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var vehicle = "We travel with \(profile.vehicleDescription.trimmingCharacters(in: .whitespacesAndNewlines))"
            if let length = profile.totalLengthMeters, length > 0 {
                vehicle += String(format: " (%.1f m total length)", length)
            }
            lines.append(vehicle + ".")
        }
        if profile.needsElectricity { lines.append("We need an electricity connection.") }
        if profile.hasPet { lines.append("We travel with a pet.") }
        if let arrival = stay.estimatedArrival?.trimmingCharacters(in: .whitespacesAndNewlines), !arrival.isEmpty {
            lines.append("Our estimated arrival time is \(arrival).")
        }
        let needs = profile.additionalNeeds.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needs.isEmpty { lines.append("Additional note: \(needs)") }
        lines.append("Could you please confirm availability, total price and check-in instructions?")
        lines.append("")
        lines.append("Thank you" + (profile.contactName.isEmpty ? "." : ",\n\(profile.contactName)"))
        return StayMessage(
            subject: "Stay request · \(target.name) · \(dates.shortText)",
            body: lines.joined(separator: "\n")
        )
    }

    private static func turkishMessage(
        target: ArrivalTarget,
        stay: StayDetails,
        profile: StayContactProfile
    ) -> StayMessage {
        let dates = dateRange(stay)
        var lines = ["Merhaba,", "", "\(target.name) için \(dates.longText) tarihleri arasındaki uygunluğu öğrenmek istiyorum."]
        if !profile.vehicleDescription.isEmpty { lines.append("Aracımız: \(profile.vehicleDescription).") }
        if profile.needsElectricity { lines.append("Elektrik bağlantısına ihtiyacımız var.") }
        if let arrival = stay.estimatedArrival, !arrival.isEmpty { lines.append("Tahmini varış saatimiz \(arrival).") }
        lines.append("Uygunluk, toplam ücret ve giriş bilgisini paylaşabilir misiniz?")
        if !profile.contactName.isEmpty { lines.append("\nTeşekkürler,\n\(profile.contactName)") }
        return StayMessage(
            subject: "Konaklama talebi · \(target.name) · \(dates.shortText)",
            body: lines.joined(separator: "\n")
        )
    }

    private static func englishGuests(_ profile: StayContactProfile) -> String {
        var parts: [String] = []
        if profile.adults > 0 { parts.append("\(profile.adults) " + (profile.adults == 1 ? "adult" : "adults")) }
        if profile.children > 0 { parts.append("\(profile.children) " + (profile.children == 1 ? "child" : "children")) }
        return parts.joined(separator: " and ")
    }

    private static func dateRange(_ stay: StayDetails) -> (longText: String, shortText: String) {
        guard let checkIn = stay.checkIn else { return ("the planned dates", "dates pending") }
        let start = englishDateFormatter.string(from: checkIn)
        guard let checkOut = stay.checkOut else { return (start, start) }
        let end = englishDateFormatter.string(from: checkOut)
        let calendar = Calendar(identifier: .gregorian)
        let startDay = calendar.component(.day, from: checkIn)
        let endDay = calendar.component(.day, from: checkOut)
        let endMonthYear = englishDateFormatter.string(from: checkOut).replacingOccurrences(of: "^\\d+ ", with: "", options: .regularExpression)
        return ("\(start) to \(end)", "\(startDay)–\(endDay) \(endMonthYear)")
    }
}

enum ContactLinkBuilder {
    static func whatsAppURL(phone: String?, message: String) -> URL? {
        guard let normalized = normalizedPhone(phone) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "wa.me"
        components.path = "/\(normalized)"
        components.queryItems = [URLQueryItem(name: "text", value: message)]
        return components.url
    }

    static func emailURL(email: String?, subject: String, body: String) -> URL? {
        guard let email = email?.trimmingCharacters(in: .whitespacesAndNewlines),
              email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
        else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }

    private static func normalizedPhone(_ phone: String?) -> String? {
        guard let phone else { return nil }
        let digits = phone.filter(\.isNumber)
        guard (8 ... 15).contains(digits.count) else { return nil }
        if phone.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("+") {
            return digits
        }
        if digits.hasPrefix("00") { return String(digits.dropFirst(2)) }
        return nil
    }
}
