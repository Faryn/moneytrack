import SwiftUI

struct BudgetView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(AppSession.self) private var app
    @Binding var month: BudgetMonth
    let openYearlyPlan: () -> Void
    private var overview: [CategoryBudget] { store.overview(month: month) }
    private var plan: AnnualBudgetPlan? { store.annualPlan(year: month.year) }
    private var whole: AnnualBudgetOverview? { try? store.wholeBudget(month: month) }
    private var hasPlan: Bool { plan != nil || overview.contains { ($0.annual ?? 0) > 0 } }
    private var totals: BudgetAmounts {
        whole?.total ?? BudgetAmounts(allocation: overview.reduce(0) { $0 + $1.allocation }, carryover: overview.reduce(0) { $0 + $1.carryover }, spent: overview.reduce(0) { $0 + $1.spent })
    }

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
            if plan != nil && whole == nil {
                Section { ContentUnavailableView("Couldn't calculate this budget", systemImage: "exclamationmark.triangle", description: Text("Your entries are preserved. Review the yearly plan before continuing.")) }
            } else if hasPlan {
                Section {
                    RemainingAmount(amount: totals.remaining, large: true)
                        .padding(.vertical, 8)
                    BudgetSupportingAmounts(amounts: totals)
                }
            } else {
                Section {
                    ContentUnavailableView {
                        Label("Set your yearly budget", systemImage: "chart.pie")
                    } description: {
                        Text("Pick your whole yearly budget first, then assign parts to categories. The rest is guilt-free spending.")
                    } actions: {
                        Button("Set Up Budget", action: openYearlyPlan)
                            .accessibilityIdentifier("budget.setup")
                    }
                }
            }
            if let whole {
                Section {
                    NavigationLink { GuiltFreeDetailView(month: month) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Guilt-free spending").font(.headline).foregroundStyle(.primary)
                            Text("\(Money.format(abs(whole.guiltFree.remaining))) \(whole.guiltFree.remaining < 0 ? "over budget" : "left")")
                                .font(.title2).foregroundStyle(AmountColors.remaining(whole.guiltFree.remaining)).monospacedDigit()
                                .contentTransition(.numericText()).accessibilityIdentifier("budget.guilt-free.remaining")
                                .accessibilityValue(Money.format(whole.guiltFree.remaining))
                            Text("Unassigned budget · \(Money.format(whole.guiltFree.spent)) spent this month").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("budget.guilt-free")
                }
            }
            if !overview.filter({ $0.id != plan?.freeCategoryID }).isEmpty {
                Section {
                    ForEach(overview.filter { $0.id != plan?.freeCategoryID }) { item in
                        NavigationLink {
                            CategoryDetailView(categoryID: item.id, month: month)
                        } label: {
                            CategoryBudgetRow(item: item, usesGuiltFree: plan != nil && item.annual == nil)
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
        .listSectionSpacing(16)
        .navigationTitle("Budget")
        .refreshable { await app.synchronize() }
    }
}

private struct BudgetSupportingAmounts: View {
    let amounts: BudgetAmounts
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if !typeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: 16) {
                    metric("Monthly budget", amount: amounts.allocation, color: .primary)
                    Spacer(minLength: 0)
                    metric("Carried forward", amount: amounts.carryover, color: AmountColors.remaining(amounts.carryover))
                    Spacer(minLength: 0)
                    metric("Your spending", amount: -amounts.spent, color: AmountColors.negative)
                }
            }
            VStack(spacing: 8) {
                LabeledContent("Monthly budget", value: Money.format(amounts.allocation))
                LabeledContent("Carried forward") {
                    Text(Money.format(amounts.carryover)).foregroundStyle(AmountColors.remaining(amounts.carryover))
                }
                LabeledContent("Your spending") {
                    Text(Money.format(-amounts.spent)).foregroundStyle(AmountColors.negative)
                }
            }
        }
    }

    private func metric(_ title: String, amount: Int64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Money.format(amount)).font(.subheadline).monospacedDigit().foregroundStyle(color)
        }
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

private struct CategoryBudgetRow: View {
    let item: CategoryBudget
    var usesGuiltFree = false
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
            Text(usesGuiltFree ? "\(Money.format(item.spent)) spent · Guilt-free pool" : item.annual == nil
                 ? "\(Money.format(item.spent)) spent · No yearly budget"
                 : "\(Money.format(item.spent)) spent of \(Money.format(item.available)) available")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var balance: some View {
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
            if usesGuiltFree {
                Text("Guilt-free").font(.subheadline).foregroundStyle(.secondary)
            } else if item.annual != nil || item.remaining < 0 {
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

    private var category: CategoryValue? { store.categories.first { $0.id == categoryID } }
    private var item: CategoryBudget? { store.overview(month: month).first { $0.id == categoryID } }
    private var expenses: [ExpenseValue] {
        store.expenses.filter { $0.categoryID == categoryID && $0.day.year == month.year && $0.day.month == month.month }
    }

    var body: some View {
        List {
            if let item, let category {
                Section(month.title) {
                    if store.annualPlan(year: month.year) != nil && item.annual == nil {
                        Text("This category uses guilt-free spending.").foregroundStyle(.secondary)
                        NavigationLink("View Guilt-free Pool") { GuiltFreeDetailView(month: month) }
                    } else {
                        if item.annual != nil || item.spent > 0 { RemainingAmount(amount: item.remaining) }
                        LabeledContent("Monthly allocation", value: Money.format(item.allocation))
                        LabeledContent("Carried forward", value: Money.format(item.carryover))
                    }
                    LabeledContent("Your spending") {
                        Text(Money.format(-item.spent)).foregroundStyle(AmountColors.negative)
                    }
                    NavigationLink("Edit Yearly Allocation") { CategoryEditor(category: category, year: month.year) }
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
    }
}

struct GuiltFreeDetailView: View {
    @Environment(LedgerStore.self) private var store
    let month: BudgetMonth
    private var result: BudgetAmounts? { (try? store.wholeBudget(month: month))?.guiltFree }
    private var expenses: [ExpenseValue] {
        let allocated = Set(store.annualPlan(year: month.year)?.allocations.map(\.categoryID) ?? [])
        return store.expenses.filter { $0.day.year == month.year && $0.day.month == month.month && !allocated.contains($0.categoryID) }
    }
    var body: some View {
        List {
            if let result {
                Section {
                    RemainingAmount(amount: result.remaining)
                    LabeledContent("Monthly allocation", value: Money.format(result.allocation))
                    LabeledContent("Carried forward", value: Money.format(result.carryover))
                    LabeledContent("Your spending", value: Money.format(-result.spent))
                } header: {
                    Text(month.title)
                } footer: {
                    Text("Categories without their own allocation share this pool. Overspending in an allocated category stays with that category and reduces the overall balance.")
                }
            }
            Section("Expenses from This Pool") {
                if expenses.isEmpty { Text("No guilt-free expenses this month").foregroundStyle(.secondary) }
                ForEach(expenses) { e in
                    NavigationLink { ExpenseDetailView(expenseID: e.id) } label: {
                        ExpenseRow(expense: e, category: store.categories.first { $0.id == e.categoryID }?.name ?? "Uncategorized")
                    }
                }
            }
        }.navigationTitle("Guilt-free Spending")
    }
}
