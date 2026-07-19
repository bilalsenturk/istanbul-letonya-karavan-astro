import SwiftUI
import MapKit

// Canlı konum kartı: cihaz GPS'i → harita + Riga'ya kalan + sıradaki durak.
struct LiveLocationCard: View {
    @EnvironmentObject var store: TripStore
    @EnvironmentObject var loc: LocationManager

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
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if loc.location != nil {
                    HStack(spacing: 0) {
                        stat(
                            value: rigaText(trip: trip),
                            label: "Riga'ya kalan"
                        )
                        Divider().background(Theme.line).padding(.vertical, 4)
                        stat(
                            value: nearestText(trip: trip),
                            label: "En yakın durak"
                        )
                        Divider().background(Theme.line).padding(.vertical, 4)
                        stat(
                            value: loc.speedKmh.map { "\($0) km/s" } ?? "0 km/s",
                            label: "Hız"
                        )
                    }
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
    }

    @ViewBuilder
    private func routeMap(trip: TripData) -> some View {
        let coords = trip.stops.map(\.coordinate)
        Map(initialPosition: .automatic) {
            MapPolyline(coordinates: coords)
                .stroke(Theme.c2, lineWidth: 3)
            ForEach(trip.stops) { stop in
                Annotation(stop.name, coordinate: stop.coordinate) {
                    Text(stop.flag)
                        .font(.system(size: 14))
                        .padding(4)
                        .background(.black.opacity(0.55), in: Circle())
                }
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .flat))
    }

    private func rigaText(trip: TripData) -> String {
        guard let riga = trip.stops.last, let km = loc.distanceKm(to: riga) else { return "—" }
        return "\(Int(km.rounded())) km"
    }

    private func nearestText(trip: TripData) -> String {
        guard let near = loc.nearestStop(in: trip.stops) else { return "—" }
        return "\(near.stop.name) · \(Int(near.km.rounded())) km"
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
