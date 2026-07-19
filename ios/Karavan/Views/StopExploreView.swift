import SwiftUI
import MapKit

// Durak keşif ekranı — tamamen Apple Haritalar verisiyle:
// • Look Around (sokak seviyesi) önizleme
// • MKLocalSearch ile çevredeki gerçek kamp/yakıt/yemek/market/şarj yerleri
struct StopExploreView: View {
    let stop: Stop

    @StateObject private var maps = AppleMapsService()

    @State private var scene: MKLookAroundScene?
    @State private var loadingScene = true
    @State private var kind: NearbyKind = .camp
    @State private var places: [Place] = []
    @State private var loadingPlaces = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    lookAround
                    navButtons
                    nearbySection
                }
                .padding(18)
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
        .task {
            async let s: () = loadScene()
            async let p: () = search()
            _ = await (s, p)
        }
    }

    // MARK: - Başlık

    private var header: some View {
        HStack(spacing: 12) {
            Text(stop.flag).font(.system(size: 34))
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text(stop.country)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
        }
    }

    // MARK: - Look Around

    @ViewBuilder private var lookAround: some View {
        if let scene {
            LookAroundPreview(initialScene: scene)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Label("Apple Look Around", systemImage: "binoculars.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(10)
                }
        } else if loadingScene {
            infoBox(icon: "binoculars", text: "Look Around yükleniyor…", showSpinner: true)
        } else {
            infoBox(icon: "binoculars", text: "Bu durak için Look Around yok.", showSpinner: false)
        }
    }

    // MARK: - Navigasyon

    private var navButtons: some View {
        HStack(spacing: 10) {
            Button {
                NavApp.openAppleMaps(to: stop)
            } label: {
                Label("Apple Maps'te sür", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Theme.gradWarm, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            Button {
                NavApp.openGoogleMaps(to: stop)
            } label: {
                Label("Google", systemImage: "globe.europe.africa.fill")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
            }
        }
    }

    // MARK: - Yakında (Apple Haritalar)

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoLabel(text: "Yakında · Apple Haritalar", color: Theme.c4)

            Picker("Tür", selection: $kind) {
                ForEach(NearbyKind.allCases) { k in
                    Text(k.label).tag(k)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: kind) { _, _ in
                Task { await search() }
            }

            if loadingPlaces {
                infoBox(icon: kind.icon, text: "Aranıyor…", showSpinner: true)
            } else if places.isEmpty {
                infoBox(icon: kind.icon, text: "Bu çevrede sonuç bulunamadı.", showSpinner: false)
            } else {
                ForEach(places) { place in
                    placeRow(place)
                }
            }
        }
    }

    private func placeRow(_ place: Place) -> some View {
        Button {
            NavApp.openAppleMaps(toCoordinate: place.coordinate, name: place.name)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.c4.opacity(0.16)).frame(width: 38, height: 38)
                    Image(systemName: kind.icon).font(.system(size: 15)).foregroundStyle(Theme.c4)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if let sub = place.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(place.distanceKm(from: stop.coordinate), specifier: "%.1f") km")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.dim)
                    Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.c2)
                }
            }
            .padding(12)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func infoBox(icon: String, text: String, showSpinner: Bool) -> some View {
        HStack(spacing: 10) {
            if showSpinner {
                ProgressView().tint(Theme.c4)
            } else {
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Theme.muted)
            }
            Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    // MARK: - Yükleme

    private func loadScene() async {
        loadingScene = true
        scene = await maps.lookAroundScene(at: stop.coordinate)
        loadingScene = false
    }

    private func search() async {
        loadingPlaces = true
        places = await maps.searchNearby(kind, around: stop.coordinate)
        loadingPlaces = false
    }
}
