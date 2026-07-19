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

    var body: some View {
        ZStack(alignment: .bottom) {
            if let trip = store.trip {
                Map(position: $position) {
                    // Gerçek sürüş rotası (Apple Haritalar / MKDirections).
                    // Henüz hesaplanmadıysa ince kesikli taslak çizgi (kırmızı değil).
                    if routeStore.routes.isEmpty {
                        MapPolyline(coordinates: trip.stops.map(\.coordinate))
                            .stroke(Theme.c4.opacity(0.35), style: StrokeStyle(lineWidth: 3, dash: [6, 6]))
                    } else {
                        ForEach(Array(routeStore.routes.enumerated()), id: \.offset) { _, route in
                            MapPolyline(route)
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
                await nav.update(location: loc.location, stops: stops, legs: routeStore.routes)
            }
        }
        .onChange(of: loc.location?.timestamp) { _, _ in
            if let stops = store.trip?.stops {
                Task { await nav.update(location: loc.location, stops: stops, legs: routeStore.routes) }
            }
        }
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
                    Text(stop.flag).font(.system(size: 15))
                }
                .overlay(Circle().strokeBorder(Theme.c4, lineWidth: 2))
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func overlay(trip: TripData) -> some View {
        VStack(spacing: 8) {
            if let next = nav.nextStop, let km = nav.remainingKm {
                pill("arrow.triangle.turn.up.right.circle.fill", "\(next.name) · \(km) km · \(nav.remainingTimeText)")
            } else if !routeStore.routes.isEmpty {
                pill("road.lanes", "Gerçek yol: \(routeStore.totalDistanceKm) km · \(routeTimeText)")
            } else if routeStore.computing {
                pill("road.lanes", "Gerçek yol hesaplanıyor…")
            }
            HStack(spacing: 10) {
                if let speed = loc.speedKmh {
                    pill("gauge.with.dots.needle.67percent", "\(speed) km/s")
                }
                if let riga = trip.stops.last, let km = loc.distanceKm(to: riga) {
                    pill("flag.checkered", "Riga \(Int(km.rounded())) km")
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
