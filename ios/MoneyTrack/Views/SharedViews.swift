import SwiftUI

// Presentation only: retain original usernames, descriptions and account identifiers.
enum SharedDisplay {
    static func person(_ value: String) -> String {
        guard !value.contains("@"), value == value.lowercased() else { return value }
        return value.capitalized
    }
    static func title(_ value: String) -> String {
        guard let first = value.first else { return value }
        return String(first).uppercased() + value.dropFirst()
    }
}

private struct SharedActivityRow: View {
    let title: String
    let subtitle: String
    let amount: Int64?
    let amountLabel: String
    var amountColor: Color = .primary
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 16))
        layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
                Text(amount.map { Money.format($0) } ?? String(localized: "Unavailable"))
                    .font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(ListRowForeground(amountColor))
                Text(amountLabel).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct SharedHomeView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(AppSession.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var error: String?
    var body: some View {
        List {
            if app.credential == nil {
                ContentUnavailableView("Sign in to share", systemImage: "person.2", description: Text("Sign in from Account to share expenses."))
            } else {
                if !store.issues.isEmpty {
                    Section { NavigationLink("Review changes") { SyncReviewList() } }
                }
                if store.pendingChanges.contains(where: { ["shared_expense", "shared_assignment", "repayment"].contains($0.entity) }) {
                    Section {
                        Label("Waiting to sync", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if !store.invitations.isEmpty {
                    Section("Invitations") {
                        ForEach(store.invitations) { invitation in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(SharedDisplay.person(invitation.senderName)).font(.body.weight(.medium))
                                Text("Accept once for current and future sharing.").font(.subheadline).foregroundStyle(.secondary)
                                Button("Accept invitation") {
                                    do { try store.acceptInvitation(invitation) } catch { self.error = error.localizedDescription }
                                }
                                .buttonStyle(.borderedProminent).controlSize(.small)
                                .disabled(store.pendingChanges.contains { $0.entity == "shared_expense" && $0.entityID == invitation.id })
                                .accessibilityIdentifier("sharing.accept.\(invitation.id)")
                            }.padding(.vertical, 4)
                        }
                    }
                }
                if !store.sharingConnections.isEmpty {
                    Section("People") {
                        ForEach(store.sharingConnections) { connection in
                            NavigationLink {
                                SharedPersonView(connection: connection)
                            } label: {
                                let layout = typeSize.isAccessibilitySize
                                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                    : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
                                layout {
                                    Text(SharedDisplay.person(connection.otherName))
                                        .font(.body.weight(.medium)).foregroundStyle(.primary)
                                    if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                                    SharedBalanceLabel(balance: try? store.sharedBalance(connection.id),
                                                       alignment: typeSize.isAccessibilitySize ? .leading : .trailing)
                                }.padding(.vertical, 4)
                            }
                            .accessibilityIdentifier("sharing.person.\(connection.otherName)")
                        }
                    }
                }
                let pending = store.sharedExpenses.filter { $0.status == "pending" && !$0.deleted }
                if !pending.isEmpty {
                    Section {
                        ForEach(pending) { value in
                            NavigationLink { ExpenseDetailView(expenseID: value.id) } label: {
                                let share = try? value.amounts.personalShare
                                SharedActivityRow(title: SharedDisplay.person(value.otherName),
                                    subtitle: SharedDisplay.title(value.description.isEmpty ? String(localized: "Shared expense") : value.description),
                                    amount: share.map { -$0 }, amountLabel: String(localized: "Your share"),
                                    amountColor: share.map { $0 > 0 ? AmountColors.negative : .primary } ?? .secondary)
                            }
                        }
                    } header: { Text("Awaiting acceptance") } footer: {
                        Text("Your share already counts in your budget.")
                    }
                }
                if store.sharingConnections.isEmpty && pending.isEmpty && store.invitations.isEmpty {
                    ContentUnavailableView("No shared expenses", systemImage: "person.2", description: Text("Share a saved expense to connect with someone. Verify your email in Account to receive invitations."))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Shared")
        .refreshable { await app.synchronize() }
        .alert("Couldn't Accept Invitation", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }
}

struct SharedBalanceLabel: View {
    let balance: Int64?
    var alignment: HorizontalAlignment = .leading
    var prominent = false
    private var status: String {
        guard let balance else { return String(localized: "Balance unavailable") }
        return balance == 0 ? String(localized: "Settled up") : balance > 0 ? String(localized: "Owes you") : String(localized: "You owe")
    }
    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(status).font(.subheadline).foregroundStyle(.secondary).accessibilityHidden(balance != nil)
            if let balance {
                Text(Money.format(abs(balance)))
                    .font(prominent ? .largeTitle.weight(.semibold) : .body.weight(.semibold))
                    .foregroundStyle(ListRowForeground(AmountColors.remaining(balance))).monospacedDigit()
                    .accessibilityLabel(balance == 0 ? "Settled up" : "\(status) \(Money.format(abs(balance)))")
                    .accessibilityIdentifier("sharing.balance")
            }
        }
    }
}

struct SharedPersonView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(AppSession.self) private var app
    let connection: SharingConnection
    @State private var settling = false
    private var balance: Int64? { try? store.sharedBalance(connection.id) }
    private var name: String { SharedDisplay.person(connection.otherName) }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    SharedBalanceLabel(balance: balance, prominent: true)
                    Button("Settle up", systemImage: "arrow.left.arrow.right") { settling = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(balance == nil || balance == 0)
                        .accessibilityIdentifier("sharing.settle")
                }.padding(.vertical, 8)
                if !store.issues.isEmpty { NavigationLink("Review changes") { SyncReviewList() } }
            } footer: {
                if store.pendingChanges.contains(where: { ["shared_expense", "shared_assignment", "repayment"].contains($0.entity) }) {
                    Text("Includes changes waiting to sync.").accessibilityIdentifier("sharing.pending")
                }
            }
            let expenses = store.sharedExpenses.filter { $0.connection?.id == connection.id }.sorted { $0.day > $1.day }
            if !expenses.isEmpty {
                Section("Expenses") {
                    ForEach(expenses) { value in
                        NavigationLink { ExpenseDetailView(expenseID: value.id) } label: {
                            SharedActivityRow(title: SharedDisplay.title(value.description.isEmpty ? String(localized: "Expense") : value.description),
                                subtitle: value.day.date.formatted(date: .abbreviated, time: .omitted) + (value.deleted ? " · " + String(localized: "Deleted") : ""),
                                amount: value.amount, amountLabel: value.deleted ? String(localized: "History") : String(localized: "Total"),
                                amountColor: value.deleted ? .secondary : .primary)
                        }
                    }
                }
            }
            let repayments = store.repayments.filter { $0.connectionID == connection.id }
            if !repayments.isEmpty {
                Section("Repayments") {
                    ForEach(repayments) { value in
                        SharedActivityRow(title: value.paidByUser ? String(localized: "You paid \(name)") : String(localized: "\(name) paid you"),
                            subtitle: String(localized: "\(value.day.date.formatted(date: .abbreviated, time: .omitted)) · Recorded by \(SharedDisplay.person(value.actorName))"),
                            amount: value.paidByUser ? -value.amount : value.amount, amountLabel: String(localized: "Repayment"),
                            amountColor: value.paidByUser ? AmountColors.negative : AmountColors.positive)
                            // Match the disclosure gutter reserved by the expense NavigationLinks.
                            .padding(.trailing, 22)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await app.synchronize() }
        .sheet(isPresented: $settling) { NavigationStack { SettleUpForm(connection: connection) } }
    }
}

struct ShareExpenseForm: View {
    @Environment(LedgerStore.self) private var store
    @Environment(AppSession.self) private var app
    @Environment(\.dismiss) private var dismiss
    let expense: ExpenseValue
    @State private var email = ""
    @State private var connectionID: UUID?
    @State private var paidByUser = true
    @State private var split: PersonalSplit = .half
    @State private var error: String?
    private var connection: SharingConnection? { store.sharingConnections.first { $0.id == connectionID } }
    var body: some View {
        Form {
            Section("Share With") {
                if !store.sharingConnections.isEmpty {
                    Picker("Person", selection: $connectionID) {
                        Text("Invite by email").tag(UUID?.none)
                        ForEach(store.sharingConnections) { c in Text(SharedDisplay.person(c.otherName)).tag(Optional(c.id)) }
                    }
                }
                if connection == nil {
                    TextField("Email address", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("sharing.email")
                }
            }
            Section {
                Picker("Paid by", selection: $paidByUser) {
                    Text("You").tag(true); Text(connection.map { SharedDisplay.person($0.otherName) } ?? String(localized: "Other person")).tag(false)
                }
                Picker(String(localized: "Your share"), selection: $split) { ForEach(PersonalSplit.allCases, id: \.self) { Text($0.title).tag($0) } }
                    .accessibilityIdentifier("sharing.split")
            }
            if let amounts = try? SharedMath.calculate(amount: expense.amount, split: split, paidByUser: paidByUser) {
                Section {
                    LabeledContent("Your budget impact") { Text(Money.format(-amounts.personalShare)).foregroundStyle(amounts.personalShare > 0 ? AmountColors.negative : .primary).monospacedDigit() }
                    SharedBalanceLabel(balance: amounts.balance)
                } footer: { Text("Your proposed share counts in the expense's original month immediately. A new person must accept before shared access starts.") }
            }
        }
        .navigationTitle("Share Expense")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Share") {
                    do {
                        guard let account = app.credential else { throw ConnectionError.unauthorized }
                        try store.shareExpense(expense.id, viewerID: account.userID, username: account.username,
                            email: email, connection: connection, paidByUser: paidByUser, split: split)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.disabled(app.credential == nil || (connection == nil && !email.contains("@")))
                    .accessibilityIdentifier("sharing.save")
            }
        }
        .alert("Couldn't Share Expense", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }
}

struct SharedExpenseEditor: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var original: SharedExpenseValue
    @State private var amount: String
    @State private var description: String
    @State private var categoryID: UUID
    @State private var date: Date
    @State private var paidByUser: Bool
    @State private var split: PersonalSplit
    @State private var error: String?
    @State private var rates = ExchangeRates.shared
    init(value: SharedExpenseValue) {
        _original = State(initialValue: value); _amount = State(initialValue: value.conversion.map { CurrencyConversion.input($0.originalAmount, currency: $0.originalCurrency) } ?? Money.input(value.amount)); _description = State(initialValue: value.description)
        _categoryID = State(initialValue: value.categoryID); _date = State(initialValue: value.day.date)
        _paidByUser = State(initialValue: value.paidByUser); _split = State(initialValue: value.ownSplit)
    }
    private var converted: CurrencyConversion? {
        guard let old = original.conversion, let value = try? CurrencyConversion.parse(amount, currency: old.originalCurrency) else { return nil }
        if value == old.originalAmount { return old }
        guard let snapshot = rates.snapshot, let rate = snapshot.rates[old.originalCurrency] else { return nil }
        return CurrencyConversion(originalAmount: value, originalCurrency: old.originalCurrency, rate: rate, rateDate: snapshot.date, source: "ECB")
    }
    private var euroAmount: Int64? { original.conversion == nil ? try? Money.parse(amount) : try? converted?.euroCents() }
    var body: some View {
        Form {
            Section {
                CurrencyField(title: String(localized: "Amount"), text: $amount, identifier: "shared-edit.amount", currencyCode: original.conversion?.originalCurrency ?? "EUR")
                if let converted, let euroAmount {
                    LabeledContent("In euros", value: Money.format(euroAmount))
                    Text("ECB · \(converted.rateDate)").font(.caption)
                }
                TextField("Description", text: $description).accessibilityIdentifier("shared-edit.description")
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Paid by", selection: $paidByUser) { Text("You").tag(true); Text(SharedDisplay.person(original.otherName)).tag(false) }
                Picker(String(localized: "Your share"), selection: $split) { ForEach(PersonalSplit.allCases, id: \.self) { Text($0.title).tag($0) } }
            } header: { Text("Shared Details") } footer: { Text("Both people can see these changes and their history.") }
            Section {
                Picker("Your category", selection: $categoryID) { ForEach(store.activeCategories) { Text(store.displayName(for: $0, year: ExpenseDay(date: date).year)).tag($0.id) } }
            } footer: { Text("Only you can see or change your category.") }
        }
        .task { if original.conversion != nil { await rates.refresh() } }
        .navigationTitle("Edit Shared Expense")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    do {
                        try store.editSharedExpense(original, amount: euroAmount!, description: description,
                            categoryID: categoryID, day: ExpenseDay(date: date), paidByUser: paidByUser, ownSplit: split, conversion: converted)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.disabled(euroAmount == nil).accessibilityIdentifier("shared-edit.save")
            }
        }
        .alert("Couldn't Save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
    }
}

struct SettleUpForm: View {
    @Environment(LedgerStore.self) private var store
    @Environment(AppSession.self) private var app
    @Environment(\.dismiss) private var dismiss
    let connection: SharingConnection
    @State private var amount = ""
    @State private var date = Date.now
    @State private var confirmedBalance: Int64?
    @State private var error: String?
    @FocusState private var focused: Bool
    private var parsed: Int64? { try? Money.parse(amount) }
    var body: some View {
        Form {
            if let balance = confirmedBalance {
                Section {
                    LabeledContent("Payment", value: balance < 0 ? String(localized: "You paid \(SharedDisplay.person(connection.otherName))") : String(localized: "\(SharedDisplay.person(connection.otherName)) paid you"))
                    CurrencyField(title: String(localized: "Amount"), text: $amount, identifier: "settle.amount", focus: $focused)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                } footer: { Text("Only records a payment made outside Spendie. Both people see the repayment; budgets stay unchanged.") }
                if let parsed, parsed <= abs(balance) {
                    Section("After recording") { SharedBalanceLabel(balance: balance + (balance < 0 ? parsed : -parsed)) }
                }
            }
        }
        .navigationTitle("Settle Up")
        .onAppear {
            confirmedBalance = try? store.sharedBalance(connection.id)
            if let balance = confirmedBalance { amount = Money.input(abs(balance)) }
            date = store.today
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Record Repayment") {
                    do {
                        guard let account = app.credential, try store.sharedBalance(connection.id) == confirmedBalance else {
                            throw ConnectionError.rejected(String(localized: "The balance changed. Close this form and review it before recording."))
                        }
                        try store.recordRepayment(connection: connection, viewerID: account.userID, username: account.username,
                            amount: Money.parse(amount), day: ExpenseDay(date: date))
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                .disabled(parsed == nil || confirmedBalance == nil || parsed! > abs(confirmedBalance!) || confirmedBalance == 0)
                .accessibilityIdentifier("settle.save")
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } }
        }
        .alert("Couldn't Record Repayment", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
    }
}
