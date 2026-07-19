import SwiftUI

struct ExpensesView: View {
    @EnvironmentObject var store: TripStore
    @EnvironmentObject var expenses: ExpenseStore
    @State private var showAdd = false

    private var ceiling: Double { Double(store.trip?.totalBudget.max ?? 1795) }
    private var ratio: Double { ceiling > 0 ? min(1, expenses.total / ceiling) : 0 }
    private var percent: Int { Int((ratio * 100).rounded()) }
    private var remaining: Double { max(0, ceiling - expenses.total) }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            List {
                Section {
                    summaryCard
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if !expenses.byCategory.isEmpty {
                    Section {
                        breakdownCard
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }

                Section {
                    if expenses.expenses.isEmpty {
                        Text("Henüz harcama yok. Sağ üstteki + ile ekle.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.muted)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(expenses.expenses) { expense in
                            ExpenseRow(expense: expense)
                                .listRowBackground(Color.clear)
                        }
                        .onDelete { expenses.delete(at: $0) }
                    }
                } header: {
                    Text("Kalemler").foregroundStyle(Theme.muted)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Harcamalar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 21))
                }
                .tint(Theme.c2)
            }
        }
        .sheet(isPresented: $showAdd) {
            AddExpenseSheet { expenses.add($0) }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Özet

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoLabel(text: "Toplam harcanan", color: Theme.c1)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("€\(expenses.total, specifier: "%.0f")")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text("/ €\(ceiling, specifier: "%.0f")")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            budgetBar
            HStack {
                Text("%\(percent) harcandı")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(percent >= 100 ? Theme.bad : Theme.dim)
                Spacer()
                Text("kalan €\(remaining, specifier: "%.0f")")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.dim)
            }
            Text("Tahmini bütçe \(store.trip?.totalBudget.total ?? "€1.500 – €1.600")")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
        }
        .card()
    }

    private var budgetBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(percent >= 100 ? AnyShapeStyle(Theme.bad) : AnyShapeStyle(Theme.gradWarm))
                    .frame(width: geo.size.width * ratio)
            }
        }
        .frame(height: 10)
    }

    // MARK: - Kategori kırılımı

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoLabel(text: "Kategoriye göre", color: Theme.c4)
            ForEach(ExpenseCategory.allCases) { category in
                let value = expenses.total(for: category)
                if value > 0 {
                    HStack(spacing: 10) {
                        Image(systemName: category.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(category.color)
                            .frame(width: 22)
                        Text(category.label)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.dim)
                        Spacer()
                        Text("€\(value, specifier: "%.0f")")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.text)
                    }
                }
            }
        }
        .card()
    }
}

private struct ExpenseRow: View {
    let expense: Expense

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(expense.category.color.opacity(0.18)).frame(width: 38, height: 38)
                Image(systemName: expense.category.icon)
                    .font(.system(size: 15))
                    .foregroundStyle(expense.category.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.note.isEmpty ? expense.category.label : expense.note)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(expense.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Text("€\(expense.amountEur, specifier: "%.0f")")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Hızlı ekleme

struct AddExpenseSheet: View {
    var onAdd: (Expense) -> Void
    @EnvironmentObject var expenseStore: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    @State private var amount = ""
    @State private var category: ExpenseCategory = .yakit
    @State private var note = ""
    @State private var date = Date()
    @State private var addedCount = 0

    private var amountValue: Double? {
        Double(amount.replacingOccurrences(of: ",", with: "."))
    }
    private var canSave: Bool { (amountValue ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            MonoLabel(text: "Tutar (€)", color: Theme.c1)
                            HStack(spacing: 6) {
                                Text("€").font(.system(size: 34, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.muted)
                                TextField("0", text: $amount)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Theme.text)
                            }
                            .card()
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            MonoLabel(text: "Kategori", color: Theme.c4)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(ExpenseCategory.allCases) { c in
                                        categoryChip(c)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            MonoLabel(text: "Not (isteğe bağlı)", color: Theme.c3)
                            suggestionChips
                            TextField("örn. Kapıkule mazot", text: $note)
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.text)
                                .padding(14)
                                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            MonoLabel(text: "Tarih", color: Theme.c2)
                            DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                                .tint(Theme.c2)
                        }

                        Button {
                            addCurrent(keepOpen: true)
                        } label: {
                            Label("Ekle ve yeni ekle", systemImage: "plus.circle.fill")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(canSave ? Theme.c4 : Theme.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Theme.c4.opacity(canSave ? 0.14 : 0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.c4.opacity(canSave ? 0.5 : 0.15), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSave)

                        if addedCount > 0 {
                            Text("Bu oturumda \(addedCount) harcama eklendi")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.ok)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Harcama ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }.tint(Theme.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitir") {
                        addCurrent(keepOpen: false)
                    }
                    .font(.system(size: 16, weight: .bold))
                    .tint(Theme.c2)
                    .disabled(!canSave && addedCount == 0)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // Cihazda öğrenen akıllı öneri çipleri (geçmiş + kategori + sıra deseni)
    @ViewBuilder private var suggestionChips: some View {
        let suggestions = expenseStore.noteSuggestions(prefix: note, category: category)
        if !suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { s in
                        Button { note = s } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles").font(.system(size: 10))
                                Text(s).font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(Theme.c4)
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(Theme.c4.opacity(0.12), in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.c4.opacity(0.4), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func addCurrent(keepOpen: Bool) {
        if let v = amountValue, v > 0 {
            onAdd(Expense(amountEur: v,
                          category: category,
                          note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                          date: date))
            addedCount += 1
        }
        if keepOpen {
            amount = ""
            note = ""            // kategori ve tarih korunur → hızlı ardışık giriş
        } else {
            dismiss()
        }
    }

    private func categoryChip(_ c: ExpenseCategory) -> some View {
        let selected = c == category
        return Button {
            category = c
        } label: {
            Label(c.label, systemImage: c.icon)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(selected ? Color.black.opacity(0.85) : Theme.dim)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    selected ? AnyShapeStyle(c.color) : AnyShapeStyle(Theme.panel),
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(Theme.line, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }
}
