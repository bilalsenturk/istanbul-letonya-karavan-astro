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
    var maximumLengthMeters: Double?
    var source: ArrivalTargetSource
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, mapItemIdentifier, name, kind, latitude, longitude, formattedAddress
        case phone, whatsAppPhone, email, websiteURL, maximumLengthMeters, source, updatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        mapItemIdentifier = try values.decodeIfPresent(String.self, forKey: .mapItemIdentifier)
        name = try values.decode(String.self, forKey: .name)
        kind = try values.decode(ArrivalTargetKind.self, forKey: .kind)
        latitude = try values.decode(Double.self, forKey: .latitude)
        longitude = try values.decode(Double.self, forKey: .longitude)
        formattedAddress = try values.decode(String.self, forKey: .formattedAddress)
        phone = try values.decodeIfPresent(String.self, forKey: .phone)
        whatsAppPhone = try values.decodeIfPresent(String.self, forKey: .whatsAppPhone)
        email = try values.decodeIfPresent(String.self, forKey: .email)
        websiteURL = try values.decodeIfPresent(URL.self, forKey: .websiteURL)
        maximumLengthMeters = try values.decodeIfPresent(Double.self, forKey: .maximumLengthMeters)
        source = try values.decodeIfPresent(ArrivalTargetSource.self, forKey: .source) ?? .migrated
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }

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
        maximumLengthMeters: Double? = nil,
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
        self.maximumLengthMeters = maximumLengthMeters
        self.source = source
        self.updatedAt = updatedAt
    }

    var hasValidCoordinate: Bool {
        latitude.isFinite && longitude.isFinite
            && abs(latitude) <= 90 && abs(longitude) <= 180
    }

    var publicSummary: ArrivalTarget {
        var value = self
        value.phone = nil
        value.whatsAppPhone = nil
        value.email = nil
        value.websiteURL = nil
        return value
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
    var estimatedArrivalMode: StayEstimatedArrivalMode
    var estimatedArrivalWindow: StayETAWindow?
    var lastContactedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case checkIn, checkOut, reservationStatus, reservationReference, note, estimatedArrival
        case estimatedArrivalMode, estimatedArrivalWindow, lastContactedAt
    }

    init(
        checkIn: Date? = nil,
        checkOut: Date? = nil,
        reservationStatus: StayReservationStatus = .notContacted,
        reservationReference: String? = nil,
        note: String? = nil,
        estimatedArrival: String? = nil,
        estimatedArrivalMode: StayEstimatedArrivalMode? = nil,
        estimatedArrivalWindow: StayETAWindow? = nil,
        lastContactedAt: Date? = nil
    ) {
        self.checkIn = checkIn
        self.checkOut = checkOut
        self.reservationStatus = reservationStatus
        self.reservationReference = reservationReference
        self.note = note
        self.estimatedArrival = estimatedArrival
        self.estimatedArrivalMode = estimatedArrivalMode ?? (estimatedArrival == nil ? .automatic : .manual)
        self.estimatedArrivalWindow = estimatedArrivalWindow
        self.lastContactedAt = lastContactedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        checkIn = try values.decodeIfPresent(Date.self, forKey: .checkIn)
        checkOut = try values.decodeIfPresent(Date.self, forKey: .checkOut)
        reservationStatus = try values.decodeIfPresent(StayReservationStatus.self, forKey: .reservationStatus) ?? .notContacted
        reservationReference = try values.decodeIfPresent(String.self, forKey: .reservationReference)
        note = try values.decodeIfPresent(String.self, forKey: .note)
        estimatedArrival = try values.decodeIfPresent(String.self, forKey: .estimatedArrival)
        estimatedArrivalWindow = try values.decodeIfPresent(StayETAWindow.self, forKey: .estimatedArrivalWindow)
        estimatedArrivalMode = try values.decodeIfPresent(StayEstimatedArrivalMode.self, forKey: .estimatedArrivalMode)
            ?? (estimatedArrival == nil ? .automatic : .manual)
        lastContactedAt = try values.decodeIfPresent(Date.self, forKey: .lastContactedAt)
    }
}

enum StayEstimatedArrivalMode: String, Codable, Equatable, Hashable {
    case automatic
    case manual
}

struct StayETAInput {
    static let maximumWaypointMinutes = 10_080
    let departure: Date
    let drivingSeconds: TimeInterval
    let waypointMinutes: Int
    let borderBufferMinutes: Int
    let calendar: Calendar

