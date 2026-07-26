import SwiftUI
import UIKit

struct ArrivalTargetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var profileStore: StayContactProfileStore
    @State private var target: ArrivalTarget
    @State private var stay: StayDetails
    @State private var copied = false

    let onSave: (ArrivalTarget, StayDetails) -> Void

    init(
        target: ArrivalTarget,
        stay: StayDetails,
        routeId: String,
        onSave: @escaping (ArrivalTarget, StayDetails) -> Void
    ) {
        _target = State(initialValue: target)
        _stay = State(initialValue: stay)
        _profileStore = StateObject(wrappedValue: StayContactProfileStore(routeId: routeId))
        self.onSave = onSave
    }

    private var message: StayMessage {
        StayMessageComposer.compose(target: target, stay: stay, profile: profileStore.profile)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Varış yeri") {
                    LabeledContent("Yer", value: target.name)
                    Text(target.formattedAddress).font(.footnote).foregroundStyle(.secondary)
                    TextField("Telefon", text: optionalBinding(\.phone))
                        .keyboardType(.phonePad)
                    TextField("WhatsApp numarası", text: optionalBinding(\.whatsAppPhone))
                        .keyboardType(.phonePad)
                    TextField("E-posta", text: optionalBinding(\.email))
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                }

                Section("Konaklama") {
                    Picker("Durum", selection: $stay.reservationStatus) {
                        ForEach(StayReservationStatus.allCases) { Text($0.title).tag($0) }
                    }
                    DatePicker("Giriş", selection: dateBinding(\.checkIn, fallback: Date()), displayedComponents: .date)
                    DatePicker("Çıkış", selection: dateBinding(\.checkOut, fallback: Date().addingTimeInterval(86_400)), displayedComponents: .date)
                    TextField("Tahmini varış", text: stayOptionalBinding(\.estimatedArrival))
                    TextField("Rezervasyon kodu", text: stayOptionalBinding(\.reservationReference))
                }

                Section("Seyahat bilgileri") {
                    TextField("İletişim adı", text: $profileStore.profile.contactName)
                    Stepper("Yetişkin: \(profileStore.profile.adults)", value: $profileStore.profile.adults, in: 1 ... 12)
                    Stepper("Çocuk: \(profileStore.profile.children)", value: $profileStore.profile.children, in: 0 ... 12)
                    TextField("Araç ve karavan", text: $profileStore.profile.vehicleDescription)
                    Toggle("Elektrik gerekli", isOn: $profileStore.profile.needsElectricity)
                    Toggle("Evcil hayvan var", isOn: $profileStore.profile.hasPet)
                }

                Section("Hazır mesaj") {
                    Text(message.body).font(.system(size: 13)).textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = message.body
                        copied = true
                    } label: { Label(copied ? "Kopyalandı" : "Mesajı kopyala", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    if let url = ContactLinkBuilder.whatsAppURL(phone: target.whatsAppPhone ?? target.phone, message: message.body) {
                        Button { openURL(url) } label: { Label("WhatsApp'tan yaz", systemImage: "message.fill") }
                    }
                    if let url = ContactLinkBuilder.emailURL(email: target.email, subject: message.subject, body: message.body) {
                        Button { openURL(url) } label: { Label("E-posta hazırla", systemImage: "envelope.fill") }
                    }
                    if let phone = target.phone, let url = URL(string: "tel:\(phone.filter { !$0.isWhitespace })") {
                        Button { openURL(url) } label: { Label("Ara", systemImage: "phone.fill") }
                    }
                    if let url = target.websiteURL {
                        Button { openURL(url) } label: { Label("Web sitesini aç", systemImage: "safari.fill") }
                    }
                }
            }
            .navigationTitle("Konaklama")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        target.updatedAt = Date()
                        onSave(target, stay)
                        dismiss()
                    }.fontWeight(.bold)
                }
            }
        }
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<ArrivalTarget, String?>) -> Binding<String> {
        Binding(
            get: { target[keyPath: keyPath] ?? "" },
            set: { target[keyPath: keyPath] = $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        )
    }

    private func stayOptionalBinding(_ keyPath: WritableKeyPath<StayDetails, String?>) -> Binding<String> {
        Binding(
            get: { stay[keyPath: keyPath] ?? "" },
            set: { stay[keyPath: keyPath] = $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        )
    }

    private func dateBinding(_ keyPath: WritableKeyPath<StayDetails, Date?>, fallback: Date) -> Binding<Date> {
        Binding(get: { stay[keyPath: keyPath] ?? fallback }, set: { stay[keyPath: keyPath] = $0 })
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
