import SwiftUI

struct AppRootView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(AppSession.self) private var app
    @Environment(\.scenePhase) private var phase
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
                        description: Text("Shared expenses and invitations are coming next.")
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
        .task(id: app.profileKey) { await app.synchronize() }
        .onChange(of: store.saveCount) { Task { await app.synchronize() } }
        .onChange(of: phase) { if phase == .active { Task { await app.synchronize() } } }
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