    init(
        departure: Date,
        drivingSeconds: TimeInterval,
        waypointMinutes: Int = 0,
        borderBufferMinutes: Int = 0,
        calendar: Calendar = .current
    ) {
        self.departure = departure
        self.drivingSeconds = max(0, drivingSeconds)
        self.waypointMinutes = max(0, waypointMinutes)
        self.borderBufferMinutes = max(0, borderBufferMinutes)
        self.calendar = calendar
    }

    static func boundedWaypointMinutes(_ minutes: [Int]) -> Int {
        minutes.reduce(0) { total, value in
            min(maximumWaypointMinutes, total + min(max(0, value), maximumWaypointMinutes))
        }
    }
}

struct StayETAWindow: Codable, Equatable, Hashable {
    let start: Date
    let end: Date
    let timeZoneIdentifier: String

    init(start: Date, end: Date, timeZoneIdentifier: String = TimeZone.current.identifier) {
        self.start = start
        self.end = end
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    var text: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        let startText = formatter.string(from: start)
        let endText = formatter.string(from: end)
        if calendar.timeZone.secondsFromGMT(for: start) != calendar.timeZone.secondsFromGMT(for: end)
            || startText == endText {
            formatter.dateFormat = "HH:mm zzz"
            return "\(formatter.string(from: start))–\(formatter.string(from: end))"
        }
        return "\(startText)–\(endText)"
    }
}

enum StayETACalculator {
    /// Round the absolute arrival instant to its nearest half-hour (15-minute ties up),
    /// then communicate the half-hour on either side as one durable hour.
    static func calculate(_ input: StayETAInput) -> StayETAWindow {
        let maximumExtraSeconds: TimeInterval = 7 * 24 * 60 * 60
        let waypointSeconds = min(TimeInterval(input.waypointMinutes) * 60, maximumExtraSeconds)
        let borderSeconds = min(TimeInterval(input.borderBufferMinutes) * 60, maximumExtraSeconds)
        let center = input.departure.addingTimeInterval(
            min(input.drivingSeconds + waypointSeconds + borderSeconds, maximumExtraSeconds * 2)
        )
        let rounded = (center.timeIntervalSinceReferenceDate / 1_800).rounded(.toNearestOrAwayFromZero) * 1_800
        let start = Date(timeIntervalSinceReferenceDate: rounded - 1_800)
        let end = Date(timeIntervalSinceReferenceDate: rounded + 1_800)
        return StayETAWindow(start: start, end: end, timeZoneIdentifier: input.calendar.timeZone.identifier)
    }
}

enum StayArrivalModeResolver {
    static func applyingAutomaticDefault(_ window: StayETAWindow?, to stay: StayDetails) -> StayDetails {
        guard stay.estimatedArrivalMode == .automatic else { return stay }
        return useAutomatic(window, replacing: stay)
    }

    static func useAutomatic(_ window: StayETAWindow?, replacing stay: StayDetails) -> StayDetails {
        var result = stay
        result.estimatedArrivalMode = .automatic
        result.estimatedArrivalWindow = window
        result.estimatedArrival = window?.text
        return result
    }
}

struct StayCamp: Equatable, Hashable {
    let maximumLengthMeters: Double?

    init(maximumLengthMeters: Double? = nil) {
        self.maximumLengthMeters = maximumLengthMeters
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
    var contactEmail: String?
    var adults: Int
    var children: Int
    var vehicleDescription: String
    var totalLengthMeters: Double?
    var needsElectricity: Bool
    var hasPet: Bool
    var additionalNeeds: String
    var preferredLanguage: StayMessageLanguage
    var updatedAt: String?

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
        updatedAt: String? = nil
    ) {
        self.contactName = contactName
        self.contactEmail = contactEmail
        self.adults = max(0, adults)
        self.children = max(0, children)
        self.vehicleDescription = vehicleDescription
        self.totalLengthMeters = totalLengthMeters
        self.needsElectricity = needsElectricity
        self.hasPet = hasPet
        self.additionalNeeds = additionalNeeds
        self.preferredLanguage = preferredLanguage
        self.updatedAt = updatedAt
    }
}

struct StayMessage: Equatable {
    let subject: String
    let body: String
}

/// The exact values handed to a system composer or an external messaging app.
/// This is deliberately Foundation-only so recipient validation remains testable
/// without attempting to open an app or inspect a user's accounts.
struct PreparedContactAction: Equatable {
    let channel: StayContactAction
    let recipient: String
    let subject: String?
    let body: String

