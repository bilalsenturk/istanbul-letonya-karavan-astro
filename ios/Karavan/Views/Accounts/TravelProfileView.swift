import SwiftUI

struct TravelProfileView: View {
    @EnvironmentObject private var account: AccountSessionStore
    @StateObject private var profileStore: StayContactProfileStore
    @State private var form = AccountTravelProfile()
    @State private var totalLengthText = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var saved = false
    @State private var syncError: String?
    @State private var validationError: String?
    @State private var boundAccountID: String?
    @State private var draftRevision = 0
    @State private var saveTask: Task<Void, Never>?

    private let vehicleSeed: String?

    init(routeId: String, vehicleSeed: String?) {
        _profileStore = StateObject(wrappedValue: StayContactProfileStore(routeId: routeId))
        self.vehicleSeed = vehicleSeed
    }

    var body: some View {
        Form {
            Section("İletişim") {
                TextField("İletişim adı", text: $form.contactName).textContentType(.name)
                TextField("E-posta", text: contactEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .textContentType(.emailAddress)
            }

            Section("Yolculuk") {
                Stepper("Yetişkin: \(form.adults)", value: $form.adults, in: 1 ... 12)
                Stepper("Çocuk: \(form.children)", value: $form.children, in: 0 ... 12)
                TextField("Araç ve karavan", text: $form.vehicleDescription)
                TextField("Toplam uzunluk (metre)", text: $totalLengthText).keyboardType(.decimalPad)
            }

            Section("Tercihler") {
                Toggle("Elektrik gerekli", isOn: $form.needsElectricity)
                Toggle("Evcil hayvan var", isOn: $form.hasPet)
                TextField("Ek ihtiyaçlar", text: $form.additionalNeeds, axis: .vertical).lineLimit(3 ... 6)
                Picker("Mesaj dili", selection: $form.preferredLanguage) {
                    ForEach(StayMessageLanguage.allCases) { Text($0.title).tag($0) }
                }
            }

            if isSaving { Section { HStack { ProgressView(); Text("Profil eşitleniyor") } } }
            else if saved { Section { Label("Profil kaydedildi", systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }

            if let validationError {
                Section { Label(validationError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }
            if let syncError {
                Section {
                    Label(syncError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Button("Tekrar dene") { save() }
                }
            }
        }
        .overlay { if isLoading { ProgressView("Profil yükleniyor") } }
        .navigationTitle("Seyahat profili")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Kaydet") { save() }.fontWeight(.bold).disabled(isLoading || isSaving)
            }
        }
        .task(id: account.user?.id) { loadProfile() }
        .onChange(of: account.user?.id) { _, _ in
            saveTask?.cancel()
            saveTask = nil
            isSaving = false
            saved = false
            syncError = nil
            validationError = nil
            boundAccountID = nil
            isLoading = true
        }
        .onChange(of: form) { _, _ in
            draftRevision += 1
            saved = false
        }
        .onDisappear { saveTask?.cancel() }
    }

    private var contactEmail: Binding<String> {
        Binding(get: { form.contactEmail ?? "" }, set: {
            form.contactEmail = $0.trimmingCharacters(in: .whitespacesAndNewlines).emptyToNil
        })
    }

    private func loadProfile() {
        guard !Task.isCancelled else { return }
        saved = false
        syncError = nil
        validationError = nil
        if let user = account.user {
            let binding = profileStore.bind(account: user, vehicleSeed: vehicleSeed)
            boundAccountID = user.id
            form = binding.profile
            syncError = binding.needsSync ? "Yerelde daha yeni bir profil var. Sunucuya göndermek için kaydedin." : nil
        } else {
            boundAccountID = nil
            form = profileStore.signedOutProfile(vehicleSeed: vehicleSeed)
        }
        totalLengthText = form.totalLengthMeters.map(Self.lengthText) ?? ""
        isLoading = false
    }

    private func save() {
        guard !isSaving else { return }
        switch TravelProfileLength.parse(totalLengthText) {
        case .failure(.invalid): validationError = "Toplam uzunluğu sayı olarak girin."
        case .failure(.outOfRange): validationError = "Toplam uzunluk 1 ile 30 metre arasında olmalı."
        case let .success(length):
            validationError = nil
            form.totalLengthMeters = length
            form.updatedAt = ISO8601DateFormatter().string(from: Date())
            saved = false
            syncError = nil
            guard let user = account.user else {
                profileStore.persistSignedOut(form)
                saved = true
                return
            }
            guard boundAccountID == user.id else { loadProfile(); return }
            let requestAccountID = user.id
            let submittedRevision = draftRevision
            let submitted = form
            profileStore.persistAccount(submitted, accountID: requestAccountID)
            isSaving = true
            saveTask = Task {
                do {
                    let updated = try await account.saveTravelProfile(submitted)
                    guard !Task.isCancelled,
                          TravelProfileSaveGuard.accepts(
                            currentAccountID: account.user?.id,
                            requestAccountID: requestAccountID,
                            submittedRevision: submittedRevision,
                            currentRevision: draftRevision
                          )
                    else { return }
                    profileStore.persistAccount(updated.travelProfile, accountID: requestAccountID)
                    form = updated.travelProfile
                    totalLengthText = form.totalLengthMeters.map(Self.lengthText) ?? ""
                    saved = true
                    isSaving = false
                } catch is CancellationError {
                    // Account changes and dismissal intentionally cancel an in-flight request.
                } catch {
                    guard !Task.isCancelled, account.user?.id == requestAccountID else { return }
                    syncError = "Profil yerelde kaydedildi. Sunucuya gönderilemedi; tekrar deneyin."
                    isSaving = false
                }
            }
        }
    }

    private static func lengthText(_ value: Double) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
}

extension AccountTravelProfile {
    var travelProfileMenuSummary: String {
        let vehicle = vehicleDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return vehicle.isEmpty ? "\(adults) yetişkin" : "\(adults) yetişkin · \(vehicle)"
    }
}

private extension String {
    var emptyToNil: String? { isEmpty ? nil : self }
}
