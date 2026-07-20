import SwiftUI
import MapKit

// Tam ekran etkileşimli harita: rota, duraklar, canlı konum, hız ve
// tek dokunuşla Apple/Google Maps navigasyonu.
struct MapScreen: View {
    @EnvironmentObject var store: TripStore
    @EnvironmentObject var loc: LocationManager
    @EnvironmentObject var routeStore: RouteStore
    @EnvironmentObject var nav: NavProgressStore

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedStop: Stop?
    /// Harita ilk açılışta KONUMUNDAN başlar; .automatic tüm rotayı sığdırdığı için
    /// İstanbul–Riga arasında bir yerde, nerede olduğun görünmeyecek kadar uzakta açılıyordu.
    @State private var didCenterOnUser = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if let trip = store.trip {
                Map(position: $position) {
                    // Gerçek sürüş rotası (Apple Haritalar / MKDirections).
                    // Henüz hesaplanmadıysa ince kesikli taslak çizgi (kırmızı değil).
                    if routeStore.displayCoords.isEmpty {
                        MapPolyline(coordinates: trip.stops.map(\.coordinate))
                            .stroke(Theme.c4.opacity(0.35), style: StrokeStyle(lineWidth: 3, dash: [6, 6]))
                    } else {
                        ForEach(Array(routeStore.displayCoords.enumerated()), id: \.offset) { _, coords in
                            MapPolyline(coordinates: coords)
                                .stroke(Theme.c4, lineWidth: 5)
                        }
                    }
                    ForEach(Array(trip.stops.enumerated()), id: \.element.id) { idx, stop in
                        Annotation(stop.name, coordinate: stop.coordinate, anchor: .bottom) {
                            stopMarker(stop, index: idx)
                        }
                    }
                    UserAnnotation()
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
        .task {
            loc.request()
            if let stops = store.trip?.stops {
                await routeStore.computeIfNeeded(stops: stops)
                await nav.update(location: loc.location, stops: stops, route: routeStore)
            }
        }
        .onChange(of: loc.location?.timestamp) { _, _ in
            centerOnUserOnce()
            if let stops = store.trip?.stops {
                Task { await nav.update(location: loc.location, stops: stops, route: routeStore) }
            }
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

    /// İlk konum gelince haritayı oraya al (bir kez; sonra kullanıcı serbest gezer).
    private func centerOnUserOnce() {
        guard !didCenterOnUser, let l = loc.location else { return }
        didCenterOnUser = true
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
        VStack(spacing: 8) {
            // Sonraki etabı başlat: anons + kilit ekranı kartı + Apple Haritalar sürüşü.
            if let next = nav.nextStop {
                Button {
                    LegLauncher.start(stop: next, nav: nav, speedKmh: loc.speedKmh)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.circle.fill").font(.system(size: 17, weight: .bold))
                        Text("\(next.name) rotasını başlat")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Theme.gradWarm, in: Capsule())
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 10) {
                Button { fitWholeRoute() } label: { pill("map", "Tüm rota") }
                    .buttonStyle(.plain)
                Button {
                    didCenterOnUser = false
                    centerOnUserOnce()
                } label: { pill("location.fill", "Konumum") }
                    .buttonStyle(.plain)
            }
            if let next = nav.nextStop, let km = nav.remainingKm {
                pill("arrow.triangle.turn.up.right.circle.fill", "\(next.name) · \(km) km · \(nav.remainingTimeText)")
            } else if routeStore.hasRoute {
                pill("road.lanes", "Gerçek yol: \(routeStore.totalDistanceKm) km · \(routeTimeText)")
            } else if routeStore.computing {
                pill("road.lanes", "Gerçek yol hesaplanıyor…")
            }
            HStack(spacing: 10) {
                if let speed = loc.speedKmh {
                    pill("gauge.with.dots.needle.67percent", "\(speed) km/s")
                }
                if let km = nav.remainingToFinalKm {
                    pill("flag.checkered", "Riga \(km) km")
                }
                if let near = loc.nearestStop(in: trip.stops) {
                    pill("mappin.and.ellipse", "\(near.stop.name) \(Int(near.km.rounded())) km")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private var routeTimeText: String {
        let hours = routeStore.totalTravelTime / 3600
        return "\(Int(hours.rounded())) sa sürüş"
    }

    private func pill(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
            Text(text)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.black.opacity(0.65), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
    }

}