    var clipboardText: String { body }
}

enum StayContactAction: String, CaseIterable, Equatable {
    case whatsApp
    case messages
    case email

    func prepare(message: StayMessage, target: ArrivalTarget) -> PreparedContactAction? {
        switch self {
        case .email:
            guard let recipient = ContactLinkBuilder.normalizedEmail(target.email) else { return nil }
            return PreparedContactAction(channel: self, recipient: recipient, subject: message.subject, body: message.body)
        case .messages:
            guard let recipient = Self.normalizedMessageRecipient(target.phone) else { return nil }
            return PreparedContactAction(channel: self, recipient: recipient, subject: nil, body: message.body)
        case .whatsApp:
            guard let recipient = ContactLinkBuilder.normalizedWhatsAppPhone(target.whatsAppPhone ?? target.phone) else { return nil }
            return PreparedContactAction(channel: self, recipient: recipient, subject: nil, body: message.body)
        }
    }

    private static func normalizedMessageRecipient(_ phone: String?) -> String? {
        guard let phone else { return nil }
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter(\.isNumber)
        guard (3 ... 15).contains(digits.count) else { return nil }
        return trimmed.hasPrefix("+") ? "+\(digits)" : digits
    }
}

enum StayContactComposerResult: Equatable {
    case sent
    case cancelled
    case failed
}

enum StayContactFollowUp {
    static func shouldOfferAwaitingReply(after result: StayContactComposerResult) -> Bool {
        result == .sent
    }

    static func shouldMarkAwaitingReply(userConfirmed: Bool) -> Bool {
        userConfirmed
    }
}

enum WhatsAppHandoffEffect: Equatable {
    case none
    case showUnavailable
    case offerAwaitingReply
}

struct WhatsAppHandoffState: Equatable {
    private var actionID: UUID?
    private var opened = false
    private var didLeave = false
    private var isActive = true
    private var terminal = false

    mutating func begin(actionID: UUID) {
        self.actionID = actionID
        opened = false
        didLeave = false
        isActive = true
        terminal = false
    }

    mutating func openCompleted(actionID: UUID, opened: Bool) -> WhatsAppHandoffEffect {
        guard self.actionID == actionID, !terminal else { return .none }
        guard opened else {
            terminal = true
            return .showUnavailable
        }
        self.opened = true
        return consumePromptIfReady()
    }

    mutating func becameInactive() -> WhatsAppHandoffEffect {
        guard actionID != nil, !terminal else { return .none }
        didLeave = true
        isActive = false
        return .none
    }

    mutating func becameActive() -> WhatsAppHandoffEffect {
        guard actionID != nil, !terminal else { return .none }
        isActive = true
        return consumePromptIfReady()
    }

    private mutating func consumePromptIfReady() -> WhatsAppHandoffEffect {
        guard opened, didLeave, isActive, !terminal else { return .none }
        terminal = true
        return .offerAwaitingReply
    }
}

enum ArrivalTargetRequirement {
    static func canStart(isRestDay: Bool, target: ArrivalTarget?) -> Bool {
        isRestDay || target?.hasValidCoordinate == true
    }
}

enum CuratedCampSelectionEligibility {
    static let unsupportedWarning = "Bu kamp çekme karavan kabul etmiyor; varış yeri olarak seçilemez."

    static func canSelect(supportsCaravan: Bool, canEditStops: Bool) -> Bool {
        supportsCaravan && canEditStops
    }
}

struct ArrivalTargetSyncContext: Equatable {
    let revision: Int
    let tripID: String
    let userID: String

    func isCurrent(revision: Int, tripID: String?, userID: String?) -> Bool {
        self.revision == revision && self.tripID == tripID && self.userID == userID
    }
}

enum RouteStartPolicy {
    static func canStart(
        isRestDay: Bool,
        target: ArrivalTarget?,
        stepState: RouteStepState
    ) -> Bool {
        !isRestDay && stepState == .available
            && ArrivalTargetRequirement.canStart(isRestDay: false, target: target)
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
        profile: StayContactProfile,
        transportMode: RouteTransportMode = .automobile,
        camp: StayCamp? = nil
    ) -> StayMessage {
        switch profile.preferredLanguage {
        case .english: englishMessage(target: target, stay: stay, profile: profile, transportMode: transportMode, camp: camp)
        case .turkish: turkishMessage(target: target, stay: stay, profile: profile, transportMode: transportMode, camp: camp)
        }
    }

