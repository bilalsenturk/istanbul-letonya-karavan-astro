import AppIntents
import Foundation

// Siri / Kısayollar / Spotlight entegrasyonu + Sürüş Focus filtresi.
// "Hey Siri, Kuzey harcama ekle" → tutar/kategori sorup cihazdaki deftere yazar.

enum ExpenseCategoryAppEnum: String, AppEnum {
    case yakit, kamp, yemek, gecis, diger

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Kategori")
    static let caseDisplayRepresentations: [ExpenseCategoryAppEnum: DisplayRepresentation] = [
        .yakit: "Yakıt", .kamp: "Kamp", .yemek: "Yemek", .gecis: "Geçiş", .diger: "Diğer",
    ]

    var model: ExpenseCategory { ExpenseCategory(rawValue: rawValue) ?? .diger }
}

struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Harcama Ekle"
    static let description = IntentDescription("Kuzey yolculuk defterine harcama ekler.")

    @Parameter(title: "Tutar (€)")
    var amount: Double

    @Parameter(title: "Kategori")
    var category: ExpenseCategoryAppEnum

    @Parameter(title: "Not")
    var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$amount) € \(\.$category) ekle") {
            \.$note
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0 else {
            return .result(dialog: "Tutar 0'dan büyük olmalı.")
        }
        guard amount < 100_000 else {
            return .result(dialog: "Tutar 100.000 €'dan küçük olmalı.")
        }
        ExpenseStore.appendDirect(Expense(amountEur: amount, category: category.model, note: note ?? ""))
        let shown = amount.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(amount)) : String(format: "%.2f", amount)
        return .result(dialog: "€\(shown) \(category.model.label) eklendi. İyi yolculuklar!")
    }
}

struct NextStopIntent: AppIntent {
    static let title: LocalizedStringResource = "Sıradaki Durak"
    static let description = IntentDescription("Sıradaki durağı ve kalan mesafeyi söyler.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let d = SharedSnapshot.defaults
        guard let stop = d?.string(forKey: SharedSnapshot.Key.nextStop) else {
            return .result(dialog: "Henüz canlı yolculuk verisi yok.")
        }
        var text = "Sıradaki durak \(stop)"
        if let km = d?.object(forKey: SharedSnapshot.Key.remainingKm) as? Int {
            text += ", \(km) kilometre"
        }
        if let m = d?.object(forKey: SharedSnapshot.Key.remainingMin) as? Int {
            text += m >= 60 ? ", yaklaşık \(m / 60) saat \(m % 60) dakika" : ", yaklaşık \(m) dakika"
        }
        // Saatler önceki veriyi güncel gibi söyleme.
        if !SharedSnapshot.isFresh {
            text += ". Bu bilgi güncel olmayabilir — uygulamayı açınca tazelenir"
        }
        return .result(dialog: "\(text).")
    }
}

struct KuzeyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "\(.applicationName) harcama ekle",
                "\(.applicationName) ile harcama ekle",
                "\(.applicationName) masraf ekle",
            ],
            shortTitle: "Harcama Ekle",
            systemImageName: "eurosign.circle.fill"
        )
        AppShortcut(
            intent: NextStopIntent(),
            phrases: [
                "\(.applicationName) sıradaki durak",
                "\(.applicationName) ne kadar kaldı",
            ],
            shortTitle: "Sıradaki Durak",
            systemImageName: "map.fill"
        )
    }
}

// Sürüş Focus'una eklenebilen filtre: açılınca panel sadeleşir (Ayarlar > Odak >
// Sürüş > Odak Filtreleri > Kuzey). Odak kapanınca sistem varsayılana döndürür.
struct DrivingFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Kuzey Sade Sürüş Modu"
    static let description = IntentDescription("Sürüş sırasında paneli sadeleştirir: yalnızca canlı yol bilgisi kalır.")

    @Parameter(title: "Sade mod", default: false)
    var simpleMode: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Sade mod", subtitle: simpleMode ? "Açık" : "Kapalı")
    }

    func perform() async throws -> some IntentResult {
        SharedSnapshot.write([SharedSnapshot.Key.simpleMode: simpleMode])
        return .result()
    }
}
