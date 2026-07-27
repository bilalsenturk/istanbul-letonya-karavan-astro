import MapKit

struct PlaceSuggestion: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D?

    static func == (lhs: PlaceSuggestion, rhs: PlaceSuggestion) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
final class PlaceSearchService: NSObject, ObservableObject {
    @Published var query = "" {
        didSet {
            showingSearchResults = false
            completer.queryFragment = query
        }
    }
    @Published private(set) var suggestions: [PlaceSuggestion] = []
    @Published private(set) var isResolving = false

    private let completer = MKLocalSearchCompleter()
    private var completions: [String: MKLocalSearchCompletion] = [:]
    private var showingSearchResults = false

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(region: MKCoordinateRegion) {
        completer.region = region
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard !showingSearchResults else { return }
        completions = [:]
        suggestions = completer.results.prefix(10).enumerated().map { index, completion in
            let id = "completion-\(index)-\(completion.title)-\(completion.subtitle)"
            completions[id] = completion
            return PlaceSuggestion(id: id, title: completion.title, subtitle: completion.subtitle, coordinate: nil)
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        guard !showingSearchResults else { return }
        suggestions = []
    }

    func resolve(_ suggestion: PlaceSuggestion) async throws -> RouteDraftStop {
        isResolving = true
        defer { isResolving = false }
        if let coordinate = suggestion.coordinate {
            return RouteDraftStop(id: UUID().uuidString, name: suggestion.title, lat: coordinate.latitude, lng: coordinate.longitude)
        }
        guard let completion = completions[suggestion.id] else { throw PlaceSearchError.notFound }
        let request = MKLocalSearch.Request(completion: completion)
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else { throw PlaceSearchError.notFound }
        let coordinate = item.placemark.coordinate
        return RouteDraftStop(
            id: UUID().uuidString,
            name: item.name ?? suggestion.title,
            lat: coordinate.latitude,
            lng: coordinate.longitude
        )
    }

    func search(region: MKCoordinateRegion?) async throws {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isResolving = true
        defer { isResolving = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.address, .pointOfInterest]
        if let region { request.region = region }
        showingSearchResults = true
        let response = try await MKLocalSearch(request: request).start()
        let results = response.mapItems.prefix(12).enumerated().map { index, item in
            let address = [item.placemark.thoroughfare, item.placemark.locality, item.placemark.country]
                .compactMap { $0 }.joined(separator: ", ")
            return PlaceSuggestion(
                id: "result-\(index)-\(item.placemark.coordinate.latitude)-\(item.placemark.coordinate.longitude)",
                title: item.name ?? text,
                subtitle: address,
                coordinate: item.placemark.coordinate
            )
        }
        guard !results.isEmpty else { throw PlaceSearchError.notFound }
        completions = [:]
        suggestions = results
    }

    func clear() {
        query = ""
        showingSearchResults = false
        suggestions = []
        completions = [:]
    }
}

extension PlaceSearchService: @preconcurrency MKLocalSearchCompleterDelegate {}

private enum PlaceSearchError: LocalizedError {
    case notFound
    var errorDescription: String? { "Bu yer haritada bulunamadı." }
}