    private static func englishMessage(
        target: ArrivalTarget,
        stay: StayDetails,
        profile: StayContactProfile,
        transportMode: RouteTransportMode,
        camp: StayCamp?
    ) -> StayMessage {
        let dates = dateRange(stay)
        let guests = englishGuests(profile)
        var lines = ["Hello,"]
        lines.append("")
        lines.append("I would like to ask about availability at \(target.name) for \(dates.longText).")
        if !guests.isEmpty { lines.append("We are \(guests).") }
        if transportMode == .automobile,
           !profile.vehicleDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var vehicle = "We travel with \(profile.vehicleDescription.trimmingCharacters(in: .whitespacesAndNewlines))"
            if let length = profile.totalLengthMeters, length > 0 {
                vehicle += String(format: " (%.1f m total length)", length)
            }
            lines.append(vehicle + ".")
        }
        if transportMode == .automobile, profile.needsElectricity { lines.append("We need an electricity connection.") }
        if transportMode == .automobile, let maximum = camp?.maximumLengthMeters,
           let length = profile.totalLengthMeters,
           length > maximum {
            lines.append(String(format: "Our %.1f m total length exceeds your stated %.1f m limit; could you please confirm that it can be accommodated?", length, maximum))
        }
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
        profile: StayContactProfile,
        transportMode: RouteTransportMode,
        camp: StayCamp?
    ) -> StayMessage {
        let dates = dateRange(stay)
        var lines = ["Merhaba,", "", "\(target.name) için \(dates.longText) tarihleri arasındaki uygunluğu öğrenmek istiyorum."]
        let guests = turkishGuests(profile)
        if !guests.isEmpty { lines.append("\(guests) olarak seyahat ediyoruz.") }
        if transportMode == .automobile, !profile.vehicleDescription.isEmpty { lines.append("Aracımız: \(profile.vehicleDescription).") }
        if transportMode == .automobile, profile.needsElectricity { lines.append("Elektrik bağlantısına ihtiyacımız var.") }
        if transportMode == .automobile, let maximum = camp?.maximumLengthMeters,
           let length = profile.totalLengthMeters,
           length > maximum {
            lines.append(String(format: "Toplam %.1f m uzunluğumuz belirtilen %.1f m sınırını aşıyor; uygunluğu teyit edebilir misiniz?", length, maximum))
        }
        if profile.hasPet { lines.append("Evcil hayvanımızla seyahat ediyoruz.") }
        let needs = profile.additionalNeeds.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needs.isEmpty { lines.append("Ek not: \(needs)") }
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

    private static func turkishGuests(_ profile: StayContactProfile) -> String {
        var parts: [String] = []
        if profile.adults > 0 { parts.append("\(profile.adults) yetişkin") }
        if profile.children > 0 { parts.append("\(profile.children) çocuk") }
        return parts.joined(separator: " ve ")
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
        guard let normalized = normalizedWhatsAppPhone(phone) else { return nil }
        var components = URLComponents()
        components.scheme = "whatsapp"
        components.host = "send"
        components.queryItems = [
            URLQueryItem(name: "phone", value: normalized),
            URLQueryItem(name: "text", value: message),
        ]
        return components.url
    }

    static func emailURL(email: String?, subject: String, body: String) -> URL? {
        guard let email = normalizedEmail(email) else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }

    static func normalizedEmail(_ email: String?) -> String? {
        guard let email = email?.trimmingCharacters(in: .whitespacesAndNewlines),
              email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
        else { return nil }
        return email
    }

    static func normalizedWhatsAppPhone(_ phone: String?) -> String? {
        guard let phone else { return nil }
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        var remainder = trimmed
        if trimmed.hasPrefix("+") {
            remainder.removeFirst()
        } else if trimmed.hasPrefix("00") {
            remainder.removeFirst(2)
        }
        let separators = CharacterSet(charactersIn: " -()")
        guard remainder.unicodeScalars.allSatisfy({ scalar in
            (scalar.value >= 48 && scalar.value <= 57) || separators.contains(scalar)
        }) else { return nil }
        let normalized = remainder.filter { $0.isASCII && $0.isNumber }
        guard normalized.range(of: #"^[1-9][0-9]{7,14}$"#, options: .regularExpression) != nil else { return nil }
        return normalized
    }
}
