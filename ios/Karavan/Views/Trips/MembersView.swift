import SwiftUI

struct MembersView: View {
    @EnvironmentObject private var account: AccountSessionStore
    @EnvironmentObject private var workspace: TripWorkspaceStore
    @Environment(\.dismiss) private var dismiss
    let trip: AccountTrip
    @State private var showInvite = false

    private var currentTrip: AccountTrip {
        workspace.trips.first(where: { $0.id == trip.id }) ?? trip
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Erişimi olanlar") {
                    ForEach(Array(currentTrip.members.enumerated()), id: \.element.userId) { _, member in
                        HStack(spacing: 12) {
                            Image(systemName: member.role == .owner ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                                .font(.system(size: 24))
                                .foregroundStyle(member.role == .owner ? Theme.c2 : Theme.muted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.userId == account.user?.id ? "Siz" : "Kuzey kullanıcısı")
                                    .font(.system(size: 15, weight: .semibold))
                                Text(member.role.title).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !currentTrip.invites.isEmpty {
                    Section("Davet bekleyenler") {
                        ForEach(currentTrip.invites) { invite in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(invite.email).font(.system(size: 14, weight: .semibold))
                                    Text(invite.role.title).font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("Bekliyor").font(.caption).foregroundStyle(Theme.warn)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Üyeler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                if currentTrip.access.canManageMembers {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showInvite = true } label: { Image(systemName: "person.badge.plus") }
                            .accessibilityLabel("Üye ekle")
                    }
                }
            }
        }
        .sheet(isPresented: $showInvite) {
            MemberInviteView(trip: currentTrip)
                .environmentObject(account)
                .environmentObject(workspace)
        }
    }
}
