import SwiftUI

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var app
    @Environment(LedgerStore.self) private var store
    @State private var error: String?
    @State private var confirmSignOut = false
    var body: some View {
        Form {
            if let account = app.credential {
                Section("Account") {
                    LabeledContent("Username", value: account.username)
                    LabeledContent("Server", value: account.server.host() ?? account.server.absoluteString)
                    NavigationLink("Email for Sharing") { EmailVerificationView() }
                        .disabled(app.needsAuthentication).accessibilityIdentifier("account.email")
                }
                Section {
                    Label(app.status, systemImage: app.needsAuthentication ? "person.crop.circle.badge.exclamationmark" : "arrow.triangle.2.circlepath")
                        .accessibilityIdentifier("account.sync-status")
                    LabeledContent("Pending changes", value: String(store.pendingChanges.count))
                        .accessibilityIdentifier("account.pending")
                    if let message = app.syncError { Text(message).font(.callout).foregroundStyle(.secondary) }
                    if app.needsAuthentication {
                        NavigationLink("Sign In Again") { SignInView() }
                    } else {
                        Button("Sync Now") { Task { await app.synchronize() } }.disabled(app.isSyncing)
                    }
                    if !store.issues.isEmpty {
                        NavigationLink("Review Changes (\(store.issues.count))") { SyncReviewList() }
                    }
                } header: { Text("Synchronization") } footer: {
                    Text("Expenses save immediately on this iPhone. Pending changes stay here until the server accepts them.")
                }
                Section {
                    Button("Sign Out", role: .destructive) { confirmSignOut = true }
                }
            } else {
                Section {
                    LabeledContent("Storage", value: String(localized: "On this iPhone"))
                    NavigationLink("Sign In") { SignInView() }
                        .accessibilityIdentifier("account.sign-in")
                } footer: {
                    Text("Your entries aren't connected to a Spendie account. Signing in keeps them separate unless you choose to copy them.")
                }
            }
            Section {
                NavigationLink { PrivacyView() } label: { Label("Privacy", systemImage: "hand.raised") }
                    .accessibilityIdentifier("account.privacy")
            }
        }
        .navigationTitle("Account")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } }
        }
        .confirmationDialog("Sign out on this iPhone?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { do { try await app.signOut() } catch { self.error = error.localizedDescription } }
            }
        } message: { Text("Your account's saved entries and pending changes stay on this iPhone for your next sign-in.") }
        .alert("Couldn't Sign Out", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }
}

private struct PrivacyNotice: Decodable {
    struct Part: Decodable, Identifiable {
        struct Reference: Decodable {
            let title: String
            let url: URL
        }
        let id: String
        let title: String
        let paragraphs: [String]
        let links: [Reference]?
    }
    let title: String
    let updated: String
    let summary: String
    let sections: [Part]

