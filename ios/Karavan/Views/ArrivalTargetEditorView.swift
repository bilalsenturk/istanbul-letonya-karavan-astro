import SwiftUI
import UIKit

struct ArrivalTargetEditorView: View {
    enum Purpose {
        case editSelection
        case contactOnly
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var target: ArrivalTarget
    @State private var stay: StayDetails
    @State private var copyConfirmationVisible = false
    @State private var copyResetTask: Task<Void, Never>?
    @State private var activeComposer: ActiveStayContactComposer?
    @State private var unavailableNotice = false
    @State private var awaitingReplyPrompt = false
    @State private var whatsAppHandoff = WhatsAppHandoffState()
    @Environment(\.scenePhase) private var scenePhase

    let onSave: (ArrivalTarget, StayDetails) -> Void
    private let purpose: Purpose
    private let profile: StayContactProfile
    private let transportMode: RouteTransportMode
    private let camp: StayCamp?
    private let automaticETA: StayETAWindow?
    private let routeId: String
    private let vehicleSeed: String?

    init(
        target: ArrivalTarget,
        stay: StayDetails,
        routeId: String,
        profile: AccountTravelProfile? = nil,
        signedOutProfile: AccountTravelProfile? = nil,
        transportMode: RouteTransportMode = .automobile,
        camp: StayCamp? = nil,
        automaticETA: StayETAWindow? = nil,
        vehicleSeed: String? = nil,
        purpose: Purpose = .editSelection,
        onSave: @escaping (ArrivalTarget, StayDetails) -> Void = { _, _ in }
    ) {
        _target = State(initialValue: target)
        _stay = State(initialValue: stay)
        self.profile = (profile ?? signedOutProfile).map(StayContactProfile.init) ?? StayContactProfile()
        self.transportMode = transportMode
        self.camp = camp
        self.automaticETA = automaticETA
        self.routeId = routeId
        self.vehicleSeed = vehicleSeed
        self.purpose = purpose
        self.onSave = onSave
    }

