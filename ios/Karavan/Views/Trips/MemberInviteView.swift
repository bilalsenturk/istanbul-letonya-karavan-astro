import SwiftUI

struct MemberInviteView: View {
    @EnvironmentObject private var account: AccountSessionStore
    @EnvironmentObject private var workspace: TripWorkspaceStore
    @Environment(\.dismiss) private var dismiss
    let trip: AccountTrip

    @State private var email = ""
    @State private var role: AccountTripRole = .member
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Kişi") {
                    TextField("Apple e-postası", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                }
                Section("Rol") {
                    Picker("Rol", selection: $role) {
                        Text("Üye").tag(AccountTripRole.member)
                        Text("Görüntüleyen").tag(AccountTripRole.viewer)
                    }
                    .pickerStyle(.segmented)
                    Text(role == .member
                         ? "Durakları ve günlük kayıtlarını düzenleyebilir."
                         : "Rotayı ve günlüğü yalnızca görüntüler.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Üye ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Ekleniyor" : "Ekle") { Task { await save() } }
                        .disabled(!isValidEmail || isSaving)
                }
            }
        }
    }

    private var isValidEmail: Bool {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.contains("@") && value.contains(".")
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await account.invite(trip: trip, email: email, role: role)
            workspace.replace(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
