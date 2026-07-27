import CoreLocation
import MapKit
import SwiftUI

private enum PlacePickerMode {
    case search
    case map
}

struct PlacePickerView: View {
    @EnvironmentObject private var location: LocationManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = PlaceSearchService()
    @State private var mode: PlacePickerMode = .search
    @State private var position: MapCameraPosition = .automatic
    @State private var region: MKCoordinateRegion?
    @State private var errorMessage: String?
    @State private var waitingForCurrentLocation = false
    @State private var recents = RecentPlaces.load()

    let title: String
    let allowsCurrentLocation: Bool
    let transportMode: RouteTransportMode
    let dismissAfterSelection: Bool
    let onSelect: (RouteDraftStop) -> Void

    init(
        title: String = "Durak seç",
        allowsCurrentLocation: Bool = true,
        transportMode: RouteTransportMode = .automobile,
        dismissAfterSelection: Bool = true,
        onSelect: @escaping (RouteDraftStop) -> Void
    ) {
        self.title = title
        self.allowsCurrentLocation = allowsCurrentLocation
        self.transportMode = transportMode
        self.dismissAfterSelection = dismissAfterSelection
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .search: searchableContent
                case .map: mapSelectionContent
                }
            }
            .background(Theme.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
        }
        .onAppear(perform: prepare)
        .onChange(of: location.location) { _, newLocation in
            guard waitingForCurrentLocation, let coordinate = newLocation?.coordinate else { return }
            waitingForCurrentLocation = false
            select(.currentLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), remember: false)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private var searchContent: some View {
        VStack(spacing: 0) {
            mapPreview
            List {
                Section {
                    if allowsCurrentLocation { currentLocationRow }
                    Button { mode = .map } label: {
                        optionRow(
                            icon: "mappin.and.ellipse",
                            title: "Haritada seç",
                            subtitle: "İğneyi tam konuma taşı",
                            tint: Theme.c2
                        )
                    }
                    .accessibilityIdentifier("route-picker-map-selection")
                }

                Section("Hızlı arama") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 18) {
                            ForEach(quickSearches) { item in
                                Button {
                                    search.query = item.query
                                    Task { await searchAll() }
                                } label: {
                                    VStack(spacing: 7) {
                                        Image(systemName: item.symbol)
                                            .font(.system(size: 18, weight: .semibold))
                                            .frame(width: 40, height: 40)
                                            .background(Theme.bg, in: Circle())
                                        Text(item.title)
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(Theme.text)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                }

                if !search.suggestions.isEmpty {
                    Section("Arama sonuçları") {
                        ForEach(search.suggestions) { suggestion in
                            Button { Task { await select(suggestion) } } label: {
                                optionRow(
                                    icon: "mappin.circle.fill",
                                    title: suggestion.title,
                                    subtitle: suggestion.subtitle,
                                    tint: Theme.c2
                                )
                            }
                        }
                    }
                } else if search.query.isEmpty && !recents.isEmpty {
                    Section("Son kullanılanlar") {
                        ForEach(recents) { stop in
                            Button { select(stop) } label: {
                                optionRow(
                                    icon: "clock.fill",
                                    title: stop.name,
                                    subtitle: coordinateText(stop),
                                    tint: Theme.muted
                                )
                            }
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Theme.warn)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var searchableContent: some View {
        searchContent
            .searchable(
                text: $search.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Yer, işletme veya adres ara"
            )
            .onSubmit(of: .search) { Task { await searchAll() } }
            .accessibilityIdentifier("route-place-search")
    }

    private var mapPreview: some View {
        Map(position: $position) {
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapCompass()
            MapScaleView()
            MapUserLocationButton()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            region = context.region
            search.update(region: context.region)
        }
        .frame(height: 170)
    }

    private var currentLocationRow: some View {
        Button(action: useCurrentLocation) {
            optionRow(
                icon: "location.fill",
                title: "Konumum",
                subtitle: currentLocationSubtitle,
                tint: .blue,
                showsProgress: waitingForCurrentLocation
            )
        }
        .accessibilityIdentifier("route-picker-current-location")
    }

    private var mapSelectionContent: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position) {
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
                MapUserLocationButton()
                MapPitchToggle()
            }
            .onMapCameraChange(frequency: .continuous) { context in region = context.region }
            .ignoresSafeArea(edges: .bottom)

            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Theme.c2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(Theme.c2, .white)
                .offset(y: -20)
                .allowsHitTesting(false)

            VStack(spacing: 10) {
                Text("Haritayı taşıyarak konumu iğnenin altına getirin.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                Button {
                    guard let center = region?.center else { return }
                    select(RouteDraftStop(
                        id: UUID().uuidString,
                        name: "Haritada seçilen konum",
                        lat: center.latitude,
                        lng: center.longitude
                    ))
                } label: {
                    Label("Bu konumu kullan", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.c2)
                .disabled(region == nil)
            }
            .padding(16)
            .background(.ultraThickMaterial)
        }
    }

    private func optionRow(
        icon: String,
        title: String,
        subtitle: String,
        tint: Color,
        showsProgress: Bool = false
    ) -> some View {
        HStack(spacing: 13) {
            ZStack {
                Circle().fill(tint.opacity(0.14)).frame(width: 38, height: 38)
                if showsProgress { ProgressView().controlSize(.small) }
                else { Image(systemName: icon).foregroundStyle(tint) }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.muted)
        }
        .contentShape(Rectangle())
    }

    private var currentLocationSubtitle: String {
        if location.location != nil { return "Cihazın güncel GPS konumu" }
        switch location.status {
        case .denied, .restricted: return "Konum izni gerekli"
        default: return "GPS konumu alınıyor"
        }
    }

    private var quickSearches: [QuickPlaceSearch] {
        if transportMode == .flight {
            return [
                QuickPlaceSearch(id: "airport", title: "Havalimanı", symbol: "airplane", query: "havalimanı"),
                QuickPlaceSearch(id: "hotel", title: "Otel", symbol: "bed.double.fill", query: "otel"),
                QuickPlaceSearch(id: "parking", title: "Otopark", symbol: "parkingsign.circle.fill", query: "otopark")
            ]
        }
        return [
            QuickPlaceSearch(id: "fuel", title: "Yakıt", symbol: "fuelpump.fill", query: "benzin istasyonu"),
            QuickPlaceSearch(id: "food", title: "Yemek", symbol: "fork.knife", query: "restoran"),
            QuickPlaceSearch(id: "hotel", title: "Konaklama", symbol: "bed.double.fill", query: "otel"),
            QuickPlaceSearch(id: "parking", title: "Otopark", symbol: "parkingsign.circle.fill", query: "otopark")
        ]
    }

    private func useCurrentLocation() {
        if let coordinate = location.location?.coordinate {
            select(.currentLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), remember: false)
        } else {
            waitingForCurrentLocation = true
            location.request()
        }
    }

    private func prepare() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-preview-add-stop") {
            let istanbul = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 41.05, longitude: 29.02),
                span: MKCoordinateSpan(latitudeDelta: 0.45, longitudeDelta: 0.45)
            )
            position = .region(istanbul)
            region = istanbul
            search.update(region: istanbul)
            return
        }
        #endif
        if let coordinate = location.location?.coordinate {
            let initial = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
            )
            position = .region(initial)
            region = initial
            search.update(region: initial)
        }
    }

    private func searchAll() async {
        do {
            try await search.search(region: region)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func select(_ suggestion: PlaceSuggestion) async {
        do {
            select(try await search.resolve(suggestion))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func select(_ stop: RouteDraftStop, remember: Bool = true) {
        if remember {
            RecentPlaces.remember(stop)
            recents = RecentPlaces.load()
        }
        onSelect(stop)
        if dismissAfterSelection { dismiss() }
    }

    private func coordinateText(_ stop: RouteDraftStop) -> String {
        String(format: "%.4f, %.4f", stop.lat, stop.lng)
    }
}

private struct QuickPlaceSearch: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let query: String
}

private enum RecentPlaces {
    private static let key = "route-place-recents-v1"

    static func load() -> [RouteDraftStop] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stops = try? JSONDecoder().decode([RouteDraftStop].self, from: data)
        else { return [] }
        return stops
    }

    static func remember(_ stop: RouteDraftStop) {
        var values = load().filter { item in
            item.name != stop.name || abs(item.lat - stop.lat) > 0.00001 || abs(item.lng - stop.lng) > 0.00001
        }
        values.insert(stop, at: 0)
        values = Array(values.prefix(6))
        if let data = try? JSONEncoder().encode(values) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
