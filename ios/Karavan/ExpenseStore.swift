import Foundation

// Harcamaların cihazdaki tek deposu. Kalemler Documents/expenses.json'da saklanır;
// her değişimde web'e yalnızca TOPLAM gönderilir (kalem listesi cihazda kalır).
@MainActor
final class ExpenseStore: ObservableObject {
    @Published private(set) var expenses: [Expense] = []

    nonisolated static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("expenses.json")
    }

    private var fileURL: URL { Self.fileURL }

    /// Siri/App Intent gibi store örneği olmadan çalışan yerlerden doğrudan ekleme.
    /// App öne gelince `reload()` ile arayüze yansır.
    nonisolated static func appendDirect(_ expense: Expense) {
        var list = (try? JSONDecoder().decode([Expense].self, from: Data(contentsOf: fileURL))) ?? []
        list.append(expense)
        list.sort { $0.date > $1.date }
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: fileURL, options: .atomic)
        }
        let total = list.reduce(0) { $0 + $1.amountEur }
        SharedSnapshot.write([SharedSnapshot.Key.spentEur: (total * 100).rounded() / 100])
    }

    init() {
        load()
        publishTotal()
    }

    // MARK: - Hesaplamalar

    var total: Double { expenses.reduce(0) { $0 + $1.amountEur } }

    var byCategory: [ExpenseCategory: Double] {
        Dictionary(grouping: expenses, by: \.category)
            .mapValues { $0.reduce(0) { $0 + $1.amountEur } }
    }

    func total(for category: ExpenseCategory) -> Double {
        expenses.filter { $0.category == category }.reduce(0) { $0 + $1.amountEur }
    }

    // MARK: - Cihazda akıllı öneri (yerleşik, sunucusuz)

    /// Geçmiş + kategori uyumu + tazelik + SIRA deseninden ("önce benzin → sonra
    /// atıştırmalık") öğrenerek not önerir. Yazdıkça (prefix) daraltır.
    func noteSuggestions(prefix rawPrefix: String, category: ExpenseCategory, limit: Int = 5) -> [String] {
        guard !expenses.isEmpty else { return [] }
        let prefix = rawPrefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let now = Date()

        var scores: [String: Double] = [:]      // anahtar: küçük harf not
        var canonical: [String: String] = [:]   // küçük harf -> orijinal yazım

        // 1) Geçmiş notlar: sıklık + tazelik + kategori uyumu (+ yazılana eşleşme)
        for e in expenses where !e.note.isEmpty {
            let key = e.note.lowercased()
            if canonical[key] == nil { canonical[key] = e.note }
            var s = 1.0
            let ageDays = now.timeIntervalSince(e.date) / 86400
            s += max(0, 1 - ageDays / 30)
            if e.category == category { s += 1.6 }
            if !prefix.isEmpty {
                if key.hasPrefix(prefix) { s += 3 }
                else if key.contains(prefix) { s += 1.5 }
                else { s = 0 }                    // yazarken eşleşmeyeni ele
            }
            if s > 0 { scores[key, default: 0] += s }
        }

        // 2) Sıra deseni: en son eklenen nottan sonra hangi not geliyor (kronolojik ikili)
        if prefix.isEmpty, let lastNote = expenses.first(where: { !$0.note.isEmpty })?.note.lowercased() {
            let chrono = expenses.sorted { $0.date < $1.date }
            for i in 0 ..< max(0, chrono.count - 1) {
                let a = chrono[i].note.lowercased()
                let b = chrono[i + 1].note.lowercased()
                guard !a.isEmpty, !b.isEmpty, a == lastNote, b != lastNote else { continue }
                if canonical[b] == nil { canonical[b] = chrono[i + 1].note }
                scores[b, default: 0] += 2.5
            }
        }

        return scores
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .compactMap { canonical[$0.key] }
    }

    // MARK: - Değişiklikler

    func add(_ expense: Expense) {
        expenses.append(expense)
        expenses.sort { $0.date > $1.date }
        persist()
    }

    func delete(at offsets: IndexSet) {
        expenses.remove(atOffsets: offsets)
        persist()
    }

    // MARK: - Kalıcılık

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Expense].self, from: data)
        else { return }
        expenses = decoded.sorted { $0.date > $1.date }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(expenses) {
            try? data.write(to: fileURL, options: .atomic)
        }
        publishTotal()
        SharedSnapshot.write([SharedSnapshot.Key.spentEur: (total * 100).rounded() / 100])
        LiveActivityManager.shared.reloadWidgetsThrottled()
    }

    /// Diskten yeniden yükle (Siri/App Intent arka planda eklemiş olabilir).
    func reload() {
        load()
        objectWillChange.send()
    }

    // MARK: - Web'e yalnızca toplamı yayınla

    private func publishTotal() {
        guard let url = Config.expensesPostURL else { return }
        let rounded = (total * 100).rounded() / 100
        let categories = byCategory.reduce(into: [String: Double]()) { acc, pair in
            acc[pair.key.rawValue] = (pair.value * 100).rounded() / 100
        }
        let payload: [String: Any] = [
            "totalEur": rounded,
            "count": expenses.count,
            "byCategory": categories,
            "ts": ISO8601DateFormatter().string(from: Date()),
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Config.livePostSecret, forHTTPHeaderField: "x-live-secret")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        req.timeoutInterval = 10

        Task { _ = try? await URLSession.shared.data(for: req) }
    }
}
