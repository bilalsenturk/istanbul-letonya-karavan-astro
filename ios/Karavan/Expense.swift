import SwiftUI

// Yol harcamaları — tümü EUR. Kalemler yalnızca cihazda tutulur (ExpenseStore);
// web'e yalnızca toplam gönderilir.
enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case yakit, kamp, yemek, gecis, diger

    var id: String { rawValue }

    var label: String {
        switch self {
        case .yakit: return "Yakıt"
        case .kamp: return "Kamp"
        case .yemek: return "Yemek"
        case .gecis: return "Geçiş"
        case .diger: return "Diğer"
        }
    }

    var icon: String {
        switch self {
        case .yakit: return "fuelpump.fill"
        case .kamp: return "tent.fill"
        case .yemek: return "fork.knife"
        case .gecis: return "road.lanes"
        case .diger: return "ellipsis.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .yakit: return Theme.c1
        case .kamp: return Theme.c4
        case .yemek: return Theme.c2
        case .gecis: return Theme.c3
        case .diger: return Theme.muted
        }
    }
}

struct Expense: Codable, Identifiable {
    let id: UUID
    var amountEur: Double
    var category: ExpenseCategory
    var note: String
    var date: Date

    init(id: UUID = UUID(),
         amountEur: Double,
         category: ExpenseCategory,
         note: String = "",
         date: Date = Date()) {
        self.id = id
        self.amountEur = amountEur
        self.category = category
        self.note = note
        self.date = date
    }
}