    private var message: StayMessage {
        StayMessageComposer.compose(
            target: target,
            stay: stay,
            profile: profile,
            transportMode: transportMode,
            camp: camp
        )
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
                .disabled(purpose == .contactOnly)

                Section("Konaklama") {
                    Picker("Durum", selection: $stay.reservationStatus) {
                        ForEach(StayReservationStatus.allCases) { Text($0.title).tag($0) }
                    }
                    DatePicker("Giriş", selection: dateBinding(\.checkIn, fallback: Date()), displayedComponents: .date)
                    DatePicker("Çıkış", selection: dateBinding(\.checkOut, fallback: Date().addingTimeInterval(86_400)), displayedComponents: .date)
                    arrivalTimeEditor
                    TextField("Rezervasyon kodu", text: stayOptionalBinding(\.reservationReference))
                }
                .disabled(purpose == .contactOnly)

                if purpose == .editSelection {
                    Section("Seyahat bilgileri") {
                        NavigationLink {
                            TravelProfileView(routeId: routeId, vehicleSeed: vehicleSeed)
                        } label: {
                            Label("Seyahat profilini düzenle", systemImage: "person.text.rectangle")
                        }
                        Text("Mesaj, hesapta kaydedilmiş yolcu ve ihtiyaç bilgilerini kullanır.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Hazır mesaj") {
                    Text(message.body).font(.system(size: 13)).textSelection(.enabled)
                    Button {
                        copy(message.body)
                    } label: {
                        Label(copyConfirmationVisible ? "Kopyalandı" : "Mesajı kopyala", systemImage: copyConfirmationVisible ? "checkmark" : "doc.on.doc")
                    }
                    .accessibilityLabel("Hazır mesajı panoya kopyala")

                    if let action = StayContactAction.whatsApp.prepare(message: message, target: target) {
                        Button { start(action) } label: { Label("WhatsApp'tan yaz", systemImage: "message.fill") }
                            .accessibilityLabel("WhatsApp'ta hazır mesaj aç")
                    }
                    if let action = StayContactAction.messages.prepare(message: message, target: target) {
                        Button { start(action) } label: { Label("Mesajlar'da yaz", systemImage: "message") }
                            .accessibilityLabel("Mesajlar'da hazır mesaj aç")
                    }
                    if let action = StayContactAction.email.prepare(message: message, target: target) {
                        Button { start(action) } label: { Label("E-posta hazırla", systemImage: "envelope.fill") }
                            .accessibilityLabel("E-posta oluşturucusunda hazır mesaj aç")
                    }
                    if let phone = target.phone, let url = URL(string: "tel:\(phone.filter { !$0.isWhitespace })") {
                        Button { openURL(url) } label: { Label("Ara", systemImage: "phone.fill") }
                    }
                    if let url = target.websiteURL {
                        Button { openURL(url) } label: { Label("Web sitesini aç", systemImage: "safari.fill") }
                    }
                }
            }
            .navigationTitle(purpose == .contactOnly ? "İletişim" : "Konaklama")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottom) {
                if copyConfirmationVisible {
                    Label("Mesaj kopyalandı", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 18)
                        .accessibilityLabel("Mesaj panoya kopyalandı")
                }
            }
            .toolbar {
                if purpose == .contactOnly {
                    ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
                } else {
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
        .sheet(item: $activeComposer) { presentation in
            switch presentation.action.channel {
            case .messages:
                MessageComposerSheet(action: presentation.action, onResult: handleComposerResult)
            case .email:
                MailComposerSheet(action: presentation.action, onResult: handleComposerResult)
            case .whatsApp:
                EmptyView()
            }
        }
        .alert("Mesaj hazır; uygulama kullanılamadığı için panoya kopyalandı.", isPresented: $unavailableNotice) {
            Button("Tamam", role: .cancel) {}
        }
        .alert("Durumu “Yanıt bekleniyor” yap?", isPresented: $awaitingReplyPrompt) {
            Button("Yanıt bekleniyor") {
                if StayContactFollowUp.shouldMarkAwaitingReply(userConfirmed: true) {
                    stay.reservationStatus = .awaitingReply
                    stay.lastContactedAt = Date()
                }
            }
            Button("Şimdi değil", role: .cancel) {}
        } message: {
            Text("Bu yalnızca sizin seçtiğiniz iletişim durumudur; teslimat veya yanıt doğrulaması değildir.")
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .inactive, .background:
                apply(whatsAppHandoff.becameInactive())
            case .active:
                apply(whatsAppHandoff.becameActive())
            @unknown default:
                break
            }
        }
        .onDisappear {
            copyResetTask?.cancel()
            whatsAppHandoff = WhatsAppHandoffState()
        }
    }

    private func copy(_ body: String) {
        UIPasteboard.general.string = body
        copyConfirmationVisible = true
        copyResetTask?.cancel()
        copyResetTask = Task {
            do {
                try await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                copyConfirmationVisible = false
            } catch {
                // A later copy or view dismissal cancels the prior confirmation task.
            }
        }
    }

    private func start(_ action: PreparedContactAction) {
        copy(action.clipboardText)
        switch action.channel {
        case .messages:
            guard MessageComposerSheet.availability == .available else {
                unavailableNotice = true
                return
            }
            activeComposer = ActiveStayContactComposer(action: action)
        case .email:
            guard MailComposerSheet.availability == .available else {
                unavailableNotice = true
                return
            }
            activeComposer = ActiveStayContactComposer(action: action)
        case .whatsApp:
            guard let url = ContactLinkBuilder.whatsAppURL(
                phone: target.whatsAppPhone ?? target.phone,
                message: action.body
            ), UIApplication.shared.canOpenURL(url) else {
                unavailableNotice = true
                return
            }
            let launchID = UUID()
            whatsAppHandoff.begin(actionID: launchID)
            UIApplication.shared.open(url, options: [:]) { opened in
                apply(whatsAppHandoff.openCompleted(actionID: launchID, opened: opened))
            }
        }
    }

    private func handleComposerResult(_ result: StayContactComposerResult) {
        activeComposer = nil
        if purpose == .editSelection, StayContactFollowUp.shouldOfferAwaitingReply(after: result) {
            awaitingReplyPrompt = true
        }
    }

    private func apply(_ effect: WhatsAppHandoffEffect) {
        switch effect {
        case .none: break
        case .showUnavailable: unavailableNotice = true
        case .offerAwaitingReply:
            if purpose == .editSelection { awaitingReplyPrompt = true }
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

    @ViewBuilder
    private var arrivalTimeEditor: some View {
        if stay.estimatedArrivalMode == .automatic {
            LabeledContent("Tahmini varış", value: stay.estimatedArrival ?? automaticETA?.text ?? "Hesaplanamadı")
                .accessibilityLabel("Otomatik tahmini varış")
            Button("Tahmini varışı elle düzenle") {
                stay.estimatedArrivalMode = .manual
            }
            .accessibilityHint("Otomatik hesaplanan varış aralığını metin olarak değiştirir")
        } else {
            TextField("Tahmini varış", text: stayOptionalBinding(\.estimatedArrival))
                .accessibilityLabel("Manuel tahmini varış")
            Button("Otomatik kullan") {
                stay = StayArrivalModeResolver.useAutomatic(automaticETA, replacing: stay)
            }
            .disabled(automaticETA == nil)
            .accessibilityHint("Yol, mola ve sınır payına göre hesaplanan aralığı geri yükler")
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
