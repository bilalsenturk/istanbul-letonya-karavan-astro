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

    private let vehicleSeed: String?

    init(routeId: String, vehicleSeed: String?) {
        _profileStore = StateObject(wrappedValue: StayContactProfileStore(routeId: routeId))
        self.vehicleSeed = vehicleSeed
    }

    var body: some View {
        Form {
            Section("İletişim") {
                TextField("İletişim adı", text: $form.contactName)
                    .textContentType(.name)
                TextField("E-posta", text: contactEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .textContentType(.emailAddress)
            }

            Section("Yolculuk") {
                Stepper("Yetişkin: \(form.adults)", value: $form.adults, in: 1 ... 12)
                Stepper("Çocuk: \(form.children)", value: $form.children, in: 0 ... 12)
                TextField("Araç ve karavan", text: $form.vehicleDescription)
                TextField("Toplam uzunluk (metre)", text: $totalLengthText)
                    .keyboardType(.decimalPad)
            }

            Section("Tercihler") {
                Toggle("Elektrik gerekli", isOn: $form.needsElectricity)
                Toggle("Evcil hayvan var", isOn: $form.hasPet)
                TextField("Ek ihtiyaçlar", text: $form.additionalNeeds, axis: .vertical)
                    .lineLimit(3 ... 6)
                Picker("Mesaj dili", selection: $form.preferredLanguage) {
                    ForEach(StayMessageLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
            }

            if isSaving {
                Section { HStack { ProgressView(); Text("Profil eşitleniyor") } }
            } else if saved {
                Section { Label("Profil kaydedildi", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }

            if let syncError {
                Section {
                    Label(syncError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Button("Tekrar dene") { save() }
                }
            }
        }
        .overlay {
            if isLoading { ProgressView("Profil yükleniyor") }
        }
        .navigationTitle("Seyahat profili")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Kaydet") { save() }
                    .fontWeight(.bold)
                    .disabled(isLoading || isSaving)
            }
        }
        .task(id: account.user?.id) {
            guard let user = account.user else { return }
            let bound = profileStore.bind(account: user, vehicleSeed: vehicleSeed)
            form = bound
            totalLengthText = bound.totalLengthMeters.map { Self.lengthFormatter.string(from: NSNumber(value: $0)) ?? "" } ?? ""
            isLoading = false
        }
    }

    private var contactEmail: Binding<String> {
        Binding(
            get: { form.contactEmail ?? "" },
            set: { form.contactEmail = $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        )
    }

    private func save() {
        guard !isSaving else { return }
        form.totalLengthMeters = Self.length(from: totalLengthText)
        form.updatedAt = ISO8601DateFormatter().string(from: Date())
        profileStore.persist(form)
        isSaving = true
        saved = false
        syncError = nil

        Task {
            do {
                let user = try await account.saveTravelProfile(form)
                form = user.travelProfile
                totalLengthText = form.totalLengthMeters.map { Self.lengthFormatter.string(from: NSNumber(value: $0)) ?? "" } ?? ""
                profileStore.persist(form)
                saved = true
            } catch {
                syncError = "Profil yerelde kaydedildi. Sunucuya gönderilemedi; tekrar deneyin."
            }
            isSaving = false
        }
    }

    private static let lengthFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    private static func length(from text: String) -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return lengthFormatter.number(from: value)?.doubleValue
    }
}

extension AccountTravelProfile {
    var travelProfileMenuSummary: String {
        let adultsText = "\(adults) yetişkin"
        let vehicle = vehicleDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return vehicle.isEmpty ? adultsText : "\(adultsText) · \(vehicle)"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
