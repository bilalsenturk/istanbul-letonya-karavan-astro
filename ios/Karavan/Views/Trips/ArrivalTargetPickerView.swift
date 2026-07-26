import MapKit
import SwiftUI

struct ArrivalTargetPickerView: View {
    let cityName: String
    let cityCoordinate: CLLocationCoordinate2D
    let initialSelection: ArrivalTarget?
    let onSelect: (ArrivalTarget) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = ArrivalPlaceSearchService()
    @State private var category: ArrivalSearchCategory = .campground
    @State private var selected: ArrivalTarget?
    @State private var position: MapCameraPosition
    @FocusState private var searchFocused: Bool

    init(
        cityName: String,
        cityCoordinate: CLLocationCoordinate2D,
        initialSelection: ArrivalTarget? = nil,
        onSelect: @escaping (ArrivalTarget) -> Void
    ) {
        self.cityName = cityName
        self.cityCoordinate = cityCoordinate
        self.initialSelection = initialSelection
        self.onSelect = onSelect
        _selected = State(initialValue: initialSelection)
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: cityCoordinate,
            latitudinalMeters: 35_000,
            longitudinalMeters: 35_000
        )))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                map
                searchBar
                categories
                results
                confirmation
            }
            .background(Theme.bg)
            .navigationTitle("\(cityName) · varış yeri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
        }
        .task {
            let region = MKCoordinateRegion(
                center: cityCoordinate,
                latitudinalMeters: 35_000,
                longitudinalMeters: 35_000
            )
            search.update(region: region)
            await search.search(category: .campground, region: region)
        }
    }

    private var map: some View {
        Map(position: $position) {
            if let selected {
                Marker(selected.name, systemImage: selected.kind.symbol,
                       coordinate: CLLocationCoordinate2D(latitude: selected.latitude, longitude: selected.longitude))
                    .tint(Theme.c2)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls { MapCompass(); MapScaleView() }
        .frame(height: 185)
        .onMapCameraChange(frequency: .onEnd) { search.update(region: $0.region) }
        .overlay(alignment: .bottomLeading) {
            Text("Apple Maps")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
                .padding(8)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("Kamp, otel veya tam adres", text: $search.query)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { Task { await search.submit() } }
            if !search.query.isEmpty {
                Button { search.clear() } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel("Aramayı temizle")
            }
            if search.isLoading { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(Theme.panel)
    }

    private var categories: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ArrivalSearchCategory.allCases) { item in
                    Button {
                        category = item
                        Task { await search.search(category: item) }
                        if item == .address { searchFocused = true }
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 11).frame(height: 34)
                            .background(category == item ? Theme.c2 : Theme.panel,
                                        in: RoundedRectangle(cornerRadius: 7))
                            .foregroundStyle(category == item ? .white : Theme.text)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .overlay(alignment: .bottom) { Divider().overlay(Theme.line) }
    }

    private var results: some View {
        List {
            if let error = search.errorMessage {
                Text(error).font(.footnote).foregroundStyle(Theme.warn)
            }
            ForEach(search.suggestions) { suggestion in
                Button {
                    Task {
                        if let target = try? await search.resolve(suggestion) {
                            selected = target
                            position = .region(MKCoordinateRegion(
                                center: CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude),
                                latitudinalMeters: 5_000,
                                longitudinalMeters: 5_000
                            ))
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(Theme.c2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(suggestion.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                            Text(suggestion.subtitle).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2)
                        }
                        Spacer()
                        if selected?.id == suggestion.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ok) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let selected {
                Text(selected.name).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                Text(selected.formattedAddress).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2)
            } else {
                Text("Gerçek kamp, otel veya adresi seçin.").font(.footnote).foregroundStyle(Theme.muted)
            }
            Button {
                guard let selected else { return }
                onSelect(selected)
                dismiss()
            } label: {
                Label("Bu yeri seç", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity).frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.c2)
            .disabled(selected == nil)
        }
        .padding(14)
        .background(.ultraThickMaterial)
        .overlay(alignment: .top) { Divider().overlay(Theme.line) }
    }
}
