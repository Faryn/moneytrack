import SwiftUI

struct ExpenseListView: View {
    @Environment(LedgerStore.self) private var store
    @Binding var month: BudgetMonth
    @State private var search = ""

    private var monthExpenses: [ExpenseValue] {
        store.expenses.filter { $0.day.year == month.year && $0.day.month == month.month }
    }
    private var matching: [ExpenseValue] {
        monthExpenses.filter {
            search.isEmpty || $0.description.localizedStandardContains(search)
                || categoryName($0.categoryID).localizedStandardContains(search)
        }
    }
    var body: some View {
        List {
            Section { MonthSelector(month: $month) }
            Section {
                LabeledContent("Your spending") {
                    Text(Money.format(-monthExpenses.reduce(0) { $0 + $1.personalShare }))
                        .foregroundStyle(AmountColors.negative).monospacedDigit()
                }
            }
            if matching.isEmpty {
                Section {
                    ContentUnavailableView(
                        search.isEmpty ? "No expenses this month" : "No matching expenses",
                        systemImage: search.isEmpty ? "list.bullet" : "magnifyingglass",
                        description: Text(search.isEmpty ? "Tap + to add an expense." : "Try a different description or category.")
                    )
                }
            } else {
                ForEach(Array(Set(matching.map(\.day))).sorted(by: >), id: \.self) { day in
                    Section(day.date.formatted(date: .abbreviated, time: .omitted)) {
                        ForEach(matching.filter { $0.day == day }) { expense in
                            NavigationLink {
                                ExpenseDetailView(expenseID: expense.id)
                            } label: { ExpenseRow(expense: expense, category: categoryName(expense.categoryID)) }
                            .accessibilityIdentifier("expense-row-\(expense.id.uuidString)")
                        }
                    }
                }
            }
        }
        .navigationTitle("Expenses")
        .searchable(text: $search, prompt: "Description or category")
    }
    private func categoryName(_ id: UUID) -> String { store.categories.first { $0.id == id }?.name ?? "Category" }
}

struct ExpenseDetailView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let expenseID: UUID
    @State private var editing = false
    @State private var deleting = false
    @State private var error: String?
    private var expense: ExpenseValue? { store.expenses.first { $0.id == expenseID } }

    var body: some View {
        List {
            if let expense {
                Section {
                    LabeledContent("Total purchase") {
                        Text(Money.format(expense.amount)).font(.title2).monospacedDigit()
                    }
                    LabeledContent("Your budget impact") {
                        Text(Money.format(-expense.personalShare)).foregroundStyle(AmountColors.negative)
                    }
                    LabeledContent("Description", value: expense.description.isEmpty ? "—" : expense.description)
                    LabeledContent("Category", value: store.categories.first { $0.id == expense.categoryID }?.name ?? "Category")
                    LabeledContent("Date", value: expense.day.date.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("Paid by", value: "You")
                    LabeledContent("Sharing", value: "Personal")
                }
            }
        }
        .navigationTitle("Expense")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("Expense Actions", systemImage: "ellipsis.circle") {
                    Button("Edit Expense", systemImage: "pencil") { editing = true }
                    Button("Delete Expense", systemImage: "trash", role: .destructive) { deleting = true }
                }
                .accessibilityIdentifier("expense.actions")
            }
        }
        .sheet(isPresented: $editing) {
            if let expense { NavigationStack { ExpenseForm(expense: expense, today: store.today) } }
        }
        .confirmationDialog("Delete this expense?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete Expense", role: .destructive) {
                do { try store.deleteExpense(expenseID); dismiss() }
                catch { self.error = error.localizedDescription }
            }
        } message: { Text("Its spending will be removed from your budget.") }
        .alert("Couldn't Delete Expense", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
    }
}
