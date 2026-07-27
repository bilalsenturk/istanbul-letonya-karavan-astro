import SwiftUI

struct AccountMenuView: View {
    @EnvironmentObject private var account: AccountSessionStore
    @EnvironmentObject private var workspace: TripWorkspaceStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let user = account.user {
                    Section {
                        LabeledContent("Hesap", value: user.visibleName)
                        LabeledContent("Yetki", value: user.isAdmin ? "Admin" : "Kullanıcı")
                    }
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
                    Button("Oturumu kapat", role: .destructive) {
                        Task {
                            workspace.clear()
                            await account.signOut()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Hesap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }

    private var vehicleSeed: String? {
        workspace.selectedTrip?.kind == .kuzey2026 ? TravelProfileVehicleSeed.kuzey : nil
    }
}
