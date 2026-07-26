import SwiftUI
import MapKit

// Durak keşif ekranı — tamamen Apple Haritalar verisiyle:
// • Look Around (sokak seviyesi) önizleme
// • MKLocalSearch ile çevredeki gerçek kamp/yakıt/yemek/market/şarj yerleri
struct StopExploreView: View {
    let stop: Stop

    @EnvironmentObject private var store: TripStore
    @EnvironmentObject private var role: RoleStore
    @EnvironmentObject private var loc: LocationManager
    @EnvironmentObject private var nav: NavProgressStore
    @EnvironmentObject private var routeSession: RouteSession
    @StateObject private var maps = AppleMapsService()

    @State private var scene: MKLookAroundScene?
    @State private var loadingScene = true
    @State private var kind: NearbyKind = .camp
    @State private var places: [Place] = []
    @State private var loadingPlaces = false
    @State private var searchGeneration = 0

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
            CountryBadge(code: stop.code, size: 18)
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

    // Bu durağa sürüş rotası = "rotayı başlat" → yalnızca sürücü
    // (NavApp'te sert kilit de var; yakındaki POI'lere adım adım navigasyon da
    // sürücüye bağlıdır — aşağıdaki POI satırlarında aynı kilit uygulanır).
    private var navButtons: some View {
        return VStack(spacing: 8) {
            Button {
                NavApp.showInAppleMaps(stop: stop)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text("Apple Maps'te göster")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                    Spacer()
                    Text("ROTA BAŞLATMAZ")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(Theme.gradWarm,
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func routeButtonTitle(_ state: RouteStepState, canStart: Bool) -> String {
        guard role.isDriver else { return "Sürücü başlatır" }
        switch state {
        case .available: return canStart ? "Buraya git" : "Sıradaki etap"
        case .active: return "Rota aktif"
        case .completed: return "Tamamlandı"
        case .locked: return "Sırada değil"
        case .origin: return "Başlangıç durağı"
        }
    }

    private func routeButtonCaption(_ state: RouteStepState) -> String {
        switch state {
        case .available: return "Apple Maps"
        case .active: return "AKTİF"
        case .completed: return "BİTTİ"
        case .locked: return "KİLİTLİ"
        case .origin: return "PLAN"
        }
    }

    private func routeButtonIcon(_ state: RouteStepState) -> String {
        switch state {
        case .available: return "arrow.triangle.turn.up.right.circle.fill"
        case .active: return "play.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .locked: return "lock.fill"
        case .origin: return "house.fill"
        }
    }

    private func routeButtonBorder(_ state: RouteStepState) -> Color {
        switch state {
        case .available: return Theme.c1.opacity(0.75)
        case .active: return Theme.ok.opacity(0.75)
        case .completed: return Theme.ok.opacity(0.35)
        case .locked, .origin: return Theme.line
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
            NavApp.showInAppleMaps(coordinate: place.coordinate, name: place.name)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
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
                        Image(systemName: "map.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.c2)
                    }
                }
                Text("Haritada göster")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.muted)
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
        let requestedKind = kind
        searchGeneration += 1
        let generation = searchGeneration
        loadingPlaces = true
        let found = await maps.searchNearby(requestedKind, around: stop.coordinate)
        guard generation == searchGeneration, requestedKind == kind else { return }
        places = found
        loadingPlaces = false
    }
}
