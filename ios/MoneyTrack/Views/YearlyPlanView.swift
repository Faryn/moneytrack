import SwiftUI

struct YearlyPlanView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var year: Int
    var body: some View {
        List {
            Section {
                Stepper("Year \(String(year))", value: $year, in: 1900...9999)
            }
            Section {
                ForEach(store.categories) { category in
                    NavigationLink {
                        CategoryEditor(category: category, year: year)
                    } label: {
                        LabeledContent(category.name) {
                            if let budget = store.budget(for: category.id, year: year) {
                                Text(Money.format(budget.amount)).monospacedDigit()
                            } else {
                                Text("Set budget").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                NavigationLink {
                    CategoryEditor(year: year)
                } label: {
                    Label("Add Category", systemImage: "plus")
                }
                .accessibilityIdentifier("category.add")
            } header: { Text("Yearly amounts") } footer: {
                Text("Each yearly amount is divided across twelve months. Carryover resets on January 1.")
            }
            Section {
                LabeledContent("Yearly total", value: Money.format(
                    store.budgets.filter { $0.year == year }.reduce(0) { $0 + $1.amount }
                ))
            }
        }
        .navigationTitle("Yearly Plan")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") { dismiss() }
            }
        }
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
    @State private var error: String?
    @State private var confirmRecalculation = false

    init(category: CategoryValue? = nil, year: Int, onSaved: ((UUID) -> Void)? = nil) {
        self.category = category; self.year = year; self.onSaved = onSaved
        _name = State(initialValue: category?.name ?? "")
    }
    private var existing: YearBudgetValue? {
        category.flatMap { store.budget(for: $0.id, year: year) }
    }
    private var parsedAnnual: Int64? { try? Money.parse(annual, allowZero: true) }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (parsedAnnual != nil || (annual.isEmpty && existing == nil))
    }
    var body: some View {
        Form {
            Section {
                TextField("Category name", text: $name)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("category.name")
            }
            Section {
                TextField("Yearly amount (€)", text: $annual)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("category.annual")
                if let amount = parsedAnnual {
                    Text("\((Decimal(amount) / 1200).formatted(.currency(code: "EUR"))) per month on average")
                        .foregroundStyle(.secondary)
                } else if !annual.isEmpty {
                    Text("Enter an amount such as 1200,50 or 1200.50, without thousands separators.")
                        .font(.callout).foregroundStyle(AmountColors.negative)
                }
            } header: { Text("Budget for \(String(year))") } footer: {
                Text("Optional for a new category. A yearly budget applies from January 1; unspent and overspent amounts carry into later months of that year. Cent rounding is distributed across the twelve months.")
            }
        }
        .navigationTitle(category == nil ? "New Category" : "Edit Category")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if let existing, parsedAnnual != existing.amount { confirmRecalculation = true }
                    else { save() }
                }
                .disabled(!canSave)
                .accessibilityIdentifier("category.save")
            }
        }
        .onAppear {
            guard !loaded else { return }
            if let existing { annual = Money.input(existing.amount) }
            loaded = true
        }
        .confirmationDialog("Recalculate \(String(year))?", isPresented: $confirmRecalculation, titleVisibility: .visible) {
            Button("Update Yearly Budget") { save() }
        } message: {
            Text("All monthly budget balances in this year will be recalculated. Recorded expenses stay unchanged.")
        }
        .alert("Couldn't Save Category", isPresented: errorPresented) { Button("OK", role: .cancel) {} } message: {
            Text(error ?? "")
        }
    }
    private var errorPresented: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }
    private func save() {
        do {
            let amount = annual.isEmpty ? nil : try Money.parse(annual, allowZero: true)
            let id = try store.saveCategory(id: category?.id, name: name, year: year, annualAmount: amount)
            onSaved?(id)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