    static func load() -> PrivacyNotice? {
        let resource = Bundle.main.preferredLocalizations.first == "de" ? "privacy.de" : "privacy"
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

private struct PrivacyView: View {
    private let notice = PrivacyNotice.load()
    var body: some View {
        List {
            if let notice {
                Section {
                    Text(notice.summary).accessibilityIdentifier("privacy.summary")
                    Text("Updated \(notice.updated)").font(.footnote).foregroundStyle(.secondary)
                } header: { Text(notice.title) }
                ForEach(notice.sections) { part in
                    Section(part.title) {
                        ForEach(part.paragraphs, id: \.self) { Text($0).textSelection(.enabled) }
                        ForEach(part.links ?? [], id: \.url) { reference in
                            Link(reference.title, destination: reference.url)
                        }
                    }
                }
            } else {
                ContentUnavailableView("Privacy information unavailable", systemImage: "hand.raised", description: Text("Contact your Spendie administrator for information about your data."))
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SignInView: View {
    @Environment(AppSession.self) private var app
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var copyLocal = false
    @State private var working = false
    @State private var signInTask: Task<Void, Never>?
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                TextField("Username", text: $username)
                    .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .disabled(app.credential != nil).accessibilityIdentifier("login.username")
                SecureField("Password", text: $password)
                    .textContentType(.password).accessibilityIdentifier("login.password")
            } footer: { Text("Accounts are created by the administrator. Your password isn't stored by Spendie on this iPhone.") }
            if server.isEmpty {
                Section { Text("The app's server hasn't been configured. Contact your administrator.").foregroundStyle(.secondary) }
            }
            #if DEBUG
            Section {
                DisclosureGroup("Development Server") {
                    TextField("Server address", text: $server)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .disabled(app.credential != nil).accessibilityIdentifier("login.server")
                }
            }
            #endif
            if app.credential == nil && !store.categories.isEmpty {
                Section {
                    Toggle("Copy on-device entries", isOn: $copyLocal)
                        .accessibilityIdentifier("login.copy-local")
                } footer: {
                    Text("Optional, once per account. Copies your current categories, budgets, and expenses into an empty account. Originals stay on this iPhone.")
                }
            }
            Section {
                Button(working ? "Signing In…" : "Sign In") {
                    working = true
                    signInTask = Task {
                        defer { working = false }
                        do {
                            try await app.signIn(server: server, username: username, password: password, copyLocal: copyLocal)
                            password = ""
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }
                .disabled(working || username.isEmpty || password.isEmpty || (try? ServerAddress.parse(server)) == nil)
                .accessibilityIdentifier("login.submit")
            }
        }
        .navigationTitle("Sign In")
        .onDisappear { signInTask?.cancel() }
        .onAppear {
            if let current = app.credential { server = current.server.absoluteString; username = current.username }
            else if server.isEmpty { server = ServerAddress.defaultSignInAddress }
        }
        .alert("Couldn't Sign In", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }
}

struct SyncReviewList: View {
    @Environment(LedgerStore.self) private var store
    var body: some View {
        List {
            ForEach(store.issues) { issue in
                NavigationLink { SyncReviewDetail(issue: issue) } label: {
                    Label(issue.entity == "expense" ? "Expense" : issue.entity == "category" ? "Category" : "Yearly budget", systemImage: "exclamationmark.triangle")
                }
            }
        }
        .navigationTitle("Review Changes")
    }
}

private struct SyncReviewDetail: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let issue: SyncIssue
    @State private var error: String?
    @State private var confirmKeep = false
    private var isSharingProposal: Bool {
        guard let change = store.pendingChanges.first(where: { $0.id == issue.id }),
              let payload = try? JSONDecoder().decode(JSONValue.self, from: change.payload), case .object(let fields) = payload else { return false }
        return fields["command"] == .string("share")
    }
    var body: some View {
        List {
            Section { Text(Bundle.main.localizedString(forKey: issue.message, value: issue.message, table: nil)) }
            Section("On this iPhone") {
                if let local = try? store.localPayload(entity: issue.entity, id: issue.entityID) {
                    if local.0 == "delete" { Text("Deleted on this iPhone") }
                    else { RecordSummary(entity: issue.entity, payload: local.1) }
                    if issue.entity == "category", let category = store.categories.first(where: { $0.id == issue.entityID }) {
                        NavigationLink("Edit Category") { CategoryEditor(category: category, year: ExpenseDay(date: store.today).year) }
                    }
                }
            }
            if let remote = issue.current {
                Section("On the server") {
                    if remote.deleted { Text("Deleted on the server") }
                    else { RecordSummary(entity: remote.entity, payload: remote.payload) }
                }
                Section { Button("Use Server Version") { resolve(keep: false) } }
            }
            Section {
                if !isSharingProposal && (issue.current != nil || !["shared_expense", "shared_assignment", "repayment", "budget_plan", "year_budget"].contains(issue.entity)) && (issue.current?.deleted != true || issue.entity == "expense") {
                    Button(issue.current?.deleted == true ? "Save as New Expense" : "Keep My Current Changes") { confirmKeep = true }
                }
                if ["shared_expense", "shared_assignment", "repayment", "budget_plan", "year_budget"].contains(issue.entity) && issue.current == nil {
                    Button("Discard This Draft", role: .destructive) { resolve(keep: false) }
                }
            } footer: {
                Text("Keeping your changes submits the current version on this iPhone. If it changed again elsewhere, you'll review it again.")
            }
        }
        .navigationTitle("Compare Versions")
        .confirmationDialog("Submit your current changes?", isPresented: $confirmKeep, titleVisibility: .visible) {
            Button("Keep My Changes") { resolve(keep: true) }
        }
        .alert("Couldn't Resolve Change", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }
    private func resolve(keep: Bool) {
        do { try store.resolve(issue, keepLocal: keep); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

private struct RecordSummary: View {
    @Environment(LedgerStore.self) private var store
    let entity: String
    let payload: JSONValue
    var body: some View {
        if entity == "budget_plan", let value = try? payload.decoded(AnnualBudgetPlan.self) {
            LabeledContent("Year", value: String(value.year))
            LabeledContent("Whole yearly budget", value: Money.format(value.total))
            LabeledContent("Unallocated", value: Money.format(value.unallocated))
            ForEach(value.allocations, id: \.categoryID) { allocation in
                LabeledContent(store.categories.first { $0.id == allocation.categoryID }?.name ?? String(localized: "Category"), value: Money.format(allocation.amount))
            }
        } else if entity == "shared_expense", case .object(let fields) = payload {
            if case .integer(let amount) = fields["amount"] { LabeledContent("Total purchase", value: Money.format(amount)) }
            if case .string(let description) = fields["description"] { LabeledContent("Description", value: description) }
            if let day = fields["day"], let date = try? day.decoded(ExpenseDay.self) { LabeledContent("Date", value: date.date.formatted(date: .abbreviated, time: .omitted)) }
            if case .string(let split) = fields["creatorSplit"] {
                LabeledContent("Creator's share", value: PersonalSplit(rawValue: split)?.title ?? split)
            }
            if case .bool(let paid) = fields["paidByCreator"] { LabeledContent("Payer", value: paid ? String(localized: "Original creator") : String(localized: "Other participant")) }
        } else if entity == "repayment", case .object(let fields) = payload {
            if case .integer(let amount) = fields["amount"] { LabeledContent("Repayment", value: Money.format(amount)) }
            Text("This records a payment made outside Spendie. If the balance changed, discard this draft and review the current balance before recording again.").font(.callout)
        } else if entity == "shared_assignment", let value = try? payload.decoded(SharedAssignment.self) {
            LabeledContent("Your private category", value: store.categories.first { $0.id == value.categoryID }?.name ?? String(localized: "Category unavailable"))
        } else if entity == "expense", let value = try? payload.decoded(ExpenseValue.self) {
            LabeledContent("Amount", value: Money.format(value.amount))
            LabeledContent("Category", value: store.categories.first { $0.id == value.categoryID }?.name ?? String(localized: "Category unavailable"))
            LabeledContent("Description", value: value.description)
            LabeledContent("Date", value: value.day.date.formatted(date: .abbreviated, time: .omitted))
        } else if entity == "category", let value = try? payload.decoded(CategoryValue.self) {
            LabeledContent("Name", value: value.name)
        } else if entity == "year_budget", let value = try? payload.decoded(YearBudgetValue.self) {
            LabeledContent("Category", value: store.categories.first { $0.id == value.categoryID }?.name ?? String(localized: "Category unavailable"))
            LabeledContent("Year", value: String(value.year))
            LabeledContent("Yearly amount", value: Money.format(value.amount))
        }
    }
}
