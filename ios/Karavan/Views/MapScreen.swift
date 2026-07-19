import SwiftUI
import MapKit

// Tam ekran etkileşimli harita: rota, duraklar, canlı konum, hız ve
// tek dokunuşla Apple/Google Maps navigasyonu.
struct MapScreen: View {
    @EnvironmentObject var store: TripStore
    @EnvironmentObject var loc: LocationManager

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedStop: Stop?

    var body: some View {
        ZStack(alignment: .bottom) {
            if let trip = store.trip {
                Map(position: $position) {
                    MapPolyline(coordinates: trip.stops.map(\.coordinate))
                        .stroke(Theme.c2, lineWidth: 4)
                    ForEach(trip.stops) { stop in
                        Annotation(stop.name, coordinate: stop.coordinate) {
                            Button {
                                selectedStop = stop
                            } label: {
                                Text(stop.flag)
                                    .font(.system(size: 17))
                                    .padding(6)
                                    .background(.black.opacity(0.6), in: Circle())
                                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                            }
                        }
                    }
                    UserAnnotation()
                }
                .mapStyle(.standard(elevation: .realistic))
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }

                overlay(trip: trip)
            }
        }
        .task { loc.request() }
        .sheet(item: $selectedStop) { stop in
            stopSheet(stop)
                .presentationDetents([.height(210)])
                .presentationBackground(.thinMaterial)
        }
    }

    private func overlay(trip: TripData) -> some View {
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
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
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

    private func stopSheet(_ stop: Stop) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(stop.flag).font(.system(size: 30))
                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.name)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                    Text(stop.country)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let km = loc.distanceKm(to: stop) {
                    VStack(spacing: 1) {
                        Text("\(Int(km.rounded()))")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                        Text("km")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    NavApp.openAppleMaps(to: stop)
                } label: {
                    Label("Apple Maps", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.c2)

                Button {
                    NavApp.openGoogleMaps(to: stop)
                } label: {
                    Label("Google Maps", systemImage: "globe.europe.africa.fill")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
    }
}
