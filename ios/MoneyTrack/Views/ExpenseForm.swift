import SwiftUI

struct ExpenseForm: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let expense: ExpenseValue?
    let today: Date
    @State private var amount: String
    @State private var description: String
    @State private var categoryID: UUID?
    @State private var date: Date
    @State private var selectedCategoryManually = false
    @State private var dateExpanded = false
    @State private var suggested = false
    @State private var error: String?
    @State private var confirmDiscard = false
    @FocusState private var amountFocused: Bool

    init(expense: ExpenseValue? = nil, categoryID: UUID? = nil, today: Date) {
        self.expense = expense; self.today = today
        _amount = State(initialValue: expense.map { Money.input($0.amount) } ?? "")
        _description = State(initialValue: expense?.description ?? "")
        _categoryID = State(initialValue: expense?.categoryID ?? categoryID)
        _date = State(initialValue: expense?.day.date ?? today)
    }
    private var canSave: Bool {
        (try? Money.parse(amount)) != nil && categoryID != nil
            && (1900...9999).contains(ExpenseDay(date: date).year)
    }
    private var dirty: Bool {
        if let expense {
            return amount != Money.input(expense.amount) || description != expense.description
                || categoryID != expense.categoryID || ExpenseDay(date: date) != expense.day
        }
        return !amount.isEmpty || !description.isEmpty || ExpenseDay(date: date) != ExpenseDay(date: today)
    }
    var body: some View {
        Form {
            Section("Amount (€)") {
                TextField("0,00", text: $amount)
                    .font(.title2).keyboardType(.decimalPad).focused($amountFocused)
                    .accessibilityLabel("Amount in euros")
                    .accessibilityIdentifier("expense.amount")
                if !amount.isEmpty && (try? Money.parse(amount)) == nil {
                    Text("Enter a positive amount such as 78,50 or 78.50, without thousands separators.")
                        .font(.callout).foregroundStyle(AmountColors.negative)
                }
            }
            Section {
                TextField("Description (optional)", text: $description)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("expense.description")
                Picker("Category", selection: Binding(
                    get: { categoryID },
                    set: { categoryID = $0; selectedCategoryManually = true; suggested = false }
                )) {
                    Text("Choose a category").tag(UUID?.none)
                    ForEach(store.categories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
                .pickerStyle(.navigationLink)
                .accessibilityIdentifier("expense.category")
                NavigationLink("Add Category") {
                    CategoryEditor(year: ExpenseDay(date: date).year) { id in
                        categoryID = id; selectedCategoryManually = true; suggested = false
                    }
                }
            } footer: {
                if suggested { Text("Category suggested from your earlier expenses.") }
            }
            Section {
                DisclosureGroup(isExpanded: $dateExpanded) {
                    DatePicker("Expense date", selection: $date, displayedComponents: .date)
                        .accessibilityIdentifier("expense.date")
                } label: {
                    LabeledContent("Date", value: ExpenseDay(date: date) == ExpenseDay(date: today)
                                   ? "Today" : date.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
        .navigationTitle(expense == nil ? "New Expense" : "Edit Expense")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { if dirty { confirmDiscard = true } else { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!canSave).accessibilityIdentifier("expense.save")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { amountFocused = false }
            }
        }
        .interactiveDismissDisabled(dirty)
        .onAppear {
            if categoryID == nil { categoryID = store.expenses.first?.categoryID ?? store.categories.first?.id }
        }
        .task { if expense == nil { amountFocused = true } }
        .onChange(of: description) {
            if !selectedCategoryManually, let id = store.suggestedCategory(description: description) {
                categoryID = id; suggested = true
            }
        }
        .alert("Discard Changes?", isPresented: $confirmDiscard) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard", role: .destructive) { dismiss() }
        } message: {
            Text("This expense hasn't been saved.")
        }
        .alert("Couldn't Save Expense", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
    }
    private func save() {
        do {
            guard let categoryID else { throw LedgerError.missingCategory }
            try store.saveExpense(id: expense?.id, amount: Money.parse(amount), description: description,
                                  categoryID: categoryID, day: ExpenseDay(date: date))
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
