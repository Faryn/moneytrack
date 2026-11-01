import SwiftUI

struct BudgetView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(AppSession.self) private var app
    @Binding var month: BudgetMonth
    let openYearlyPlan: () -> Void
    private var overview: [CategoryBudget] { store.overview(month: month) }
    private var hasPlan: Bool { overview.contains { $0.annual != nil } }

    var body: some View {
        List {
            Section { MonthSelector(month: $month) }
            if !store.issues.isEmpty {
                Section {
                    NavigationLink { SyncReviewList() } label: {
                        Label("Changes need review", systemImage: "exclamationmark.triangle")
                    }
                }
            }
            if hasPlan {
                Section {
                    RemainingAmount(amount: overview.reduce(0) { $0 + $1.remaining }, large: true)
                        .padding(.vertical, 8)
                    LabeledContent("Monthly budget", value: Money.format(overview.reduce(0) { $0 + $1.allocation }))
                    LabeledContent("Carried forward") {
                        let carryover = overview.reduce(Int64(0)) { $0 + $1.carryover }
                        Text(Money.format(carryover)).foregroundStyle(AmountColors.remaining(carryover))
                    }
                    LabeledContent("Your spending") {
                        Text(Money.format(-overview.reduce(0) { $0 + $1.spent }))
                            .foregroundStyle(AmountColors.negative)
                    }
                } footer: {
                    Text("Includes carryover since January. Only your share of spending counts.")
                }
            } else {
                Section {
                    ContentUnavailableView {
                        Label("Set your yearly budget", systemImage: "chart.pie")
                    } description: {
                        Text("Add yearly amounts for your categories to see what's left each month.")
                    } actions: {
                        Button("Set Up Budget", action: openYearlyPlan)
                            .accessibilityIdentifier("budget.setup")
                    }
                }
            }
            if !overview.isEmpty {
                Section {
                    ForEach(overview) { item in
                        NavigationLink {
                            CategoryDetailView(categoryID: item.id, month: month)
                        } label: {
                            CategoryBudgetRow(item: item)
                        }
                        .accessibilityIdentifier("category-\(item.category.name)")
                    }
                } header: {
                    Text("Categories")
                }
            }
            Section {
                Button("Yearly Plan", action: openYearlyPlan)
                    .accessibilityIdentifier("budget.yearly-plan")
            }
        }
        .navigationTitle("Budget")
        .refreshable { await app.synchronize() }
    }
}

private struct CategoryBudgetRow: View {
    let item: CategoryBudget
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if typeSize.isAccessibilitySize {
                nameAndSpending
                balance
            } else {
                HStack(alignment: .firstTextBaseline) {
                    nameAndSpending
                    Spacer(minLength: 8)
                    balance
                }
            }
            if item.annual != nil && item.available > 0 {
                ProgressView(value: min(Double(item.spent), Double(item.available)), total: Double(item.available))
                    .tint(item.remaining < 0 ? AmountColors.negative : AmountColors.positive)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
    private var nameAndSpending: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.category.name).foregroundStyle(.primary)
            Text(item.annual == nil
                 ? "\(Money.format(item.spent)) spent · No yearly budget"
                 : "\(Money.format(item.spent)) spent of \(Money.format(item.available)) available")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var balance: some View {
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
            if item.annual != nil || item.remaining < 0 {
                Text(Money.format(abs(item.remaining)))
                    .font(.headline).monospacedDigit()
                    .foregroundStyle(AmountColors.remaining(item.remaining))
                Text(item.remaining < 0 ? "over budget" : "left")
                    .font(.caption).foregroundStyle(AmountColors.remaining(item.remaining))
            } else {
                Text("Set budget").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

struct CategoryDetailView: View {
    @Environment(LedgerStore.self) private var store
    let categoryID: UUID
    let month: BudgetMonth
    @State private var addingExpense = false

    private var category: CategoryValue? { store.categories.first { $0.id == categoryID } }
    private var item: CategoryBudget? { store.overview(month: month).first { $0.id == categoryID } }
    private var expenses: [ExpenseValue] {
        store.expenses.filter { $0.categoryID == categoryID && $0.day.year == month.year && $0.day.month == month.month }
    }

    var body: some View {
        List {
            if let item, let category {
                Section(month.title) {
                    if item.annual != nil || item.spent > 0 { RemainingAmount(amount: item.remaining) }
                    LabeledContent("Monthly allocation", value: Money.format(item.allocation))
                    LabeledContent("Carried forward", value: Money.format(item.carryover))
                    LabeledContent("Your spending") {
                        Text(Money.format(-item.spent)).foregroundStyle(AmountColors.negative)
                    }
                    NavigationLink("Edit Yearly Budget") {
                        CategoryEditor(category: category, year: month.year)
                    }
                }
                Section("Expenses") {
                    if expenses.isEmpty {
                        Text("No expenses this month").foregroundStyle(.secondary)
                    } else {
                        ForEach(expenses) { expense in
                            NavigationLink {
                                ExpenseDetailView(expenseID: expense.id)
                            } label: { ExpenseRow(expense: expense, category: category.name) }
                        }
                    }
                }
            }
        }
        .navigationTitle(category?.name ?? "Category")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Expense", systemImage: "plus") { addingExpense = true }
            }
        }
        .sheet(isPresented: $addingExpense) {
            NavigationStack { ExpenseForm(categoryID: categoryID, today: store.today) }
        }
    }
}
