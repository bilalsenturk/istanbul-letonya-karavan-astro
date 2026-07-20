import SwiftUI

// Bir günü düzenle. Boş bırakılan alan = "web verisini kullan" (düzenleme silinir).
// `extraDays` sonraki TÜM günlerin tarihini kaydırır (TripPlanner kaskadı).
struct DayEditView: View {
    let day: EffectiveDay

    @EnvironmentObject var plan: TripPlanStore
    @Environment(\.dismiss) private var dismiss

    @State private var origin: String
    @State private var destination: String
    @State private var distanceKm: String
    @State private var duration: String
    @State private var fuel: String
    @State private var note: String
    @State private var campName: String
    @State private var campPlace: String
    @State private var isRestDay: Bool
    @State private var extraDays: Int
    @State private var startHour: Int

    init(day: EffectiveDay) {
        self.day = day
        _origin = State(initialValue: day.origin)
        _destination = State(initialValue: day.destination)
        _distanceKm = State(initialValue: day.distanceKm)
        _duration = State(initialValue: day.duration)
        _fuel = State(initialValue: day.fuel)
        _note = State(initialValue: day.edit?.note ?? "")
        _campName = State(initialValue: day.campName)
        _campPlace = State(initialValue: day.campPlace)
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

                        group("Güzergâh", Theme.c1) {
                            field("Nereden", text: $origin)
                            field("Nereye", text: $destination)
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
                                hint: String(format: "%02d:00", startHour)
                            )
                        }

                        group("Tahminler", Theme.c3) {
                            field("Mesafe", text: $distanceKm)
                            field("Süre", text: $duration)
                            field("Yakıt", text: $fuel)
                        }

                        group("Kamp", Theme.c4) {
                            field("Kamp adı", text: $campName)
                            field("Yer", text: $campPlace)
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

    private func save() {
        plan.update(slug: day.base.slug) { e in
            e.origin = diff(origin, day.base.origin)
            e.destination = diff(destination, day.base.destination)
            e.distanceKm = diff(distanceKm, day.base.distanceKm)
            e.duration = diff(duration, day.base.duration)
            e.fuel = diff(fuel, day.base.fuel)
            e.campName = diff(campName, day.base.camp.name)
            e.campPlace = diff(campPlace, day.base.camp.place)

            let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            e.note = trimmedNote.isEmpty ? nil : trimmedNote

            let baseRest = (e.origin ?? day.base.origin) == (e.destination ?? day.base.destination)
            e.isRestDay = (isRestDay == baseRest) ? nil : isRestDay

            e.extraDays = extraDays == 0 ? nil : extraDays

            let defaultHour = day.index == 0
                ? Calendar.current.component(.hour, from: plan.departure(nil))
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
