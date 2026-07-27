import SwiftUI

private enum JourneyMenuSheet: Identifiable {
    case account
    case members(AccountTrip)

    var id: String {
        switch self {
        case .account: "account"
        case .members(let trip): "members-\(trip.id)"
        }
    }
}

struct JourneyMenuView: View {
    @EnvironmentObject private var account: AccountSessionStore
    @EnvironmentObject private var workspace: TripWorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: JourneyMenuSheet?

    var body: some View {
        NavigationStack {
            Group {
                if account.isRestoring {
                    ProgressView("Hesap yükleniyor")
                        .tint(Theme.c2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !account.isSignedIn {
                    SignInView()
                        .environmentObject(account)
                } else {
                    signedInContent
                }
            }
            .navigationTitle(account.isSignedIn ? "Yolculuk" : "Hesap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .account:
                AccountMenuView()
                    .environmentObject(account)
                    .environmentObject(workspace)
            case .members(let trip):
                MembersView(trip: trip)
                    .environmentObject(account)
                    .environmentObject(workspace)
            }
        }
    }

    private var signedInContent: some View {
        List {
            if let trip = workspace.selectedTrip {
                Section("Aktif yolculuk") {
                    LabeledContent {
                        Text(trip.roleTitle)
                            .foregroundStyle(Theme.muted)
                    } label: {
                        Label(trip.name, systemImage: "location.north.fill")
                    }

                    Button {
                        sheet = .members(trip)
                    } label: {
                        Label("Üyeler", systemImage: "person.2")
                    }
                }
            }

            if let user = account.user {
                Section {
                    NavigationLink {
                        TravelProfileView(
                            routeId: workspace.selectedTrip?.id ?? "kuzey-local",
                            vehicleSeed: vehicleSeed
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("Seyahat profili", systemImage: "person.text.rectangle")
                            Text(user.travelProfile.travelProfileMenuSummary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Section {
                Button {
                    dismiss()
                    Task { @MainActor in
                        await Task.yield()
                        workspace.closeTrip()
                    }
                } label: {
                    Label("Rotalarım", systemImage: "map")
                }

                Button {
                    sheet = .account
                } label: {
                    Label("Hesap", systemImage: "person.crop.circle")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .tint(Theme.c2)
    }

    private var vehicleSeed: String? {
        workspace.selectedTrip?.kind == .kuzey2026 ? TravelProfileVehicleSeed.kuzey : nil
    }
}
