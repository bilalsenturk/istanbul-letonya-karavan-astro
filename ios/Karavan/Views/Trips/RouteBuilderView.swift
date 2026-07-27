import MapKit
import SwiftUI

private enum RouteEditorSheet: Identifiable {
    case place(index: Int?)
    case details(RouteDraftStop)

    var id: String {
        switch self {
        case .place(let index): "place-\(index.map(String.init) ?? "new")"
        case .details(let stop): "details-\(stop.id)"
        }
    }
}

struct RouteBuilderView: View {
    @EnvironmentObject private var account: AccountSessionStore
    @EnvironmentObject private var workspace: TripWorkspaceStore
    @EnvironmentObject private var location: LocationManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var preview = RoutePreviewService()
    @State private var draft: RouteDraft
    @State private var position: MapCameraPosition = .automatic
    @State private var sheet: RouteEditorSheet?
    @State private var errorMessage: String?
    @State private var editMode: EditMode = .inactive

    private let trip: AccountTrip?

    init(trip: AccountTrip? = nil) {
        self.trip = trip
        _draft = State(initialValue: trip.map(RouteDraft.init(trip:)) ?? RouteDraft(name: ""))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    routeMap
                    itineraryPanel(maxHeight: min(geometry.size.height * 0.58, 470))
                }
                .background(Theme.bg)
            }
            .navigationTitle(trip == nil ? "Yeni rota" : "Rotayı düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(workspace.isWorking ? "Kaydediliyor" : "Kaydet") {
                        Task { await save() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!draft.isSavable || workspace.isWorking)
                    .accessibilityIdentifier("route-editor-save")
                }
            }
        }
        .fullScreenCover(item: $sheet) { item in
            switch item {
            case .place(let index):
                PlacePickerView(
                    title: pickerTitle(for: index),
                    allowsCurrentLocation: allowsCurrentLocation(at: index),
                    transportMode: draft.transportMode
                ) { stop in
                    if let index { draft.replace(at: index, with: stop) }
                    else { draft.add(stop) }
                    refreshPreview()
                }
                .environmentObject(location)
            case .details(let stop):
                StopEditorView(stop: stop) { updated in
                    draft.update(updated)
                    refreshPreview()
                }
            }
        }
        .onAppear(perform: prepare)
        .onChange(of: draft.transportMode) { _, _ in refreshPreview() }
        .onChange(of: location.location) { _, newLocation in
            guard let coordinate = newLocation?.coordinate else { return }
            if draft.stops.contains(where: { $0.source == .currentLocation }) {
                draft.updateCurrentLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                refreshPreview()
            } else if trip == nil && draft.stops.isEmpty {
                draft.add(.currentLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
                refreshPreview()
            }
        }
    }

    private var routeMap: some View {
        Map(position: $position) {
            UserAnnotation()
            if preview.coordinates.count > 1 {
                MapPolyline(coordinates: preview.coordinates)
                    .stroke(Theme.c2, style: StrokeStyle(
                        lineWidth: 5,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: draft.transportMode == .flight ? [9, 7] : []
                    ))
            }
            ForEach(Array(draft.stops.enumerated()), id: \.element.id) { index, stop in
                if stop.source != .currentLocation {
                    Annotation(stop.name, coordinate: CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lng)) {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 29, height: 29)
                            .background(Theme.c2, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapCompass()
            MapScaleView()
            MapUserLocationButton()
            MapPitchToggle()
        }
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .topLeading) {
            if preview.isLoading || preview.distanceKm != nil {
                HStack(spacing: 7) {
                    if preview.isLoading { ProgressView().controlSize(.small) }
                    Text(routeSummary).font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(12)
            }
        }
    }

    private func itineraryPanel(maxHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Theme.muted.opacity(0.55))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 10)

            HStack(spacing: 10) {
                TextField("Rota adı", text: $draft.name)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .disabled(!canEditMetadata)
                    .accessibilityIdentifier("route-editor-name")
                if draft.stops.count >= 2 && canEditStops {
                    Button {
                        draft.reverseStops()
                        refreshPreview()
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Rotayı ters çevir")
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            editMode = editMode == .active ? .inactive : .active
                        }
                    } label: {
                        Image(systemName: editMode == .active ? "checkmark" : "line.3.horizontal")
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.bordered)
                    .tint(editMode == .active ? Theme.c2 : nil)
                    .accessibilityLabel(editMode == .active ? "Sıralamayı bitir" : "Durakları sırala")
                }
            }
            .padding(.horizontal, 16)

            transportPicker
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider().overlay(Theme.line)

            List {
                ForEach(Array(draft.stops.enumerated()), id: \.element.id) { index, stop in
                    itineraryRow(stop, index: index)
                        .listRowBackground(Theme.panel)
                        .listRowSeparatorTint(Theme.line)
                }
                .onMove { source, destination in
                    guard canEditStops else { return }
                    draft.move(fromOffsets: source, toOffset: destination)
                    refreshPreview()
                }

                if draft.stops.count < 2 {
                    placeholderRow(index: draft.stops.count)
                        .listRowBackground(Theme.panel)
                } else if canEditStops {
                    Button { sheet = .place(index: nil) } label: {
                        Label("Durak ekle", systemImage: "plus.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.c2)
                    }
                    .accessibilityIdentifier("route-editor-add-stop")
                    .listRowBackground(Theme.panel)
                }

                if let message = errorMessage ?? workspace.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(Theme.warn)
                        .listRowBackground(Theme.panel)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, $editMode)
            .frame(height: min(maxHeight - 132, CGFloat(max(2, routeRowCount)) * 55 + 46))
            .contentMargins(.vertical, 0, for: .scrollContent)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(maxHeight: maxHeight)
        .background(.ultraThickMaterial)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18)
                .strokeBorder(Theme.line)
        }
    }

    private var transportPicker: some View {
        HStack(spacing: 5) {
            ForEach(RouteTransportMode.allCases) { mode in
                Button {
                    guard canEditMetadata else { return }
                    draft.transportMode = mode
                } label: {
                    Label(mode.title, systemImage: mode.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(draft.transportMode == mode ? .white : Theme.muted)
                .background(
                    draft.transportMode == mode ? Theme.c2 : Theme.bg.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .disabled(!canEditMetadata)
            }
        }
    }

    private func itineraryRow(_ stop: RouteDraftStop, index: Int) -> some View {
        Button {
            guard canEditStops else { return }
            sheet = .place(index: index)
        } label: {
            HStack(spacing: 12) {
                waypointSymbol(index: index, stop: stop)
                VStack(alignment: .leading, spacing: 3) {
                    Text(waypointRole(index: index))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                    Text(stop.source == .currentLocation ? "Konumum" : stop.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if canEditStops {
                    Button { sheet = .details(stop) } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.muted)
                    .accessibilityLabel("\(stop.name) ayrıntıları")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("route-editor-stop-\(index)")
        .swipeActions(edge: .trailing, allowsFullSwipe: draft.stops.count > 2) {
            if canEditStops {
                Button(role: .destructive) {
                    draft.remove(id: stop.id)
                    refreshPreview()
                } label: {
                    Label("Sil", systemImage: "trash")
                }
            }
        }
    }

    private func placeholderRow(index: Int) -> some View {
        Button {
            guard canEditStops else { return }
            sheet = .place(index: nil)
        } label: {
            HStack(spacing: 12) {
                waypointSymbol(index: index, stop: nil)
                VStack(alignment: .leading, spacing: 3) {
                    Text(index == 0 ? "Başlangıç" : "Hedef")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                    Text(index == 0 ? "Konumum veya bir yer seç" : "Nereye gidiyorsunuz?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.c2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(index == 0 ? "route-editor-origin" : "route-editor-destination")
    }

    private func waypointSymbol(index: Int, stop: RouteDraftStop?) -> some View {
        ZStack {
            Circle()
                .fill(stop?.source == .currentLocation ? Color.blue : index == 0 ? Theme.muted : Theme.c2)
                .frame(width: 28, height: 28)
            if stop?.source == .currentLocation {
                Image(systemName: "location.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
            } else if stop == nil {
                Image(systemName: index == 0 ? "location.circle" : "mappin")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
            } else {
                Text("\(index + 1)").font(.system(size: 11, weight: .black)).foregroundStyle(.white)
            }
        }
    }

    private var canEditStops: Bool { trip?.access.canEditStops ?? true }
    private var canEditMetadata: Bool { trip?.access.canEditTrip ?? true }
    private var routeRowCount: Int {
        max(2, draft.stops.count + (draft.stops.count >= 2 && canEditStops ? 1 : 0))
    }

    private func waypointRole(index: Int) -> String {
        if index == 0 { return "Başlangıç" }
        if index == draft.stops.count - 1 { return "Hedef" }
        return "Durak \(index)"
    }

    private func pickerTitle(for index: Int?) -> String {
        guard let index else { return "Durak ekle" }
        if index == 0 { return "Başlangıcı seç" }
        if index == draft.stops.count - 1 { return "Hedefi değiştir" }
        return "Durağı değiştir"
    }

    private func allowsCurrentLocation(at index: Int?) -> Bool {
        !draft.stops.enumerated().contains { offset, stop in
            stop.source == .currentLocation && offset != index
        }
    }

    private func prepare() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-preview-builder"), trip == nil, draft.stops.isEmpty {
            draft = Self.previewDraft
            if ProcessInfo.processInfo.arguments.contains("-ui-preview-flight") { draft.transportMode = .flight }
            refreshPreview()
            if ProcessInfo.processInfo.arguments.contains("-ui-preview-add-stop") {
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    sheet = .place(index: 0)
                }
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-preview-add-stop") {
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                sheet = .place(index: draft.stops.isEmpty ? nil : 0)
            }
        }
        #endif
        if trip == nil, draft.stops.isEmpty, let coordinate = location.location?.coordinate {
            draft.add(.currentLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
        refreshPreview()
    }

    private func refreshPreview() {
        preview.update(stops: draft.stops, mode: draft.transportMode)
        position = .automatic
    }

    private func save() async {
        if let trip {
            if await workspace.update(draft, trip: trip, account: account) { dismiss() }
        } else {
            await workspace.create(draft, account: account)
            if workspace.selectedTrip != nil { dismiss() }
        }
    }

    private var routeSummary: String {
        guard let distance = preview.distanceKm else { return "Rota hesaplanıyor" }
        guard let minutes = preview.durationMinutes else { return "Yaklaşık \(distance) km" }
        let hours = minutes / 60
        let remainder = minutes % 60
        let duration = hours > 0 ? "\(hours) sa \(remainder) dk" : "\(minutes) dk"
        return "\(distance) km · \(duration)"
    }

    #if DEBUG
    private static let previewDraft = RouteDraft(
        name: "Balkan Yazı",
        stops: [
            .currentLocation(latitude: 41.0082, longitude: 28.9784),
            RouteDraftStop(id: "preview-sofia", name: "Sofya", lat: 42.6977, lng: 23.3219, note: "2 gece"),
            RouteDraftStop(id: "preview-bucharest", name: "Bükreş", lat: 44.4268, lng: 26.1025, note: "Şehir merkezi")
        ]
    )
    #endif
}
