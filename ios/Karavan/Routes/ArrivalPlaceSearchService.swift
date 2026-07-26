import MapKit

enum ArrivalSearchCategory: String, CaseIterable, Identifiable {
    case campground
    case hotel
    case caravanPark
    case parking
    case address

    var id: String { rawValue }

    var title: String {
        switch self {
        case .campground: "Kamp"
        case .hotel: "Otel"
        case .caravanPark: "Karavan"
        case .parking: "Otopark"
        case .address: "Adres"
        }
    }

    var symbol: String {
        switch self {
        case .campground: "tent.fill"
        case .hotel: "bed.double.fill"
        case .caravanPark: "caravan.fill"
        case .parking: "parkingsign.circle.fill"
        case .address: "mappin.and.ellipse"
        }
    }

    var query: String {
        switch self {
        case .campground: "camping campground"
        case .hotel: "hotel"
        case .caravanPark: "caravan park RV park"
        case .parking: "parking"
        case .address: ""
        }
    }

    var targetKind: ArrivalTargetKind {
        switch self {
        case .campground: .campground
        case .hotel: .hotel
        case .caravanPark: .caravanPark
        case .parking: .parking
        case .address: .address
        }
    }
}

struct ArrivalPlaceSuggestion: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

@MainActor
final class ArrivalPlaceSearchService: NSObject, ObservableObject {
    @Published var query = "" {
        didSet {
            guard !isShowingResolvedResults else { return }
            completer.queryFragment = query
        }
    }
    @Published private(set) var suggestions: [ArrivalPlaceSuggestion] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let completer = MKLocalSearchCompleter()
    private var completions: [String: MKLocalSearchCompletion] = [:]
    private var resolvedItems: [String: MKMapItem] = [:]
    private var category: ArrivalSearchCategory = .campground
    private var region: MKCoordinateRegion?
    private var isShowingResolvedResults = false

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(region: MKCoordinateRegion) {
        self.region = region
        completer.region = region
    }

    func search(category: ArrivalSearchCategory, region: MKCoordinateRegion? = nil) async {
        self.category = category
        if let region { update(region: region) }
        if category == .address {
            query = ""
            suggestions = []
            errorMessage = nil
            return
        }
        query = category.query
        await submit()
    }

    func submit() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.address, .pointOfInterest]
        if let region { request.region = region }
        if category == .campground || category == .caravanPark {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.campground])
        } else if category == .hotel {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.hotel])
        } else if category == .parking {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.parking])
        }

        do {
            let response = try await MKLocalSearch(request: request).start()
            show(items: Array(response.mapItems.prefix(20)))
            if suggestions.isEmpty { errorMessage = "Bu bölgede sonuç bulunamadı." }
        } catch {
            suggestions = []
            resolvedItems = [:]
            errorMessage = "Apple Maps sonuçları alınamadı."
        }
    }

    func resolve(_ suggestion: ArrivalPlaceSuggestion) async throws -> ArrivalTarget {
        isLoading = true
        defer { isLoading = false }
        if let item = resolvedItems[suggestion.id] { return snapshot(item, id: suggestion.id).makeTarget() }
        guard let completion = completions[suggestion.id] else { throw ArrivalSearchError.notFound }
        let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
        guard let item = response.mapItems.first else { throw ArrivalSearchError.notFound }
        return snapshot(item, id: suggestion.id).makeTarget()
    }

    func clear() {
        isShowingResolvedResults = false
        query = ""
        suggestions = []
        completions = [:]
        resolvedItems = [:]
        errorMessage = nil
    }

    private func show(items: [MKMapItem]) {
        isShowingResolvedResults = true
        completions = [:]
        resolvedItems = [:]
        suggestions = items.enumerated().map { index, item in
            let coordinate = item.placemark.coordinate
            let id = "map-\(index)-\(coordinate.latitude)-\(coordinate.longitude)"
            resolvedItems[id] = item
            return ArrivalPlaceSuggestion(
                id: id,
                title: item.name ?? "Adsız yer",
                subtitle: formattedAddress(item.placemark)
            )
        }
    }

    private func snapshot(_ item: MKMapItem, id: String) -> ArrivalPlaceSnapshot {
        ArrivalPlaceSnapshot(
            id: id,
            name: item.name ?? "Seçilen yer",
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude,
            formattedAddress: formattedAddress(item.placemark),
            phone: item.phoneNumber,
            websiteURL: item.url,
            kind: inferredKind(item)
        )
    }

    private func inferredKind(_ item: MKMapItem) -> ArrivalTargetKind {
        switch item.pointOfInterestCategory {
        case .campground: category == .caravanPark ? .caravanPark : .campground
        case .hotel: .hotel
        case .parking: .parking
        default: category.targetKind
        }
    }

    private func formattedAddress(_ placemark: MKPlacemark) -> String {
        let parts = [
            [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " "),
            placemark.postalCode,
            placemark.locality,
            placemark.administrativeArea,
            placemark.country,
        ].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return parts.isEmpty ? (placemark.title ?? "Adres bilgisi yok") : parts.joined(separator: ", ")
    }
}

extension ArrivalPlaceSearchService: @preconcurrency MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        isShowingResolvedResults = false
        resolvedItems = [:]
        completions = [:]
        suggestions = completer.results.prefix(12).enumerated().map { index, completion in
            let id = "completion-\(index)-\(completion.title)-\(completion.subtitle)"
            completions[id] = completion
            return ArrivalPlaceSuggestion(id: id, title: completion.title, subtitle: completion.subtitle)
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
        errorMessage = "Apple Maps araması tamamlanamadı."
    }
}

private enum ArrivalSearchError: LocalizedError {
    case notFound
    var errorDescription: String? { "Seçilen yer Apple Maps'te bulunamadı." }
}
