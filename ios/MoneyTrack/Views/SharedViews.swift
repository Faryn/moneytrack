import SwiftUI

struct SharedHomeView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(AppSession.self) private var app
    @State private var error: String?
    var body: some View {
        List {
            if app.credential == nil {
                ContentUnavailableView("Sign in to share", systemImage: "person.2", description: Text("Sign in from Account, then share a saved expense through its menu."))
            } else {
                if !store.issues.isEmpty {
                    Section { NavigationLink("Review Changes") { SyncReviewList() } }
                }
                if store.pendingChanges.contains(where: { ["shared_expense", "shared_assignment", "repayment"].contains($0.entity) }) {
                    Section { Label("Shared changes saved on this iPhone · awaiting sync", systemImage: "arrow.triangle.2.circlepath").font(.callout) }
                }
                if !store.invitations.isEmpty {
                    Section("Invitations") {
                        ForEach(store.invitations) { invitation in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(invitation.senderName) invited you").font(.headline)
                                Text("Your share starts in your private Uncategorized category.").font(.callout).foregroundStyle(.secondary)
                                Button("Accept Invitation") {
                                    do { try store.acceptInvitation(invitation) } catch { self.error = error.localizedDescription }
                                }
                                .disabled(store.pendingChanges.contains { $0.entity == "shared_expense" && $0.entityID == invitation.id })
                                .accessibilityIdentifier("sharing.accept.\(invitation.id)")
                            }
                        }
                    }
                }
                if !store.sharingConnections.isEmpty {
                    Section("People") {
                        ForEach(store.sharingConnections) { connection in
                            NavigationLink {
                                SharedPersonView(connection: connection)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(connection.otherName)
                                    SharedBalanceLabel(balance: try? store.sharedBalance(connection.id))
                                }
                            }
                            .accessibilityIdentifier("sharing.person.\(connection.otherName)")
                        }
                    }
                }
                let pending = store.sharedExpenses.filter { $0.status == "pending" && !$0.deleted }
                if !pending.isEmpty {
                    Section("Awaiting Acceptance") {
                        ForEach(pending) { value in
                            NavigationLink { ExpenseDetailView(expenseID: value.id) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(value.otherName)
                                    Text(value.description.isEmpty ? "Shared expense" : value.description).font(.subheadline)
                                    Text("Your proposed share already counts in your budget.").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if store.sharingConnections.isEmpty && pending.isEmpty && store.invitations.isEmpty {
                    ContentUnavailableView("No shared expenses", systemImage: "person.2", description: Text("Open a saved expense and choose Share Expense. Verify your email in Account to receive invitations."))
                }
            }
        }
        .navigationTitle("Shared")
        .refreshable { await app.synchronize() }
        .alert("Couldn't Accept Invitation", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }
}

struct SharedBalanceLabel: View {
    let balance: Int64?
    var body: some View {
        if let balance {
            Text(balance == 0 ? "Settled up" : "\(balance > 0 ? "Owes you" : "You owe") \(Money.format(abs(balance)))")
                .foregroundStyle(AmountColors.remaining(balance)).monospacedDigit()
                .accessibilityIdentifier("sharing.balance")
        } else { Text("Balance unavailable").foregroundStyle(.secondary) }
    }
}

struct SharedPersonView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(AppSession.self) private var app
    let connection: SharingConnection
    @State private var settling = false
    private var balance: Int64? { try? store.sharedBalance(connection.id) }
    var body: some View {
        List {
            Section {
                SharedBalanceLabel(balance: balance).font(.title2)
                Button("Settle Up") { settling = true }.disabled(balance == nil || balance == 0)
                    .accessibilityIdentifier("sharing.settle")
                if !store.issues.isEmpty { NavigationLink("Review Changes") { SyncReviewList() } }
                if store.pendingChanges.contains(where: { ["shared_expense", "shared_assignment", "repayment"].contains($0.entity) }) {
                    Text("Includes changes waiting to sync.").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("sharing.pending")
                }
            }
            let expenses = store.sharedExpenses.filter { $0.connection?.id == connection.id }.sorted { $0.day > $1.day }
            if !expenses.isEmpty {
                Section("Expenses") {
                    ForEach(expenses) { value in
                        NavigationLink { ExpenseDetailView(expenseID: value.id) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(value.description.isEmpty ? "Expense" : value.description)
                                Text(value.deleted ? "Deleted expense · history retained" : "\(Money.format(value.amount)) total · \(value.day.date.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            let repayments = store.repayments.filter { $0.connectionID == connection.id }
            if !repayments.isEmpty {
                Section("Repayments") {
                    ForEach(repayments) { value in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(value.paidByUser ? "You paid \(connection.otherName)" : "\(connection.otherName) paid you") · \(Money.format(value.amount))")
                            Text("\(value.day.date.formatted(date: .abbreviated, time: .omitted)) · Recorded by \(value.actorName)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(connection.otherName)
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
                        ForEach(store.sharingConnections) { c in Text(c.otherName).tag(Optional(c.id)) }
                    }
                }
                if connection == nil {
                    TextField("Email address", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("sharing.email")
                }
            }
            Section {
                Picker("Paid by", selection: $paidByUser) {
                    Text("You").tag(true); Text(connection?.otherName ?? "Other person").tag(false)
                }
                Picker("Your share", selection: $split) { ForEach(PersonalSplit.allCases, id: \.self) { Text($0.title).tag($0) } }
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
    init(value: SharedExpenseValue) {
        _original = State(initialValue: value); _amount = State(initialValue: Money.input(value.amount)); _description = State(initialValue: value.description)
        _categoryID = State(initialValue: value.categoryID); _date = State(initialValue: value.day.date)
        _paidByUser = State(initialValue: value.paidByUser); _split = State(initialValue: value.ownSplit)
    }
    var body: some View {
        Form {
            Section {
                CurrencyField(title: "Amount", text: $amount, identifier: "shared-edit.amount")
                TextField("Description", text: $description).accessibilityIdentifier("shared-edit.description")
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Paid by", selection: $paidByUser) { Text("You").tag(true); Text(original.otherName).tag(false) }
                Picker("Your share", selection: $split) { ForEach(PersonalSplit.allCases, id: \.self) { Text($0.title).tag($0) } }
            } header: { Text("Shared Details") } footer: { Text("Both people can see these changes and their history.") }
            Section {
                Picker("Your category", selection: $categoryID) { ForEach(store.categories) { Text($0.name).tag($0.id) } }
            } footer: { Text("Only you can see or change your category.") }
        }
        .navigationTitle("Edit Shared Expense")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    do {
                        try store.editSharedExpense(original, amount: Money.parse(amount), description: description,
                            categoryID: categoryID, day: ExpenseDay(date: date), paidByUser: paidByUser, ownSplit: split)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.disabled((try? Money.parse(amount)) == nil).accessibilityIdentifier("shared-edit.save")
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
                    Text(balance < 0 ? "You paid \(connection.otherName)" : "\(connection.otherName) paid you")
                    CurrencyField(title: "Amount", text: $amount, identifier: "settle.amount", focus: $focused)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                } footer: { Text("Only records a payment made outside MoneyTrack. Both people see the repayment; budgets stay unchanged.") }
                if let parsed, parsed <= abs(balance) {
                    Section("After Recording") { SharedBalanceLabel(balance: balance + (balance < 0 ? parsed : -parsed)) }
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
                            throw ConnectionError.rejected("The balance changed. Close this form and review it before recording.")
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
