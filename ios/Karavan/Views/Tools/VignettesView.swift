import SwiftUI

// Vinyet / otoyol geçiş takibi: hangi ülkenin yol izni ne zamana kadar geçerli;
// bitmeden 1 gün önce yerel bildirim.
struct Vignette: Codable, Identifiable {
    let id: UUID
    var country: String   // ülke kodu (BG, RO, HU…)
    var note: String
    var expiry: Date

    init(id: UUID = UUID(), country: String, note: String, expiry: Date) {
        self.id = id
        self.country = country
        self.note = note
        self.expiry = expiry
    }
}

@MainActor
final class VignetteStore: ObservableObject {
    @Published private(set) var items: [Vignette] = []

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("vignettes.json")
    }

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Vignette].self, from: data) {
            items = decoded.sorted { $0.expiry < $1.expiry }
        }
    }

    func add(_ v: Vignette) {
        items.append(v)
        items.sort { $0.expiry < $1.expiry }
        persist()
        scheduleReminder(v)
    }

    func delete(at offsets: IndexSet) {
        for i in offsets {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: ["vignette-\(items[i].id.uuidString)"])
        }
        items.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func scheduleReminder(_ v: Vignette) {
        guard let fireDate = Calendar.current.date(byAdding: .day, value: -1, to: v.expiry),
              fireDate > Date() else { return }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: fireDate)
        comps.hour = 9
        let content = UNMutableNotificationContent()
        content.title = "🛣️ \(v.country) vinyeti yarın bitiyor"
        content.body = v.note.isEmpty ? "Yenilemeyi unutma." : v.note
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "vignette-\(v.id.uuidString)", content: content, trigger: trigger)
        )
    }
}

import UserNotifications

struct VignettesView: View {
    @StateObject private var store = VignetteStore()
    @State private var showAdd = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if store.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "road.lanes").font(.system(size: 36)).foregroundStyle(Theme.muted)
                    Text("Henüz vinyet yok.\nSağ üstten ülke + bitiş tarihi ekle;\nbitmeden 1 gün önce hatırlatırım.")
                        .font(.system(size: 14)).foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.center)
                }
            } else {
                List {
                    ForEach(store.items) { v in
                        HStack(spacing: 12) {
                            CountryBadge(code: v.country, size: 13)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(v.note.isEmpty ? "Vinyet / geçiş" : v.note)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.text)
                                Text("Bitiş: \(v.expiry.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            daysLeftBadge(v.expiry)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .onDelete { store.delete(at: $0) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Vinyet Takibi")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 21))
                }
                .tint(Theme.c2)
            }
        }
        .sheet(isPresented: $showAdd) { AddVignetteSheet { store.add($0) } }
        .preferredColorScheme(.dark)
    }

    private func daysLeftBadge(_ expiry: Date) -> some View {
        let days = Calendar.current.dateComponents([.day], from: .now, to: expiry).day ?? 0
        let color: Color = days < 0 ? Theme.bad : (days <= 2 ? Theme.c1 : Theme.ok)
        return Text(days < 0 ? "bitti" : "\(days) gün")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
    }
}

private struct AddVignetteSheet: View {
    var onAdd: (Vignette) -> Void
    @Environment(\.dismiss) private var dismiss

    private let countries = ["TR", "BG", "RO", "HU", "SK", "PL", "LT", "LV"]
    @State private var country = "BG"
    @State private var note = ""
    @State private var expiry = Date().addingTimeInterval(7 * 86400)

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        MonoLabel(text: "Ülke", color: Theme.c4)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(countries, id: \.self) { c in
                                    Button { country = c } label: {
                                        Text(c)
                                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                                            .foregroundStyle(country == c ? .black.opacity(0.85) : Theme.dim)
                                            .padding(.horizontal, 14).padding(.vertical, 9)
                                            .background(
                                                country == c ? AnyShapeStyle(Theme.c4) : AnyShapeStyle(Theme.panel),
                                                in: Capsule()
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        MonoLabel(text: "Not", color: Theme.c3)
                        TextField("örn. e-vinyet 10 gün", text: $note)
                            .font(.system(size: 16)).foregroundStyle(Theme.text)
                            .padding(13)
                            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        MonoLabel(text: "Bitiş tarihi", color: Theme.c1)
                        DatePicker("", selection: $expiry, displayedComponents: .date)
                            .labelsHidden().tint(Theme.c2)
                    }
                    Spacer()
                }
                .padding(18)
            }
            .navigationTitle("Vinyet Ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }.tint(Theme.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle") {
                        onAdd(Vignette(country: country, note: note, expiry: expiry))
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .bold)).tint(Theme.c2)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
