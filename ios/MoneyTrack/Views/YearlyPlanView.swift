import SwiftUI

struct YearlyPlanView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var year: Int
    @State private var total = ""
    @State private var loadedYear: Int?
    @State private var baselineTotal: Int64?
    @State private var confirmedPlan: AnnualBudgetPlan?
    @State private var expectedRevision: Int64 = 0
    @State private var allocations: [CategoryAllocation] = []
    @State private var error: String?
    @State private var confirm = false
    private var plan: AnnualBudgetPlan? { store.annualPlan(year: year) }
    private var parsed: Int64? { try? Money.parse(total, allowZero: true) }
    private var allocated: Int64 { (plan?.allocations ?? allocations).reduce(0) { $0 + $1.amount } }
    var body: some View {
        Form {
            Section { Stepper("Year \(String(year))", value: $year, in: 1900...9999) }
            Section {
                TextField("Yearly budget (€)", text: $total).keyboardType(.decimalPad)
                    .accessibilityIdentifier("budget.annual")
                if let parsed {
                    LabeledContent("Per month on average", value: Money.format(parsed / 12))
                    LabeledContent("Assigned to categories", value: Money.format(allocated))
                    LabeledContent("Guilt-free spending") {
                        Text(Money.format(parsed - allocated)).foregroundStyle(AmountColors.remaining(parsed - allocated))
                    }
                }
                Button(plan == nil ? "Set Yearly Budget" : "Save Yearly Budget") {
                    if plan != nil && parsed != baselineTotal { confirm = true } else { save() }
                }
                .disabled(parsed == nil || parsed! < allocated).accessibilityIdentifier("budget.save")
                if let parsed, parsed < allocated {
                    Text("Reduce category allocations before lowering the total this far.").foregroundStyle(AmountColors.negative)
                }
            } header: { Text("1. Your Whole Year") } footer: {
                Text("Pick the total first. Category budgets are parts of this amount; everything unassigned is guilt-free spending. Unspent and overspent amounts carry within the year.")
                if plan == nil && !allocations.isEmpty { Text("Prefilled from your existing category budgets. Saving keeps those allocations and makes any extra guilt-free.") }
            }
            Section {
                if let plan {
                    ForEach(store.categories.filter { $0.id != plan.freeCategoryID }) { category in
                        NavigationLink { CategoryEditor(category: category, year: year) } label: {
                            LabeledContent(category.name, value: plan.allocations.first { $0.categoryID == category.id }.map { Money.format($0.amount) } ?? "Guilt-free pool")
                        }.disabled(parsed != plan.total)
                    }
                    NavigationLink { CategoryEditor(year: year) } label: { Label("Add Category", systemImage: "plus") }
                        .disabled(parsed != plan.total)
                        .accessibilityIdentifier("category.add")
                } else { Text("Save the yearly total to start assigning category amounts.").foregroundStyle(.secondary) }
            } header: { Text("2. Assign to Categories") } footer: {
                Text("Categories without an allocation draw from the guilt-free pool. Category overspending stays visible against that category.")
            }
        }
        .navigationTitle("Yearly Plan")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } } }
        .onAppear { load() }
        .onChange(of: year) { load(force: true) }
        .confirmationDialog("Recalculate \(String(year))?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Update Yearly Budget") { save() }
        } message: { Text("The whole year's monthly balances will be recalculated. Expenses stay unchanged.") }
        .alert("Couldn't Save Budget", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
    }
    private func load(force: Bool = false) {
        guard force || loadedYear != year || parsed == baselineTotal else { return }
        let source = plan?.allocations ?? store.legacyAllocations(year: year)
        allocations = source
        confirmedPlan = plan
        let amount = plan?.total ?? source.reduce(0) { $0 + $1.amount }
        baselineTotal = amount
        total = amount == 0 && plan == nil ? "" : Money.input(amount)
        expectedRevision = plan.flatMap { try? store.recordRevision("budget_plan", $0.id) } ?? 0
        loadedYear = year
    }
    private func save() {
        do {
            try store.saveAnnualPlan(year: year, total: Money.parse(total, allowZero: true), allocations: confirmedPlan?.allocations ?? allocations, expectedRevision: expectedRevision, confirmedPlan: confirmedPlan)
            loadedYear = nil; load()
        } catch { self.error = error.localizedDescription }
    }
}

struct CategoryEditor: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let category: CategoryValue?
    let year: Int
    var onSaved: ((UUID) -> Void)?
    @State private var name: String
    @State private var annual = ""
    @State private var loaded = false
    @State private var snapshot: AnnualBudgetPlan?
    @State private var expectedRevision: Int64 = 0
    @State private var error: String?
    @State private var confirm = false
    init(category: CategoryValue? = nil, year: Int, onSaved: ((UUID) -> Void)? = nil) {
        self.category = category; self.year = year; self.onSaved = onSaved
        _name = State(initialValue: category?.name ?? "")
    }
    private var parsed: Int64? { annual.isEmpty ? 0 : try? Money.parse(annual, allowZero: true) }
    private var reserved: Bool { category?.id == snapshot?.freeCategoryID && category != nil }
    var body: some View {
        Form {
            Section { TextField("Category name", text: $name).textInputAutocapitalization(.words).accessibilityIdentifier("category.name") }
            if let snapshot, !reserved {
                Section {
                    TextField("Yearly allocation (€)", text: $annual).keyboardType(.decimalPad).accessibilityIdentifier("category.annual")
                    if let parsed {
                        let previous = snapshot.allocations.first { $0.categoryID == category?.id }?.amount ?? 0
                        let free = snapshot.guiltFree + previous - parsed
                        LabeledContent("Guilt-free after allocation", value: Money.format(free))
                        if free < 0 { Text("This allocation exceeds the yearly total.").foregroundStyle(AmountColors.negative) }
                    }
                } header: { Text("Part of Your \(String(year)) Budget") } footer: {
                    Text("Leave empty or enter zero to use the guilt-free pool. This amount comes from the yearly total; it doesn't add to it.")
                }
            } else {
                Section { Text(reserved ? "This default category draws from guilt-free spending." : "Set the whole yearly budget in Yearly Plan before assigning category amounts.").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(category == nil ? "New Category" : "Edit Category")
        .toolbar { ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                if category != nil, let snapshot, !reserved, parsed != snapshot.allocations.first(where: { $0.categoryID == category?.id })?.amount ?? 0 { confirm = true }
                else { save() }
            }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parsed == nil).accessibilityIdentifier("category.save")
        } }
        .onAppear {
            guard !loaded else { return }
            snapshot = store.annualPlan(year: year)
            expectedRevision = snapshot.flatMap { try? store.recordRevision("budget_plan", $0.id) } ?? 0
            if let id = category?.id, let amount = snapshot?.allocations.first(where: { $0.categoryID == id })?.amount { annual = Money.input(amount) }
            loaded = true
        }
        .confirmationDialog("Recalculate \(String(year))?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Update Yearly Allocation") { save() }
        } message: { Text("The category and guilt-free balances for this year will be recalculated. The yearly total stays the same.") }
        .alert("Couldn't Save Category", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
    }
    private func save() {
        do {
            let amount = snapshot == nil || reserved ? nil : parsed
            let id = try store.saveCategory(id: category?.id, name: name, year: year, annualAmount: amount, planSnapshot: snapshot, expectedPlanRevision: expectedRevision)
            onSaved?(id); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
