import SwiftUI
import MapKit

// Tam ekran etkileşimli harita: rota, duraklar, canlı konum, hız ve
// tek dokunuşla Apple/Google Maps navigasyonu.
struct MapScreen: View {
    @EnvironmentObject var store: TripStore
    @EnvironmentObject var loc: LocationManager
    @EnvironmentObject var routeStore: RouteStore
    @EnvironmentObject var nav: NavProgressStore
    @EnvironmentObject var role: RoleStore
    @EnvironmentObject var routeSession: RouteSession
    @EnvironmentObject private var appNavigation: AppNavigation

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedStop: Stop?
    /// Harita ilk açılışta KONUMUNDAN başlar; .automatic tüm rotayı sığdırdığı için
    /// İstanbul–Riga arasında bir yerde, nerede olduğun görünmeyecek kadar uzakta açılıyordu.
    @State private var didCenterOnUser = false
    @State private var activeRouteCoords: [CLLocationCoordinate2D] = []
    @State private var showRouteStops = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if let trip = store.trip {
                Map(position: $position) {
                    // Gerçek sürüş rotası (Apple Haritalar / MKDirections).
                    // Henüz hesaplanmadıysa ince kesikli taslak çizgi (kırmızı değil).
                    if routeStore.displayCoords.isEmpty {
                        MapPolyline(coordinates: trip.stops.map(\.coordinate))
                            .stroke(.white.opacity(0.34), style: StrokeStyle(lineWidth: 3, dash: [6, 6]))
                    } else {
                        ForEach(Array(routeStore.displayCoords.enumerated()), id: \.offset) { _, coords in
                            MapPolyline(coordinates: coords)
                                .stroke(.white.opacity(routeSession.isActive ? 0.22 : 0.42), lineWidth: routeSession.isActive ? 3 : 4)
                        }
                    }
                    if activeRouteCoords.count > 1 {
                        MapPolyline(coordinates: activeRouteCoords)
                            .stroke(Theme.c2, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                    ForEach(Array(routeStore.traveledDisplayCoords(
                        stops: trip.stops,
                        routeStarted: routeSession.isActive,
                        activeStopId: routeSession.activeStopId,
                        currentLegIndex: nav.currentLegIndex,
                        legProgress: nav.legProgress
                    ).enumerated()), id: \.offset) { _, coords in
                        MapPolyline(coordinates: coords)
                            .stroke(Theme.ok, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                    if let location = loc.location {
                        Annotation("", coordinate: location.coordinate, anchor: .center) {
                            MiniRigMarker(
                                heading: location.course >= 0 ? location.course : 0,
                                moving: routeSession.isActive && (loc.speedKmh ?? 0) > 2
                            )
                        }
                    }
                    ForEach(Array(trip.stops.enumerated()), id: \.element.id) { idx, stop in
                        Annotation(stop.name, coordinate: stop.coordinate, anchor: .bottom) {
                            stopMarker(stop, index: idx)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .all))
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }

                overlay(trip: trip)
            }
        }
        .task { await bootstrap() }
        // .task yolculuk yüklenmeden çalıştıysa rota/nav başlatılmadan
        // kalırdı — trip gelince yeniden dene.
        .onChange(of: store.trip != nil) { _, loaded in
            if loaded { Task { await bootstrap() } }
        }
        .onChange(of: loc.location?.timestamp) { _, _ in
            centerOnUserOnce()
            if let stops = store.trip?.stops {
                Task {
                    await nav.update(location: loc.location, stops: stops, route: routeStore)
                    await refreshActiveRoute(trip: store.trip)
                }
            }
        }
        .onChange(of: routeSession.activeStopId) { _, _ in
            Task { await refreshActiveRoute(trip: store.trip) }
        }
        .onAppear { centerOnUserOnce() }
        .sheet(item: $selectedStop) { stop in
            StopExploreView(stop: stop)
        }
    }

    // Durak işareti: bayrak + üstünde şehir adı etiketi (kullanıcı isteği).
    private func stopMarker(_ stop: Stop, index: Int) -> some View {
        Button {
            selectedStop = stop
        } label: {
            VStack(spacing: 3) {
                Text(stop.name)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.62), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
                    .fixedSize()
                ZStack {
                    Circle().fill(.black.opacity(0.65)).frame(width: 30, height: 30)
                    Text(stop.code)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
                .overlay(Circle().strokeBorder(Theme.c4, lineWidth: 2))
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Kamera

    /// Konum izni + rota/nav önyüklemesi; trip sonradan gelirse tekrar çağrılır.
    private func bootstrap() async {
        loc.request()
        if let stops = store.trip?.stops {
            await routeStore.computeIfNeeded(stops: stops)
            await nav.update(location: loc.location, stops: stops, route: routeStore)
            await refreshActiveRoute(trip: store.trip)
        }
    }

    private func refreshActiveRoute(trip: TripData?) async {
        guard routeSession.isActive,
              let trip,
              let activeStopId = routeSession.activeStopId,
              let target = trip.stops.first(where: { $0.id == activeStopId }),
              let source = activeRouteSource(for: target, trip: trip)
        else {
            activeRouteCoords = []
            return
        }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: target.coordinate))
        request.transportType = .automobile

        if let route = try? await MKDirections(request: request).calculate().routes.first {
            activeRouteCoords = route.polyline.coordinates()
        } else {
            activeRouteCoords = [source.coordinate, target.coordinate]
        }
    }

    private func activeRouteSource(for target: Stop, trip: TripData) -> CoordinateValue? {
        guard let targetIndex = trip.stops.firstIndex(where: { $0.id == target.id }) else { return nil }
        let fallbackIndex = max(0, targetIndex - 1)
        let plannedOrigin = CoordinateValue(trip.stops[fallbackIndex].coordinate)
        return RouteStartOrigin.coordinate(
            location: loc.location.map { CoordinateValue($0.coordinate) },
            plannedOrigin: plannedOrigin
        )
    }

    /// İlk konum gelince haritayı oraya al (bir kez; sonra kullanıcı serbest gezer).
    private func centerOnUserOnce() {
        guard !didCenterOnUser, loc.location != nil else { return }
        didCenterOnUser = true
        centerOnUser()
    }

    /// "Konumum" düğmesi: her seferinde ortala. Bayrağa DOKUNMA — konum yokken
    /// bayrağı sıfırlamak, ilk GPS fiksinin kullanıcının bilerek kaydırdığı
    /// haritayı geri çekmesine yol açıyordu.
    private func centerOnUser() {
        guard let l = loc.location else { return }
        withAnimation(.easeInOut(duration: 0.6)) {
            position = .region(MKCoordinateRegion(
                center: l.coordinate,
                latitudinalMeters: 30_000,
                longitudinalMeters: 30_000
            ))
        }
    }

    /// Tüm rotayı ekrana sığdır.
    private func fitWholeRoute() {
        withAnimation(.easeInOut(duration: 0.6)) { position = .automatic }
    }

    private func overlay(trip: TripData) -> some View {
        routeControlPanel(trip: trip)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
    }

    private func routeControlPanel(trip: TripData) -> some View {
        let completed = routeSession.completedStopIds.intersection(Set(trip.stops.map(\.id))).count
        let total = max(0, trip.stops.count - 1)
        let target = displayedRouteStop(trip: trip)
        let ordinal = target.flatMap { routeOrdinal(for: $0, trip: trip) }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(routeSession.isActive ? "Rota aktif" : "Rota başlamadı",
                      systemImage: routeSession.isActive ? "play.fill" : "pause.fill")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(routeSession.isActive ? Theme.ok : Theme.c1)
                Spacer()
                Text("\(completed)/\(total)")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Theme.dim)
            }

            if let target {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ordinal.map { "\($0). \(target.name)" } ?? target.name)
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        HStack(spacing: 7) {
                            CountryBadge(code: target.code, size: 10)
                            Text(routeSession.isActive ? "Takip açık" : "Sıradaki etap")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer(minLength: 8)
                    routeActionButton(target: target, trip: trip)
                }
            } else {
                Label("Tüm etaplar tamamlandı", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ok)
            }

            HStack(spacing: 8) {
                Button { fitWholeRoute() } label: { compactPill("map", "Tüm rota") }
                    .buttonStyle(.plain)
                Button { centerOnUser() } label: { compactPill("location.fill", "Konumum") }
                    .buttonStyle(.plain)
                if routeSession.isActive, let next = nav.nextStop, let km = nav.remainingKm {
                    compactPill("arrow.triangle.turn.up.right.circle.fill", "\(next.name) \(km) km")
                }
            }

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    showRouteStops.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Duraklar")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    Spacer()
                    Text(routeSession.isActive ? "aktif" : "sırada")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(routeSession.isActive ? Theme.ok : Theme.c1)
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.dim)
                        .rotationEffect(.degrees(showRouteStops ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showRouteStops {
                routeStopList(trip: trip)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
    }

    private func routeActionButton(target: Stop, trip: TripData) -> some View {
        let state = routeSession.state(for: target, stops: trip.stops)
        let canOpenPlan = state == .available

        return Button {
            guard canOpenPlan else { return }
            appNavigation.selectedTab = .plan
        } label: {
            HStack(spacing: 7) {
                Image(systemName: state == .active ? "play.fill" : "list.number")
                    .font(.system(size: 13, weight: .bold))
                Text(canOpenPlan ? "Planı aç" : routeActionTitle(state: state, canStart: false))
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(canOpenPlan ? AnyShapeStyle(Theme.gradWarm) : AnyShapeStyle(Theme.panel),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(routeStateTint(state).opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!canOpenPlan)
        .opacity(canOpenPlan || state == .active ? 1 : 0.58)
    }

    private func routeStopList(trip: TripData) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(trip.stops.dropFirst().enumerated()), id: \.element.id) { offset, stop in
                    let state = routeSession.state(for: stop, stops: trip.stops)
                    routeStopRow(stop: stop, number: offset + 1, state: state)
                    if offset < trip.stops.dropFirst().count - 1 {
                        Divider().overlay(.white.opacity(0.08))
                    }
                }
            }
        }
        .frame(maxHeight: 210)
    }

    private func routeStopRow(stop: Stop, number: Int, state: RouteStepState) -> some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(routeStateTint(state))
                .frame(width: 24, height: 24)
                .background(routeStateTint(state).opacity(0.14), in: Circle())
            CountryBadge(code: stop.code, size: 9)
            Text(stop.name)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(state == .locked ? Theme.muted : .white)
                .lineLimit(1)
            Spacer()
            Text(routeStateText(state))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(routeStateTint(state))
        }
        .padding(.vertical, 9)
    }

    private func routeStateText(_ state: RouteStepState) -> String {
        guard role.isDriver else { return "Sürücü" }
        switch state {
        case .available: return "Sıradaki"
        case .active: return "Aktif"
        case .completed: return "Bitti"
        case .locked: return "Kilitli"
        case .origin: return "Başlangıç"
        }
    }

    private func routeActionTitle(state: RouteStepState, canStart: Bool) -> String {
        guard role.isDriver else { return "Sürücü" }
        switch state {
        case .available: return canStart ? "Buraya git" : "Sıradaki"
        case .active: return "Aktif"
        case .completed: return "Bitti"
        case .locked: return "Kilitli"
        case .origin: return "Başlangıç"
        }
    }

    private func displayedRouteStop(trip: TripData) -> Stop? {
        if routeSession.isActive,
           let activeStopId = routeSession.activeStopId,
           let active = trip.stops.first(where: { $0.id == activeStopId }) {
            return active
        }
        return routeSession.nextStartableStopId(stops: trip.stops)
            .flatMap { id in trip.stops.first { $0.id == id } }
    }

    private func routeOrdinal(for stop: Stop, trip: TripData) -> Int? {
        guard let index = trip.stops.firstIndex(where: { $0.id == stop.id }), index > 0 else { return nil }
        return index
    }

    private func routeStateTint(_ state: RouteStepState) -> Color {
        switch state {
        case .available: return Theme.c1
        case .active: return Theme.ok
        case .completed: return Theme.ok.opacity(0.82)
        case .locked, .origin: return Theme.muted
        }
    }

    private func compactPill(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
            Text(text)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
    }

}

