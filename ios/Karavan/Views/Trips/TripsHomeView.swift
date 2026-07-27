import SwiftUI

private enum TripsHomeSheet: Identifiable {
    case createRoute
    case account

    var id: String {
        switch self {
        case .createRoute: "create-route"
        case .account: "account"
        }
    }
}

struct TripsHomeView: View {
    @EnvironmentObject private var account: AccountSessionStore
    @EnvironmentObject private var workspace: TripWorkspaceStore
    @State private var sheet: TripsHomeSheet?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                if workspace.trips.isEmpty {
                    ContentUnavailableView {
                        Label("İlk rotanızı oluşturun", systemImage: "map")
                    } description: {
                        Text("Başlangıç ve durakları haritadan seçin.")
                    } actions: {
                        Button("Yeni rota") { sheet = .createRoute }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.c2)
                    }
                } else {
                    List {
                        ForEach(workspace.trips) { trip in
                            Button { workspace.select(trip) } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(trip.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text("\(trip.stops.count) durak · \(trip.roleTitle)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: trip.kind == .kuzey2026 ? "location.north.fill" : "map.fill")
                                        .foregroundStyle(trip.kind == .kuzey2026 ? Theme.c2 : .secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Rotalarım")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { sheet = .account } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Hesap")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { sheet = .createRoute } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Yeni rota")
                }
            }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .createRoute:
                RouteBuilderView()
                    .environmentObject(account)
                    .environmentObject(workspace)
            case .account:
                AccountMenuView()
                    .environmentObject(account)
                    .environmentObject(workspace)
            }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-preview-builder") {
                sheet = .createRoute
            }
            #endif
        }
    }

}
