import SwiftUI

// Bir günü düzenle. Boş bırakılan alan = "web verisini kullan" (düzenleme silinir).
// `extraDays` sonraki TÜM günlerin tarihini kaydırır (TripPlanner kaskadı).
struct DayEditView: View {
    let day: EffectiveDay

    @EnvironmentObject var plan: TripPlanStore
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss

    @State private var distanceKm: String
    @State private var duration: String
    @State private var fuel: String
    @State private var note: String
    @State private var isRestDay: Bool
    @State private var extraDays: Int
    @State private var startHour: Int

    init(day: EffectiveDay) {
        self.day = day
        _distanceKm = State(initialValue: day.distanceKm)
        _duration = State(initialValue: day.duration)
        _fuel = State(initialValue: day.fuel)
        _note = State(initialValue: day.edit?.note ?? "")
        _isRestDay = State(initialValue: day.isRestDay)
        _extraDays = State(initialValue: max(0, day.edit?.extraDays ?? 0))
        _startHour = State(initialValue: Calendar.current.component(.hour, from: day.departTime))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        infoBanner

                        group("Gün türü", Theme.c1) {
                            Toggle(isOn: $isRestDay) {
                                Text("Dinlenme günü")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.text)
                            }
                            .tint(Theme.c4)
                            .padding(.vertical, 2)
                        }

                        group("Takvim", Theme.c2) {
                            stepperRow(
                                title: "Bu durakta fazladan gün",
                                value: $extraDays, range: 0 ... 14,
                                hint: extraDays == 0
                                    ? "Normal (1 gün)"
                                    : "\(1 + extraDays) gün kalınır — sonraki günler \(extraDays) gün kayar"
                            )
                            stepperRow(
                                title: "Çıkış saati",
                                value: $startHour, range: 0 ... 23,
                                hint: startHourHint
                            )
                        }

                        group("Tahminler", Theme.c3) {
                            field("Mesafe", text: $distanceKm)
                            field("Süre", text: $duration)
                            field("Yakıt", text: $fuel)
                        }

                        group("Kişisel not", Theme.c1) {
                            TextEditor(text: $note)
                                .frame(height: 90)
                                .scrollContentBackground(.hidden)
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.text)
                                .padding(10)
                                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .strokeBorder(Theme.line, lineWidth: 1))
                        }

                        if day.isEdited {
                            Button(role: .destructive) {
                                plan.reset(slug: day.base.slug)
                                dismiss()
                            } label: {
                                Label("Bu günün düzenlemelerini sıfırla", systemImage: "arrow.uturn.backward")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.bad)
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("\(day.index + 1). günü düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: refresh)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }.tint(Theme.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .font(.system(size: 16, weight: .bold)).tint(Theme.c2)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var infoBanner: some View {
        HStack(spacing: 9) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 14)).foregroundStyle(Theme.c2)
            Text("Tarih otomatik: \(day.dateText). Kalkışı değiştirirsen tüm günler kayar.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
            Spacer()
        }
        .padding(11)
        .background(Theme.c2.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Kaydet (boş/aynı alan → düzenleme yok)

    /// Sheet açılırken formu depodaki TAZE günle doldur — init'teki `day`
    /// eski bir kopya olabilir (sheet açıkken web senkronu gelmiş olabilir).
    private func refresh() {
        let d = plan.day(store.trip, slug: day.base.slug) ?? day
        distanceKm = d.distanceKm
        duration = d.duration
        fuel = d.fuel
        note = d.edit?.note ?? ""
        isRestDay = d.isRestDay
        extraDays = max(0, d.edit?.extraDays ?? 0)
        startHour = Calendar.current.component(.hour, from: d.departTime)
    }

    private func save() {
        // Diff tabanını KAYIT ANINDA depodan taze çek — sheet açıkken web
        // senkronu tabanı değiştirmiş olabilir; init'teki `day.base` bayat
        // kalıp yeni taban değerlerini hayalet düzenlemeye çevirirdi.
        let base = plan.day(store.trip, slug: day.base.slug)?.base ?? day.base
        plan.update(slug: base.slug) { e in
            e.distanceKm = diff(distanceKm, base.distanceKm)
            e.duration = diff(duration, base.duration)
            e.fuel = diff(fuel, base.fuel)

            let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            e.note = trimmedNote.isEmpty ? nil : trimmedNote

            let baseRest = base.origin == base.destination
            e.isRestDay = (isRestDay == baseRest) ? nil : isRestDay

            e.extraDays = extraDays == 0 ? nil : extraDays

            // İlk günün varsayılanı GERÇEK kalkış saati (web verisi dahil) —
            // plan.departure(nil) tripsiz Date()'e düşer ve hayalet startHour yazardı.
            let defaultHour = day.index == 0
                ? Calendar.current.component(.hour, from: plan.departure(store.trip))
                : 8
            e.startHour = (startHour == defaultHour) ? nil : startHour
        }
        dismiss()
    }

    /// Taban değerle aynıysa nil (düzenleme saklama) — böylece web güncellenince taze kalır.
    private func diff(_ value: String, _ base: String) -> String? {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t.isEmpty || t == base) ? nil : t
    }

    /// Gün 0'da stepper saatlik çalışır ama gerçek varsayılan dakikalı olabilir
    /// (ör. 08:30). Değer varsayılana eşitse kayıtta nil yazılır ve dakika
    /// korunur — ipucunda tam saati göster ki görünenle kaydedilen uyuşsun.
    private var startHourHint: String {
        guard day.index == 0 else { return String(format: "%02d:00", startHour) }
        let cal = Calendar.current
        let dep = plan.departure(store.trip)
        let defaultHour = cal.component(.hour, from: dep)
        if startHour == defaultHour, plan.edits.days[day.base.slug]?.startHour == nil {
            return String(format: "%02d:%02d (kalkış saati)", defaultHour, cal.component(.minute, from: dep))
        }
        return String(format: "%02d:00", startHour)
    }

    // MARK: - Yapı taşları

    private func group(_ title: String, _ color: Color, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(text: title, color: color)
            VStack(spacing: 10, content: content)
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.muted)
            TextField(label, text: text)
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
                .padding(11)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1))
        }
    }

    private func stepperRow(title: String, value: Binding<Int>, range: ClosedRange<Int>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Stepper(value: value, in: range) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
            }
            .tint(Theme.c2)
            Text(hint)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.muted)
        }
    }
}
