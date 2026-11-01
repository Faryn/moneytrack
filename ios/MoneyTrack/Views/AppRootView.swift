import SwiftUI

struct AppRootView: View {
    @Environment(LedgerStore.self) private var store
    @State private var month: BudgetMonth
    @State private var selectedTab = AppTab.budget
    @State private var sheet: RootSheet?

    init(store: LedgerStore) {
        _month = State(initialValue: BudgetMonth(date: store.today))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Budget", systemImage: "chart.pie", value: AppTab.budget) {
                NavigationStack {
                    BudgetView(month: $month, openYearlyPlan: { sheet = .yearly(month.year) })
                        .toolbar { EntryToolbar(add: { sheet = .expense }, account: { sheet = .account }) }
                }
            }
            Tab("Expenses", systemImage: "list.bullet", value: AppTab.expenses) {
                NavigationStack {
                    ExpenseListView(month: $month)
                        .toolbar { EntryToolbar(add: { sheet = .expense }, account: { sheet = .account }) }
                }
            }
            Tab("Shared", systemImage: "person.2", value: AppTab.shared) {
                NavigationStack {
                    ContentUnavailableView(
                        "No shared expenses", systemImage: "person.2",
                        description: Text("Shared expenses and balances will appear here when your account is connected.")
                    )
                    .navigationTitle("Shared")
                    .toolbar { EntryToolbar(add: { sheet = .expense }, account: { sheet = .account }) }
                }
            }
        }
        .sheet(item: $sheet) { destination in
            NavigationStack {
                switch destination {
                case .expense: ExpenseForm(today: store.today)
                case .yearly(let year): YearlyPlanView(year: year)
                case .account: AccountView()
                }
            }
        }
        .sensoryFeedback(.success, trigger: store.saveCount)
    }
}

private enum AppTab: Hashable { case budget, expenses, shared }
private enum RootSheet: Identifiable {
    case expense, yearly(Int), account
    var id: String {
        switch self {
        case .expense: "expense"
        case .yearly(let year): "yearly-\(year)"
        case .account: "account"
        }
    }
}

struct EntryToolbar: ToolbarContent {
    let add: () -> Void
    let account: () -> Void
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Account", systemImage: "person.crop.circle", action: account)
                .accessibilityIdentifier("account.open")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Add Expense", systemImage: "plus", action: add)
                .accessibilityIdentifier("expense.add")
        }
    }
}

private struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section {
                LabeledContent("Storage", value: "On this iPhone")
                LabeledContent("Account", value: "Not connected")
            } footer: {
                Text("Your expenses are saved on this iPhone. They aren't backed up to a MoneyTrack account yet.")
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")
            }
        }
        .navigationTitle("Account")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") { dismiss() }
            }
        }
    }
}
