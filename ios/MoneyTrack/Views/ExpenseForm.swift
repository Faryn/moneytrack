import SwiftUI

struct ExpenseForm: View {
    @Environment(LedgerStore.self) private var store
    @Environment(AppSession.self) private var app
    @Environment(\.dismiss) private var dismiss
    let expense: ExpenseValue?
    let today: Date
    var onSaved: (() -> Void)? = nil
    @State private var amount: String
    @State private var description: String
    @State private var categoryID: UUID?
    @State private var date: Date
    @State private var selectedCategoryManually = false
    @State private var suggested = false
    @State private var error: String?
    @State private var confirmDiscard = false
    @State private var expectedRevision: Int64?
    @State private var sharingConnectionID: UUID?
    @State private var paidByUser = true
    @State private var split: PersonalSplit = .half
    @State private var kind: BookingKind = .expense
    @State private var inputCurrency = "EUR"
    @State private var rates = ExchangeRates.shared
    @FocusState private var amountFocused: Bool

    init(expense: ExpenseValue? = nil, categoryID: UUID? = nil, today: Date, draft: QuickExpense? = nil, categoryIsExplicit: Bool = false, onSaved: (() -> Void)? = nil) {
        self.expense = expense; self.today = today; self.onSaved = onSaved
        _kind = State(initialValue: expense?.kind ?? .expense)
        _inputCurrency = State(initialValue: expense?.conversion?.originalCurrency ?? draft?.currency ?? "EUR")
        _amount = State(initialValue: expense.map { value in value.conversion.map { CurrencyConversion.input($0.originalAmount, currency: $0.originalCurrency) } ?? Money.input(value.amount) } ?? draft.map { CurrencyConversion.input($0.amount, currency: $0.currency) } ?? "")
        _description = State(initialValue: expense?.description ?? draft?.description ?? "")
        _categoryID = State(initialValue: categoryIsExplicit ? categoryID : expense?.categoryID ?? draft?.categoryID ?? categoryID)
        _date = State(initialValue: expense?.day.date ?? today)
        _selectedCategoryManually = State(initialValue: categoryIsExplicit || draft?.categoryID != nil)
        _sharingConnectionID = State(initialValue: draft?.sharingConnection?.id)
    }
    private var enteredConversion: CurrencyConversion? {
        guard inputCurrency != "EUR", let originalAmount = try? CurrencyConversion.parse(amount, currency: inputCurrency) else { return nil }
        if let old = expense?.conversion, old.originalAmount == originalAmount, old.originalCurrency == inputCurrency { return old }
        guard let snapshot = rates.snapshot, let rate = snapshot.rates[inputCurrency] else { return nil }
        return CurrencyConversion(originalAmount: originalAmount, originalCurrency: inputCurrency, rate: rate, rateDate: snapshot.date, source: "ECB")
    }
    private var euroAmount: Int64? {
        inputCurrency == "EUR" ? try? Money.parse(amount) : try? enteredConversion?.euroCents()
    }
    private var sharingConnection: SharingConnection? { store.sharingConnections.first { $0.id == sharingConnectionID } }
    private var canSave: Bool {
        (kind == .income || sharingConnectionID == nil || (sharingConnection != nil && app.credential != nil)) && euroAmount != nil
            && (1900...9999).contains(ExpenseDay(date: date).year)
    }
    private var dirty: Bool {
        if let expense {
            return kind != (expense.kind ?? .expense) || euroAmount != expense.amount || enteredConversion != expense.conversion || description != expense.description
                || categoryID != expense.categoryID || ExpenseDay(date: date) != expense.day
        }
        return kind == .income || sharingConnectionID != nil || !amount.isEmpty || !description.isEmpty || ExpenseDay(date: date) != ExpenseDay(date: today)
    }
    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $kind) {
                    ForEach(BookingKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("expense.kind")
                CurrencyField(title: String(localized: "Amount"), text: $amount, identifier: "expense.amount", focus: $amountFocused, currencyCode: inputCurrency)
                if !amount.isEmpty && (try? CurrencyConversion.parse(amount, currency: inputCurrency)) == nil {
                    Text("Enter a positive amount with the fractional digits allowed by the selected currency.")
                        .font(.callout).foregroundStyle(AmountColors.negative)
                }
            }
            if inputCurrency != "EUR" {
                Section {
                    if let euroAmount { LabeledContent("In euros", value: Money.format(euroAmount)) }
                    if let enteredConversion {
                        Text("ECB · \(enteredConversion.rateDate) · 1 EUR = \(enteredConversion.rate) \(inputCurrency)").font(.caption)
                    }
                    if let message = rates.message { Text(message).font(.callout) }
                    Button(rates.loading ? "Updating rates…" : "Refresh Rates") { Task { await rates.refresh() } }.disabled(rates.loading)
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
                    Text("No category").tag(UUID?.none)
                    ForEach(store.activeCategories) { category in
                        Text(store.displayName(for: category, year: ExpenseDay(date: date).year)).tag(Optional(category.id))
                    }
                }
                .pickerStyle(.navigationLink)
                .accessibilityIdentifier("expense.category")
            } footer: {
                if suggested { Text("Category suggested from your earlier expenses.") }
            }
            if kind == .expense, expense == nil, app.credential != nil, !store.sharingConnections.isEmpty {
                Section("Sharing") {
                    Picker("Share with", selection: $sharingConnectionID) {
                        Text("Personal").tag(UUID?.none)
                        ForEach(store.sharingConnections) { Text(SharedDisplay.person($0.otherName)).tag(Optional($0.id)) }
                    }.accessibilityIdentifier("expense.share-with")
                    if let sharingConnection {
                        Picker("Paid by", selection: $paidByUser) {
                            Text("You").tag(true)
                            Text(SharedDisplay.person(sharingConnection.otherName)).tag(false)
                        }
                        Picker("Your share", selection: $split) {
                            ForEach(PersonalSplit.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                }
            }
            Section("Details") {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .accessibilityIdentifier("expense.date")
                Picker("Currency", selection: $inputCurrency) {
                    Text("EUR · Euro").tag("EUR")
                    ForEach(CurrencyConversion.currencies, id: \.self) { Text($0).tag($0) }
                }.accessibilityIdentifier("expense.currency")
                NavigationLink("Add Category") {
                    CategoryEditor(year: ExpenseDay(date: date).year) { id in
                        categoryID = id; selectedCategoryManually = true; suggested = false
                    }
                }
            }

        }
        .navigationTitle(expense == nil ? (kind == .income ? "New Income" : "New Expense") : (kind == .income ? "Edit Income" : "Edit Expense"))
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
                Button(kind == .income ? "Save Income" : "Save Expense", action: save)
                    .disabled(!canSave)
                    .accessibilityIdentifier("expense.keyboard-save")
            }
        }
        .interactiveDismissDisabled(dirty)
        .onAppear {
            if let expense, expectedRevision == nil { expectedRevision = (try? store.recordRevision("expense", expense.id)) ?? 0 }
            if categoryID == nil, !selectedCategoryManually, let recent = store.expenses.first?.categoryID,
               recent != store.annualPlan(year: ExpenseDay(date: date).year)?.freeCategoryID { categoryID = recent }
        }
        .task { if expense == nil { amountFocused = true } }
        .task(id: inputCurrency) { if inputCurrency != "EUR" { await rates.refresh() } }
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
            var sharing: NewExpenseSharing?
            if kind == .expense, let connection = sharingConnection, let account = app.credential {
                sharing = NewExpenseSharing(userID: account.userID, username: account.username, connection: connection, paidByUser: paidByUser, split: split)
            }
            try store.saveExpense(id: expense?.id, amount: euroAmount!, description: description,
                                  categoryID: categoryID, day: ExpenseDay(date: date), expectedRevision: expectedRevision, conversion: enteredConversion, sharing: sharing, kind: kind)
            dismiss()
            onSaved?()
        } catch { self.error = error.localizedDescription }
    }
}


