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
    @Environment(AppSession.self) private var app
    @State private var sharing = false
    @State private var editing = false
    @State private var deleting = false
    @State private var error: String?
    private var shared: SharedExpenseValue? { store.sharedExpenses.first { $0.id == expenseID } }
    private var expense: ExpenseValue? { store.expenses.first { $0.id == expenseID } }

    private var deletionBalance: String {
        guard let shared, let connection = shared.connection,
              let before = try? store.sharedBalance(connection.id), let change = try? shared.amounts.balance else { return "" }
        let after = before - change
        if after == 0 { return " After deletion, you are settled up." }
        return after > 0 ? " After deletion, \(shared.otherName) owes you \(Money.format(after))." :
            " After deletion, you owe \(shared.otherName) \(Money.format(-after))."
    }
    private func historyChanges(_ fields: [String: JSONValue], shared: SharedExpenseValue) -> String {
        fields.sorted(by: { $0.key < $1.key }).compactMap { key, value -> String? in
            switch (key, value) {
            case ("amount", .integer(let amount)): return "Amount: \(Money.format(amount))"
            case ("description", .string(let text)): return "Description: \(text)"
            case ("creatorSplit", .string(let split)): return "\(shared.creatorName)'s share: \(split.capitalized)"
            case ("paidByCreator", .bool(let paid)): return "Paid by: \(paid ? shared.creatorName : shared.recipientName ?? shared.recipientEmail ?? "Other person")"
            case ("day", _):
                guard let day = try? value.decoded(ExpenseDay.self) else { return nil }
                return "Date: \(day.date.formatted(date: .abbreviated, time: .omitted))"
            default: return nil
            }
        }.joined(separator: " · ")
    }
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
                    LabeledContent("Paid by", value: shared.map { $0.paidByUser ? "You" : $0.otherName } ?? "You")
                    LabeledContent("Sharing", value: shared.map { $0.status == "pending" ? "Awaiting acceptance" : "Shared with \($0.otherName)" } ?? "Personal")
                }
            }
            if let shared {
                if shared.deleted { Section { Text("This shared expense was deleted. Its spending and obligation have been removed.") } }
                Section("Shared History") {
                    ForEach(shared.history.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(entry.actorName) · \(entry.action.capitalized)")
                            Text(entry.at.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            if case .object(let fields) = entry.changes, !fields.isEmpty {
                                Text(historyChanges(fields, shared: shared)).font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Expense")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("Expense Actions", systemImage: "ellipsis.circle") {
                    if shared == nil && app.credential != nil { Button("Share Expense", systemImage: "person.2") { sharing = true }.accessibilityIdentifier("expense.share") }
                    Button("Edit Expense", systemImage: "pencil") { editing = true }
                    Button("Delete Expense", systemImage: "trash", role: .destructive) { deleting = true }
                }
                .disabled(shared?.deleted == true)
                .accessibilityIdentifier("expense.actions")
            }
        }
        .sheet(isPresented: $editing) {
            if let shared { NavigationStack { SharedExpenseEditor(value: shared) } }
            else if let expense { NavigationStack { ExpenseForm(expense: expense, today: store.today) } }
        }
        .sheet(isPresented: $sharing) { if let expense { NavigationStack { ShareExpenseForm(expense: expense) } } }
        .confirmationDialog("Delete this expense?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete Expense", role: .destructive) {
                do { try store.deleteExpense(expenseID); dismiss() }
                catch { self.error = error.localizedDescription }
            }
        } message: { Text(shared == nil ? "Its spending will be removed from your budget." : "Both people lose this expense’s budget impact and obligation. Recorded repayments stay in the balance history.\(deletionBalance)") }
        .alert("Couldn't Delete Expense", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
    }
}
