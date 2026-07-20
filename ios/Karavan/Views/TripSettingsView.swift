import SwiftUI

// Yolculuk ayarları: kalkış tarihi/saati. Değiştirince TÜM günler, geri sayım,
// hatırlatmalar, widget ve web yayını kendiliğinden kayar (TripPlanner kaskadı).
struct TripSettingsView: View {
    @EnvironmentObject var store: TripStore
    @EnvironmentObject var plan: TripPlanStore
    @Environment(\.dismiss) private var dismiss

    @State private var departure = Date()
    @State private var showResetConfirm = false

    private var days: [EffectiveDay] { TripPlanner.days(trip: store.trip, edits: previewEdits) }

    // Plan sahipliği: yalnızca BİR cihaz düzenlemeleri yayınlar, diğerleri onu izler.
    @ViewBuilder private var planOwnerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(text: "Cihazlar arası plan", color: Theme.c2)
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $plan.isOwner) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Planı bu cihaz yönetiyor")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.text)
                        Text(plan.isOwner
                             ? "Değişikliklerin diğer telefonlara gider."
                             : "Bu cihaz planı yalnızca okur; sahip cihaz ne derse o.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .tint(Theme.c1)

                if !plan.isOwner {
                    HStack(spacing: 7) {
                        Image(systemName: plan.syncing ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(plan.syncing ? Theme.muted : Theme.ok)
                        Text(syncText)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        Button("Şimdi güncelle") { Task { await plan.syncFromWeb() } }
                            .font(.system(size: 11.5, weight: .bold))
                            .tint(Theme.c1)
                    }
                }
            }
            .padding(13)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1))
        }
    }

    private var syncText: String {
        if plan.syncing { return "Güncelleniyor…" }
        guard let t = plan.lastSyncedAt else { return "Henüz güncellenmedi" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "Son güncelleme \(f.string(from: t))"
    }

    /// Seçilen tarihle canlı önizleme (kaydetmeden).
    private var previewEdits: TripEdits {
        var e = plan.edits
        e.departureAt = departure
        return e
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        planOwnerSection

                        VStack(alignment: .leading, spacing: 10) {
                            MonoLabel(text: "Kalkış", color: Theme.c1)
                            DatePicker("Kalkış tarihi ve saati", selection: $departure)
                                .datePickerStyle(.graphical)
                                .tint(Theme.c2)
                                .disabled(!plan.isOwner)
                                .opacity(plan.isOwner ? 1 : 0.45)
                                .padding(10)
                                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            MonoLabel(text: "Önizleme — günler böyle kayar", color: Theme.c4)
                            ForEach(days) { d in
                                HStack(spacing: 10) {
                                    Text("\(d.index + 1)")
                                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                        .foregroundStyle(Theme.muted)
                                        .frame(width: 18)
                                    Text(d.isRestDay ? d.origin : "\(d.origin) → \(d.destination)")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Theme.text)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(d.shortDateText)
                                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                        .foregroundStyle(Theme.c2)
                                    if d.dayCount > 1 {
                                        Text("+\(d.dayCount - 1)")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundStyle(Theme.c1)
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                            if let arrival = TripPlanner.arrivalDate(trip: store.trip, edits: previewEdits) {
                                Divider().background(Theme.line)
                                HStack {
                                    Text("Riga'ya varış")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.dim)
                                    Spacer()
                                    Text(TripPlanner.dayFormatter.string(from: arrival))
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(Theme.ok)
                                }
                            }
                        }
                        .card()

                        if plan.hasEdits, plan.isOwner {
                            Button(role: .destructive) { showResetConfirm = true } label: {
                                Label("Tüm düzenlemeleri sıfırla (\(plan.editedDayCount) gün)",
                                      systemImage: "arrow.uturn.backward")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.bad)
                        }

                        Text(plan.isOwner
                             ? "Bu cihaz planı yönetiyor: değişikliklerin siteye ve diğer telefonlara gider. Web verisi taban kalır, düzenlemelerin korunur."
                             : "Planı sahip cihaz yönetiyor. Düzenlemek için oradan değiştir ya da yukarıdan bu cihazı sahip yap.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Yolculuk Ayarları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }.tint(Theme.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        plan.setDeparture(departure)
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .bold)).tint(Theme.c2)
                    .disabled(!plan.isOwner)
                }
            }
            .confirmationDialog("Tüm düzenlemeler silinsin mi?", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("Sıfırla", role: .destructive) {
                    plan.resetAll()
                    departure = plan.departure(store.trip)
                }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("Kalkış tarihi ve gün düzenlemeleri web verisine döner.")
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { departure = plan.departure(store.trip) }
    }
}
