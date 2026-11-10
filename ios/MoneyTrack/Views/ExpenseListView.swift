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
                || categoryName($0).localizedStandardContains(search)
        }
    }
    var body: some View {
        List {
            Section { MonthSelector(month: $month) }
            Section {
                LabeledContent("Your spending") {
                    Text(Money.format(-monthExpenses.reduce(0) { $0 + $1.budgetSpending }))
                        .foregroundStyle(AmountColors.negative).monospacedDigit()
                }
            }
            if monthExpenses.contains(where: \.isIncome) {
                Section {
                    LabeledContent("Income") {
                        Text("+" + Money.format(monthExpenses.filter(\.isIncome).reduce(0) { $0 + $1.amount }))
                            .foregroundStyle(AmountColors.positive).monospacedDigit()
                    }
                }
            }
            if matching.isEmpty {
                Section {
                    ContentUnavailableView(
                        search.isEmpty ? "No bookings this month" : "No matching bookings",
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
                            } label: { ExpenseRow(expense: expense, category: categoryName(expense)) }
                            .accessibilityIdentifier("expense-row-\(expense.id.uuidString)")
                        }
                    }
                }
            }
        }
        .navigationTitle("Bookings")
        .searchable(text: $search, prompt: "Description or category")
    }
    private func categoryName(_ expense: ExpenseValue) -> String {
        store.categories.first { $0.id == expense.categoryID }
            .map { store.displayName(for: $0, year: expense.day.year) } ?? String(localized: "Category")
    }
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
        if after == 0 { return " " + String(localized: "After deletion, you are settled up.") }
        let person = SharedDisplay.person(shared.otherName)
        let amount = Money.format(abs(after))
        return " " + (after > 0
            ? String(localized: "After deletion, \(person) owes you \(amount).")
            : String(localized: "After deletion, you owe \(person) \(amount)."))
    }
    private func historyChanges(_ fields: [String: JSONValue], shared: SharedExpenseValue) -> String {
        fields.sorted(by: { $0.key < $1.key }).compactMap { key, value -> String? in
            switch (key, value) {
            case ("amount", .integer(let amount)): return String(localized: "Amount: \(Money.format(amount))")
            case ("description", .string(let text)): return String(localized: "Description: \(text)")
            case ("creatorSplit", .string(let split)):
                let title = PersonalSplit(rawValue: split)?.title ?? split
                return String(localized: "Share of \(SharedDisplay.person(shared.creatorName)): \(title)")
            case ("paidByCreator", .bool(let paid)):
                let name = paid ? shared.creatorName : shared.recipientName ?? shared.recipientEmail ?? String(localized: "Other person")
                return String(localized: "Paid by: \(SharedDisplay.person(name))")
            case ("conversion", _):
                guard let conversion = try? value.decoded(CurrencyConversion.self) else { return String(localized: "Currency: EUR") }
                return String(localized: "Original: \(conversion.originalDisplay) · ECB \(conversion.rateDate)")
            case ("day", _):
                guard let day = try? value.decoded(ExpenseDay.self) else { return nil }
                return String(localized: "Date: \(day.date.formatted(date: .abbreviated, time: .omitted))")
            default: return nil
            }
        }.joined(separator: " · ")
    }
    private func historyAction(_ action: String) -> String {
        switch action {
        case "shared": String(localized: "Shared")
        case "accepted": String(localized: "Accepted")
        case "edited": String(localized: "Edited")
        case "deleted": String(localized: "Deleted")
        default: action
        }
    }
    var body: some View {
        List {
            if let expense {
                Section {
                    LabeledContent(expense.isIncome ? "Income" : "Total purchase") {
                        Text(Money.format(expense.amount)).font(.body.weight(.semibold)).monospacedDigit()
                    }
                    LabeledContent("Your budget impact") {
                        Text(Money.format(-expense.budgetSpending)).font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(expense.budgetSpending > 0 ? AmountColors.negative : .primary)
                    }
                    LabeledContent("Description", value: expense.description.isEmpty ? "—" : SharedDisplay.title(expense.description))
                    LabeledContent("Category", value: store.categories.first { $0.id == expense.categoryID }.map { store.displayName(for: $0, year: expense.day.year) } ?? String(localized: "Category"))
                    if let conversion = expense.conversion {
                        LabeledContent("Original amount", value: conversion.originalDisplay)
                        LabeledContent("Exchange rate", value: "1 EUR = \(conversion.rate) \(conversion.originalCurrency)")
                        LabeledContent("Rate date", value: "\(conversion.rateDate) · ECB")
                    }
                    LabeledContent("Date", value: expense.day.date.formatted(date: .abbreviated, time: .omitted))
                    if !expense.isIncome { LabeledContent("Paid by", value: shared.map { $0.paidByUser ? String(localized: "You") : SharedDisplay.person($0.otherName) } ?? String(localized: "You")) }
                    LabeledContent("Sharing", value: shared.map { $0.status == "pending" ? String(localized: "Awaiting acceptance") : String(localized: "Shared with \(SharedDisplay.person($0.otherName))") } ?? String(localized: "Personal"))
                }
            }
            if let shared {
                if shared.deleted { Section { Text("This shared expense was deleted. Its spending and obligation have been removed.") } }
                Section("Shared history") {
                    ForEach(shared.history.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(SharedDisplay.person(entry.actorName)) · \(historyAction(entry.action))").font(.body.weight(.medium))
                            Text(entry.at.formatted(date: .abbreviated, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                            if case .object(let fields) = entry.changes, !fields.isEmpty {
                                Text(historyChanges(fields, shared: shared)).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(expense?.isIncome == true ? "Income" : "Expense")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("Expense Actions", systemImage: "ellipsis.circle") {
                    if shared == nil && expense?.isIncome != true && app.credential != nil { Button("Share Expense", systemImage: "person.2") { sharing = true }.accessibilityIdentifier("expense.share") }
                    Button(expense?.isIncome == true ? "Edit Income" : "Edit Expense", systemImage: "pencil") { editing = true }
                    Button(expense?.isIncome == true ? "Delete Income" : "Delete Expense", systemImage: "trash", role: .destructive) { deleting = true }
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
        .confirmationDialog(expense?.isIncome == true ? "Delete this income?" : "Delete this expense?", isPresented: $deleting, titleVisibility: .visible) {
            Button(expense?.isIncome == true ? "Delete Income" : "Delete Expense", role: .destructive) {
                do { try store.deleteExpense(expenseID); dismiss() }
                catch { self.error = error.localizedDescription }
            }
        } message: { Text(shared == nil ? (expense?.isIncome == true ? "This income booking will be removed. Your budget stays unchanged." : "Its spending will be removed from your budget.") : "Both people lose this expense’s budget impact and obligation. Recorded repayments stay in the balance history.\(deletionBalance)") }
        .alert("Couldn't Delete Expense", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
    }
}
