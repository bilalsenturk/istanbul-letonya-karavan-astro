import SwiftUI
import MapKit

// Canlı konum kartı: cihaz GPS'i → harita + Riga'ya kalan + sıradaki durak.
struct LiveLocationCard: View {
    @EnvironmentObject var store: TripStore
    @EnvironmentObject var loc: LocationManager
    @EnvironmentObject var routeStore: RouteStore
    @EnvironmentObject var nav: NavProgressStore
    @EnvironmentObject var appNavigation: AppNavigation
    @EnvironmentObject var routeSession: RouteSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                MonoLabel(text: "Canlı Konum · GPS", color: Theme.c2)
                Spacer()
                if loc.location != nil {
                    HStack(spacing: 5) {
                        Circle().fill(Theme.ok).frame(width: 7, height: 7)
                        Text("CANLI")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.ok)
                    }
                }
            }

            if let trip = store.trip {
                routeMap(trip: trip)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack(spacing: 10) {
                    Button {
                        appNavigation.selectedTab = .plan
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                            Text("Rotalar")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Theme.gradCool, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Button {
                        let nextRequiredStop = routeSession.nextStartableStopId(stops: trip.stops)
                            .flatMap { id in trip.stops.first { $0.id == id } }
                        AnnouncementService.shared.announceRouteReady(
                            nextStop: nextRequiredStop?.name,
                            triggeredByUserAction: true
                        )
                    } label: {
                        Image(systemName: "megaphone.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.c1)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                    }
                }

                if loc.location != nil {
                    nextDestinationPanel(trip: trip)
                    if loc.lastPublished != nil {
                        HStack(spacing: 5) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 10, weight: .bold))
                            Text("Web'e yayınlanıyor")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        }
                        .foregroundStyle(Theme.c4)
                    }
                } else {
                    Button {
                        loc.request()
                    } label: {
                        Text(loc.status == .denied ? "Ayarlar'dan konum izni ver" : "Konumu Aç")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Theme.gradCool, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                }
            }
        }
        .card()
        .task { await updateNav() }
        .onChange(of: loc.location?.timestamp) { _, _ in Task { await updateNav() } }
        // legs dizisi baştan son sayısıyla atanır (hepsi nil) — count hiç
        // değişmez. Anlamlı sinyal DOLAN etap sayısı: rota geldikçe nav tazelenir.
        .onChange(of: routeStore.legs.filter { $0 != nil }.count) { _, _ in Task { await updateNav() } }
    }

    private func updateNav() async {
        guard let stops = store.trip?.stops else { return }
        await nav.update(location: loc.location, stops: stops, route: routeStore)
    }

    // Sıradaki hedefe kalan km + SÜRE + gidilen + anlık şehir (kullanıcı isteği).
    @ViewBuilder
    private func nextDestinationPanel(trip: TripData) -> some View {
        let routeStarted = routeSession.isActive
        let nextRequiredStop = routeSession.nextStartableStopId(stops: trip.stops)
            .flatMap { id in trip.stops.first { $0.id == id } }
        let displayedLegProgress = routeStarted ? nav.legProgress : 0
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if routeStarted, let active = routeSession.activeStopName {
                    HStack(spacing: 6) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.ok)
                        Text("Aktif rota: \(active)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.ok)
                    }
                } else if let next = nextRequiredStop {
                    HStack(spacing: 6) {
                        CountryBadge(code: next.code, size: 10)
                        Text("Sıradaki etap: \(next.name)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.c1)
                    }
                } else {
                    Text("Sıradaki hedef hesaplanıyor…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                if let city = nav.currentCity {
                    Label(city, systemImage: "location.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                }
            }

            HStack(spacing: 0) {
                stat(value: routeStarted ? (nav.remainingKm.map { "\($0) km" } ?? "—") : "—", label: "Kalan yol")
                Divider().background(Theme.line).padding(.vertical, 4)
                stat(value: routeStarted && nav.remainingMinutes != nil ? nav.remainingTimeText : "—", label: "Kalan süre")
                // Hız bilinmiyorsa (geçersiz GPS) "0 km/s" sahte durma gösterirdi
                // — MapScreen'deki gibi hız istatistiğini gizle.
                if routeStarted, let speed = loc.speedKmh {
                    Divider().background(Theme.line).padding(.vertical, 4)
                    stat(value: "\(speed) km/s", label: "Hız")
                }
            }

            // Etap ilerlemesi: gidilen / kalan
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(Theme.gradCool).frame(width: geo.size.width * displayedLegProgress)
                }
            }
            .frame(height: 8)

            HStack {
                Text(routeStarted
                     ? "Gidilen \(nav.traveledKm.map { "\($0) km" } ?? "—") · %\(Int((nav.legProgress * 100).rounded()))"
                     : "Rota başlamadı · gidilen 0 km")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.muted)
                Spacer()
                if routeStarted, let km = nav.remainingToFinalKm {
                    Text("Riga'ya \(km) km")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    @ViewBuilder
    private func routeMap(trip: TripData) -> some View {
        // Kullanıcıya odaklı başlangıç kamerası (konum yoksa tüm rota).
        Map(initialPosition: .userLocation(fallback: .automatic)) {
            // Gerçek yol (Apple Haritalar); gelene kadar ince kesikli taslak (kırmızı değil).
            if routeStore.displayCoords.isEmpty {
                MapPolyline(coordinates: trip.stops.map(\.coordinate))
                    .stroke(.white.opacity(0.34), style: StrokeStyle(lineWidth: 2.5, dash: [5, 5]))
            } else {
                ForEach(Array(routeStore.displayCoords.enumerated()), id: \.offset) { _, coords in
                    MapPolyline(coordinates: coords).stroke(.white.opacity(0.42), lineWidth: 3)
                }
            }
            ForEach(Array(routeStore.traveledDisplayCoords(
                stops: trip.stops,
                routeStarted: routeSession.isActive,
                activeStopId: routeSession.activeStopId,
                currentLegIndex: nav.currentLegIndex,
                legProgress: nav.legProgress
            ).enumerated()), id: \.offset) { _, coords in
                MapPolyline(coordinates: coords)
                    .stroke(Theme.ok, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            }
            if let location = loc.location {
                Annotation("", coordinate: location.coordinate, anchor: .center) {
                    MiniRigMarker(
                        heading: location.course >= 0 ? location.course : 0,
                        moving: routeSession.isActive && (loc.speedKmh ?? 0) > 2
                    )
                }
            }
            ForEach(trip.stops) { stop in
                Annotation(stop.name, coordinate: stop.coordinate) {
                    Text(stop.code)
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(.black.opacity(0.62), in: Circle())
                        .overlay(Circle().strokeBorder(Theme.c4.opacity(0.8), lineWidth: 1))
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .kerning(1.1)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }
}
