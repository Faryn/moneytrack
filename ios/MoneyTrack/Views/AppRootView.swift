import SwiftUI

struct AppRootView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(AppSession.self) private var app
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var month: BudgetMonth
    @State private var selectedTab = AppTab.budget
    @State private var sheet: RootSheet?
    @State private var quickEntry = false

    init(store: LedgerStore) {
        _month = State(initialValue: BudgetMonth(date: store.today))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Budget", systemImage: "chart.pie", value: AppTab.budget) {
                ledgerNavigation("Select a Category", systemImage: "chart.pie") {
                    BudgetView(month: $month, openYearlyPlan: { sheet = .yearly(month.year) })
                        .toolbar { EntryToolbar(account: { sheet = .account }) }
                }
            }
            Tab("Expenses", systemImage: "list.bullet", value: AppTab.expenses) {
                ledgerNavigation("Select a Booking", systemImage: "list.bullet", showsAdd: true) {
                    ExpenseListView(month: $month)
                        .toolbar { EntryToolbar(account: { sheet = .account }) }
                }
            }
            Tab("Shared", systemImage: "person.2", value: AppTab.shared) {
                ledgerNavigation("Select a Person", systemImage: "person.2") {
                    SharedHomeView()
                        .toolbar { EntryToolbar(account: { sheet = .account }) }
                }
            }
        }
        .sheet(item: $sheet) { destination in
            NavigationStack {
                switch destination {
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

    @ViewBuilder
    private func ledgerNavigation<Content: View>(
        _ prompt: LocalizedStringKey,
        systemImage: String,
        showsAdd: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            NavigationSplitView {
                content()
                    .listStyle(.insetGrouped)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if showsAdd { addExpense }
                    }
                    .navigationSplitViewColumnWidth(min: 320, ideal: 420, max: 500)
            } detail: {
                ContentUnavailableView(prompt, systemImage: systemImage)
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            NavigationStack { content() }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if showsAdd { addExpense }
                }
        }
    }

    private var addExpense: some View {
        HStack {
            Spacer()
            if typeSize.isAccessibilitySize {
                ReachableExpenseButton { quickEntry = true }
                    .sheet(isPresented: $quickEntry) { QuickExpenseEntry() }
            } else {
                ReachableExpenseButton { quickEntry = true }
                    .popover(isPresented: $quickEntry, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                        QuickExpenseEntry()
                            .presentationCompactAdaptation(.popover)
                    }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
    }
}

private enum AppTab: Hashable { case budget, expenses, shared }
private enum RootSheet: Identifiable {
    case yearly(Int), account
    var id: String {
        switch self {
        case .yearly(let year): "yearly-\(year)"
        case .account: "account"
        }
    }
}

struct EntryToolbar: ToolbarContent {
    @Environment(AppSession.self) private var app
    let account: () -> Void
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Account", systemImage: "person.crop.circle", action: account)
                .accessibilityIdentifier("account.open")
                .accessibilityLabel(app.credential.map { String(localized: "Account, signed in as \($0.username)") } ?? String(localized: "Account"))
        }
    }
}

struct ReachableExpenseButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activations = 0
    let action: () -> Void
    var body: some View {
        Button {
            activations += 1
            action()
        } label: {
            Label("Add Expense", systemImage: "plus")
                .labelStyle(.iconOnly)
                .font(.title2.weight(.semibold)).frame(width: 28, height: 28)
                .symbolEffect(.bounce, value: activations)
                .symbolEffectsRemoved(reduceMotion)
        }
        .buttonStyle(.borderedProminent).buttonBorderShape(.circle).controlSize(.large)
        .accessibilityIdentifier("expense.add")
        .sensoryFeedback(.selection, trigger: activations)
    }
}
