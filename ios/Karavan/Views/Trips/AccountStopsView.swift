import MapKit
import SwiftUI

private enum AccountStopsSheet: Identifiable {
    case members
    case editRoute
    case stop(AccountRouteStop)

    var id: String {
        switch self {
        case .members: "members"
        case .editRoute: "edit-route"
        case .stop(let stop): "stop-\(stop.id)"
        }
    }
}

struct AccountStopsView: View {
    @EnvironmentObject private var account: AccountSessionStore
    @EnvironmentObject private var workspace: TripWorkspaceStore
    @StateObject private var preview = RoutePreviewService()
    @State private var position: MapCameraPosition = .automatic
    @State private var sheet: AccountStopsSheet?
    @State private var errorMessage: String?

    private var trip: AccountTrip? { workspace.selectedTrip }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                if let trip {
                    GeometryReader { geometry in
                        ZStack(alignment: .bottom) {
                            map(trip)
                            stopPanel(trip, maxHeight: geometry.size.height * 0.54)
                        }
                    }
                }
            }
            .navigationTitle(trip?.name ?? "Duraklar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { workspace.closeTrip() } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Rotalarıma dön")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { sheet = .members } label: { Image(systemName: "person.2") }
                        .accessibilityLabel("Üyeler")
                }
            }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .members:
                if let trip {
                    MembersView(trip: trip)
                        .environmentObject(account)
                        .environmentObject(workspace)
                }
            case .editRoute:
                if let trip {
                    RouteBuilderView(trip: trip)
                        .environmentObject(account)
                        .environmentObject(workspace)
                }
            case .stop(let stop):
                StopEditorView(stop: draftStop(stop), routeId: trip?.id ?? "local") { updated in
                    Task { await save(updated, original: stop) }
                }
            }
        }
        .onAppear {
            refreshPreview()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-preview-members") {
                sheet = .members
            } else if ProcessInfo.processInfo.arguments.contains("-ui-preview-add-stop") {
                sheet = .editRoute
            } else if ProcessInfo.processInfo.arguments.contains("-ui-preview-stop"),
                      let stop = trip?.stops.last {
                sheet = .stop(stop)
            }
            #endif
        }
        .onChange(of: trip?.stops) { _, _ in refreshPreview() }
    }

    private func map(_ trip: AccountTrip) -> some View {
        Map(position: $position) {
            UserAnnotation()
            if preview.coordinates.count > 1 {
                MapPolyline(coordinates: preview.coordinates)
                    .stroke(Theme.c2, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            ForEach(trip.stops) { stop in
                if stop.resolvedSource != .currentLocation {
                Annotation(stop.name, coordinate: CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lng)) {
                    Text("\(stop.order + 1)")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 27, height: 27)
                        .background(Theme.c2, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls { MapCompass(); MapScaleView(); MapUserLocationButton() }
        .ignoresSafeArea(edges: .bottom)
    }

    private func stopPanel(_ trip: AccountTrip, maxHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Theme.muted.opacity(0.55))
                .frame(width: 36, height: 5)
                .padding(.vertical, 9)
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Theme.warn)
                    .font(.footnote)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(trip.stops.sorted(by: { $0.order < $1.order })) { stop in
                        Button {
                            if trip.access.canEditStops { sheet = .stop(stop) }
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(stop.order + 1)")
                                    .font(.system(size: 12, weight: .black))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(stop.order == 0 ? Theme.muted : Theme.c2, in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(stop.resolvedSource == .currentLocation ? "Konumum" : stop.name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Theme.text)
                                    let detail = [stop.note, stop.accommodation].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                                    if !detail.isEmpty {
                                        Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                                    }
                                }
                                Spacer()
                                if trip.access.canEditStops {
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                                }
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 58)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(Theme.line).padding(.leading, 56)
                    }
                }
            }
            .frame(height: min(maxHeight - (trip.access.canEditStops ? 78 : 20), CGFloat(trip.stops.count) * 59))

            if trip.access.canEditStops {
                Button { sheet = .editRoute } label: {
                    Label("Rotayı düzenle", systemImage: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.c2)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .accessibilityIdentifier("account-route-edit")
            }
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThickMaterial)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18)
                .strokeBorder(Theme.line)
        }
    }

    private func refreshPreview() {
        guard let trip else { return }
        let stops = trip.stops.sorted(by: { $0.order < $1.order }).map(draftStop)
        preview.update(stops: stops, mode: trip.transportMode ?? .automobile)
        if stops.count == 1 {
            position = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: stops[0].lat, longitude: stops[0].lng),
                span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
            ))
        } else {
            position = .automatic
        }
    }

    private func draftStop(_ stop: AccountRouteStop) -> RouteDraftStop {
        RouteDraftStop(
            id: stop.id,
            name: stop.name,
            lat: stop.lat,
            lng: stop.lng,
            source: stop.resolvedSource,
            note: stop.note ?? "",
            arrivalAt: stop.arrivalAt.flatMap(ISO8601DateFormatter().date(from:)),
            accommodation: stop.accommodation ?? "",
            link: stop.link ?? "",
            arrivalTarget: stop.resolvedArrivalTarget,
            stayDetails: stop.resolvedStayDetails
        )
    }

    private func save(_ updated: RouteDraftStop, original: AccountRouteStop) async {
        guard let trip else { return }
        let iso = ISO8601DateFormatter()
        let stop = AccountRouteStop(
            id: original.id,
            name: updated.name,
            lat: updated.lat,
            lng: updated.lng,
            order: original.order,
            source: updated.source,
            note: updated.note.isEmpty ? nil : updated.note,
            arrivalAt: updated.arrivalAt.map(iso.string(from:)),
            accommodation: updated.accommodation.isEmpty ? nil : updated.accommodation,
            link: updated.link.isEmpty ? nil : updated.link,
            arrivalTarget: updated.arrivalTarget.map(AccountArrivalTarget.init),
            stayDetails: updated.stayDetails.map(AccountStayDetails.init)
        )
        do {
            let changed = try await account.updateStop(trip: trip, stop: stop)
            workspace.replace(changed)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}