struct QuickExpenseEntry: View {
    @Environment(LedgerStore.self) private var store
    @Environment(AppSession.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var recognition = QuickEntryRecognition()
    @State private var pickedCategoryID: UUID?
    @State private var categoryWasPicked = false
    @State private var error: String?
    @State private var details = false
    @State private var saving = false
    @State private var rates = ExchangeRates.shared
    @State private var focused = false
    @State private var editor = QuickEntryTextEditor()
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var preferredWidth = 320

    private var parsed: QuickExpense? { recognition.current }
    private var canSave: Bool { euroAmount != nil && (parsed?.sharingConnection == nil || app.credential != nil) && !saving }
    private var categoryID: UUID? {
        if categoryWasPicked { return pickedCategoryID }
        return recognition.preview?.categoryID ?? recognition.preview.flatMap { store.suggestedCategory(description: $0.description) } ?? store.expenses.first?.categoryID
    }
    private var categorySelection: Binding<UUID?> {
        Binding(get: { categoryID }, set: { pickedCategoryID = $0; categoryWasPicked = true })
    }
    private var detailDraft: QuickExpense? {
        guard let parsed else { return nil }
        return QuickExpense(amount: parsed.amount, currency: parsed.currency, sharingConnection: parsed.sharingConnection,
                            description: parsed.description, categoryID: categoryID)
    }
    private var conversion: CurrencyConversion? { conversion(for: parsed) }
    private func conversion(for parsed: QuickExpense?) -> CurrencyConversion? {
        guard let parsed, parsed.currency != "EUR", let snapshot = rates.snapshot,
              let rate = snapshot.rates[parsed.currency] else { return nil }
        return CurrencyConversion(originalAmount: parsed.amount, originalCurrency: parsed.currency,
                                  rate: rate, rateDate: snapshot.date, source: "ECB")
    }
    private var euroAmount: Int64? { euroAmount(for: parsed) }
    private func euroAmount(for parsed: QuickExpense?) -> Int64? {
        guard let parsed else { return nil }
        return parsed.currency == "EUR" ? parsed.amount : try? conversion(for: parsed)?.euroCents()
    }
    private var categoryName: String {
        store.categories.first { $0.id == categoryID }.map { store.displayName(for: $0, year: ExpenseDay(date: store.today).year) } ?? String(localized: "No category")
    }
    private var previewAmount: Int64? { euroAmount(for: recognition.preview) }
    private var previewLabel: String {
        let values = [previewAmount.map { Money.format($0) } ?? String(localized: "Amount"), recognition.preview?.description ?? "", categoryName]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        return recognition.issue == nil ? values : String(localized: "Last recognized: \(values). \(entryStatus)")
    }
    private var entryStatus: String {
        switch recognition.issue {
        case .amount: return String(localized: "Check amount")
        case .unsupportedCurrency: return String(localized: "Check currency")
        case .unknownPerson, .ambiguousPerson, .missingPerson: return String(localized: "Check person")
        case nil: return recognition.preview != nil && previewAmount == nil ? String(localized: "Exchange rate needed") : String(localized: "Today")
        }
    }
    private var sharingError: String? {
        switch recognition.issue {
        case .unknownPerson, .ambiguousPerson, .missingPerson: recognition.issue?.localizedDescription
        default: nil
        }
    }
    private var currency: String { recognition.preview?.currency ?? "EUR" }
    private var currencyTitle: String { ["EUR": "€", "USD": "$", "GBP": "£"][currency] ?? currency }
    private var entryActions: some View {
        HStack(spacing: 8) {
            Button("Details", systemImage: "slider.horizontal.3") { focused = false; details = true }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Expense details")
                .accessibilityHint("Date, currency and category")
                .accessibilityIdentifier("expense.quick-details")
            Button("Save", action: save)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .frame(minHeight: 44)
                .disabled(!canSave)
                .accessibilityIdentifier("expense.quick-save")
        }
    }
    private var entryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            let headerLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))
            headerLayout {
                Text("New Expense").font(.headline).accessibilityIdentifier("expense.quick-title")
                if !typeSize.isAccessibilitySize { Spacer() }
                entryActions
            }
            HStack(spacing: 8) {
                Menu {
                    Button("€ · Euro") { insertCurrency("€") }
                    Button("$ · US dollar") { insertCurrency("$") }
                    Button("£ · British pound") { insertCurrency("£") }
                } label: {
                    Text(currencyTitle).font(.subheadline).lineLimit(1).fixedSize()
                }
                .menuIndicator(.visible)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Currency shortcuts")
                .accessibilityHint("Insert a currency symbol at the cursor")
                .accessibilityValue(currency)
                .accessibilityIdentifier("expense.quick-currency")
                Divider().frame(height: 24).accessibilityHidden(true)
                QuickEntryTextField(text: $text, isFocused: $focused, locale: locale, editor: editor, onSubmit: save)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                let previewLayout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
                previewLayout {
                    Text(previewAmount.map { Money.format($0) } ?? "—")
                        .font(.title3.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(parsed != nil && euroAmount != nil ? Color.primary : Color.secondary)
                        .contentTransition(.identity)
                        .accessibilityLabel(previewLabel)
                        .accessibilityIdentifier("expense.quick-preview")
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    Menu {
                        Picker("Category", selection: categorySelection) {
                            Text("No category").tag(UUID?.none)
                            ForEach(store.activeCategories) { category in
                                Text(store.displayName(for: category, year: ExpenseDay(date: store.today).year)).tag(Optional(category.id))
                            }
                        }
                    } label: {
                        Text(categoryName)
                            .font(.subheadline)
                            .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .menuIndicator(.visible)
                    .accessibilityLabel("Category")
                    .accessibilityValue(categoryName)
                    .accessibilityIdentifier("expense.quick-category")
                }
                Text(entryStatus)
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("expense.quick-status")
            }
            .padding(.horizontal, 2)
            .transaction { $0.animation = nil }
            if let connection = recognition.preview?.sharingConnection {
                let ownShare = previewAmount.flatMap { try? SharedMath.calculate(amount: $0, split: .half, paidByUser: true).personalShare }
                let shareLabel = ownShare.map { " · " + String(localized: "You \(Money.format($0))") } ?? ""
                Label("\(SharedDisplay.person(connection.otherName)) · 50/50\(shareLabel)", systemImage: "person.2")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("expense.quick-sharing")
            }
            if let conversion = conversion(for: recognition.preview) {
                Text("ECB · \(conversion.rateDate)").font(.caption).foregroundStyle(.secondary)
            }
            if currency != "EUR", let message = rates.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if let message = error ?? sharingError { Text(message).font(.callout).foregroundStyle(AmountColors.negative) }
        }
        .padding(16)
    }
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                ScrollView { entryContent }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollDismissesKeyboard(.interactively)
                    .accessibilityIdentifier("expense.quick-scroll")
            } else {
                entryContent
                    .frame(idealWidth: preferredWidth)
                    .fixedSize(horizontal: false, vertical: true)
                    .presentationSizing(.fitted)
            }
        }
        .task {
            // Let the popover present before asking the system to show its keyboard.
            await Task.yield()
            focused = true
        }
        .task(id: currency) { if currency != "EUR" { await rates.refresh() } }
        .onChange(of: text) {
            error = nil
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { categoryWasPicked = false; pickedCategoryID = nil }
            updateRecognition()
        }
        .onChange(of: store.activeCategories) { updateRecognition() }
        .onChange(of: store.sharingConnections) { updateRecognition() }
        .sheet(isPresented: $details) {
            NavigationStack {
                ExpenseForm(categoryID: categoryID, today: store.today, draft: detailDraft, categoryIsExplicit: categoryWasPicked, onSaved: { dismiss() })
            }
        }
    }
    private func insertCurrency(_ symbol: String) {
        editor.insert(symbol)
        focused = true
    }
    private func updateRecognition() {
        recognition.update(text, categories: store.activeCategories, connections: store.sharingConnections)
    }
    private func save() {
        guard canSave, let parsed, let euroAmount else { return }
        saving = true
        do {
            var sharing: NewExpenseSharing?
            if let connection = parsed.sharingConnection, let account = app.credential {
                sharing = NewExpenseSharing(userID: account.userID, username: account.username, connection: connection)
            }
            try store.saveExpense(amount: euroAmount, description: parsed.description, categoryID: categoryID,
                                  day: ExpenseDay(date: store.today), conversion: conversion, sharing: sharing)
            dismiss()
        } catch { self.error = error.localizedDescription; saving = false }
    }
}