struct MiniRigMarker: View {
    let heading: CLLocationDirection
    let moving: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            Capsule()
                .fill(.black.opacity(0.28))
                .frame(width: 42, height: 8)
                .blur(radius: 4)
                .offset(y: 9)

            HStack(spacing: 2) {
                caravan
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(.white.opacity(0.86))
                    .frame(width: 7, height: 2)
                    .shadow(color: .black.opacity(0.28), radius: 1, y: 0.5)
                car
            }
            .offset(x: moving ? (pulse ? 1.1 : -0.6) : 0,
                    y: moving ? (pulse ? -0.35 : 0.25) : 0)
        }
        .frame(width: 54, height: 32)
        .rotationEffect(.degrees(heading - 90))
        .shadow(color: .black.opacity(0.42), radius: 7, y: 4)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.82).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityHidden(true)
    }

    private var car: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(LinearGradient(colors: [.white, Color(red: 0.78, green: 0.84, blue: 0.91)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 23, height: 14)
                .overlay(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color(red: 0.18, green: 0.27, blue: 0.39).opacity(0.72))
                        .frame(width: 8, height: 4)
                        .padding(.top, 2)
                        .padding(.trailing, 5)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(.white.opacity(0.65), lineWidth: 0.8)
                )
            wheels(width: 17)
                .offset(y: 2.5)
        }
        .frame(width: 23, height: 19)
    }

    private var caravan: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.99, blue: 1.0),
                                              Color(red: 0.80, green: 0.86, blue: 0.91)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 23, height: 16)
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color(red: 0.18, green: 0.27, blue: 0.39).opacity(0.55))
                        .frame(width: 6, height: 5)
                        .padding(.top, 3)
                        .padding(.leading, 5)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(.white.opacity(0.68), lineWidth: 0.8)
                )
            wheels(width: 18)
                .offset(y: 2.5)
        }
        .frame(width: 23, height: 21)
    }

    private func wheels(width: CGFloat) -> some View {
        HStack {
            Circle().fill(Color(red: 0.03, green: 0.06, blue: 0.10)).frame(width: 4, height: 4)
            Spacer()
            Circle().fill(Color(red: 0.03, green: 0.06, blue: 0.10)).frame(width: 4, height: 4)
        }
        .frame(width: width)
    }
}

private extension MKPolyline {
    func coordinates() -> [CLLocationCoordinate2D] {
        guard pointCount > 0 else { return [] }
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
