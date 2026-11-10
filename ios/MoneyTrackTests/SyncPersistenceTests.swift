import XCTest
import SwiftData
@testable import MoneyTrack

private enum OriginalMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LedgerSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

@MainActor
final class SyncPersistenceTests: XCTestCase {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appending(path: UUID().uuidString) }
    private func remote(_ category: CategoryValue, revision: Int64) throws -> RemoteRecord {
        .init(entity: "category", entityID: category.id, revision: revision, deleted: false, payload: try .value(category))
    }

    func testArchivedCategoryLeavesActiveListsAndPreservesPreparedRename() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try LedgerPersistence.container(root: root)
        let store = try LedgerStore(container: container)
        let category = CategoryValue(id: UUID(), name: "Leisure")
        try store.receive(.init(changes: [remote(category, revision: 1)], cursor: "created", hasMore: false))
        try store.saveCategory(id: category.id, name: "My leisure", year: 2026, annualAmount: nil)
        let prepared = try XCTUnwrap(store.prepareNextOperation())
        let archived = RemoteRecord(entity: "category", entityID: category.id, revision: 2, deleted: false,
            payload: .object(["id": .string(category.id.uuidString), "name": .string(category.name), "archived": .bool(true)]))
        try store.receive(.init(changes: [archived], cursor: "archived", hasMore: false))
        XCTAssertTrue(store.activeCategories.isEmpty)
        XCTAssertTrue(store.overview(month: .init(year: 2026, month: 1)).isEmpty)
        let reopened = try LedgerStore(container: container)
        XCTAssertTrue(reopened.activeCategories.isEmpty)
        XCTAssertEqual(reopened.categories.first?.name, "My leisure")
        XCTAssertEqual(try reopened.prepareNextOperation()?.1, prepared.1)
        XCTAssertThrowsError(try reopened.saveExpense(amount: 100, description: "New expense", categoryID: category.id, day: ExpenseDay(iso: "2026-11-08")))
        try reopened.receive(.init(changes: [remote(category, revision: 3)], cursor: "restored", hasMore: false))
        XCTAssertEqual(reopened.activeCategories.map(\.id), [category.id])
    }

    func testPopulatedV1MigratesWithoutLosingPendingPayloadsOrTombstones() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appending(path: "local-device")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        let category = CategoryValue(id: UUID(), name: "Restaurants")
        let budget = YearBudgetValue(id: UUID(), categoryID: category.id, year: 2026, amount: 120000)
        let active = ExpenseValue(id: UUID(), categoryID: category.id, amount: 7800, personalShare: 7800,
            description: "Theodor", day: try ExpenseDay(iso: "2026-01-15"), createdAt: Date(timeIntervalSince1970: 0))
        let removed = ExpenseValue(id: UUID(), categoryID: category.id, amount: 100, personalShare: 100,
            description: "Deleted", day: active.day, createdAt: active.createdAt)
        let pending = PendingChangeValue(id: UUID(), entityID: category.id, entity: "category", action: "upsert", sequence: 1,
            payload: try JSONEncoder().encode(category))
        do {
            let schema = Schema(versionedSchema: LedgerSchemaV1.self)
            let config = ModelConfiguration("MoneyTrack", schema: schema, url: path.appending(path: "ledger.store"), cloudKitDatabase: .none)
            let old = try ModelContainer(for: schema, migrationPlan: OriginalMigrationPlan.self, configurations: [config])
            let context = ModelContext(old); context.autosaveEnabled = false
            context.insert(CategoryRecord(category)); context.insert(YearBudgetRecord(budget))
            context.insert(ExpenseRecord(active))
            let tombstone = ExpenseRecord(removed); tombstone.deletedAt = .now; context.insert(tombstone)
            context.insert(PendingChangeRecord(pending)); try context.save()
        }
        let container = try LedgerPersistence.container(root: root)
        let migrated = try LedgerStore(container: container)
        XCTAssertEqual(migrated.categories, [category])
        XCTAssertEqual(migrated.budgets, [budget])
        XCTAssertEqual(migrated.expenses, [active])
        XCTAssertEqual(migrated.pendingChanges, [pending])
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<ExpenseRecord>()).count, 2)
        let wire = try XCTUnwrap(migrated.prepareNextOperation())
        XCTAssertEqual(wire.0, pending.id)
        XCTAssertEqual(try JSONDecoder().decode(WireOperation.self, from: wire.1).expectedRevision, 0)
    }

    func testFrozenRetryAndDependentEditNeverRebaseSilentlyAfterRemoteChanges() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var store: LedgerStore? = try LedgerStore(container: LedgerPersistence.container(root: root))
        let id = try store!.saveCategory(name: "Original", year: 2026, annualAmount: nil)
        let first = try XCTUnwrap(store!.prepareNextOperation())
        try store!.saveCategory(id: id, name: "My later edit", year: 2026, annualAmount: nil)
        store = nil
        let reopened = try LedgerStore(container: LedgerPersistence.container(root: root))
        XCTAssertEqual(try reopened.prepareNextOperation()?.1, first.1)
        let elsewhere = try remote(.init(id: id, name: "Changed elsewhere"), revision: 2)
        try reopened.receive(.init(changes: [elsewhere], cursor: "cursor", hasMore: false))
        try reopened.acknowledge(first.0, record: remote(.init(id: id, name: "Original"), revision: 1))
        XCTAssertEqual(reopened.categories.first?.name, "My later edit")
        let second = try XCTUnwrap(reopened.prepareNextOperation())
        XCTAssertEqual(try JSONDecoder().decode(WireOperation.self, from: second.1).expectedRevision, 1)
        try reopened.recordIssue(second.0, message: "Changed elsewhere", current: elsewhere)
        let persisted = try LedgerStore(container: LedgerPersistence.container(root: root))
        XCTAssertEqual(persisted.issues.count, 1)
        XCTAssertNil(try persisted.prepareNextOperation())
        try persisted.resolve(XCTUnwrap(persisted.issues.first), keepLocal: true)
        let replacement = try XCTUnwrap(persisted.prepareNextOperation())
        XCTAssertNotEqual(replacement.0, second.0)
        XCTAssertEqual(try JSONDecoder().decode(WireOperation.self, from: replacement.1).expectedRevision, 2)
        XCTAssertEqual(persisted.categories.first?.name, "My later edit")
    }

    func testPullIsAtomicIdempotentAndDoesNotEchoRemoteWrites() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LedgerStore(container: LedgerPersistence.container(root: root))
        let category = CategoryValue(id: UUID(), name: "Restaurants")
        let record = try remote(category, revision: 1)
        let invalid = RemoteRecord(entity: "unsupported", entityID: UUID(), revision: 1, deleted: false, payload: .null)
        XCTAssertThrowsError(try store.receive(.init(changes: [record, invalid], cursor: "bad", hasMore: false)))
        let reopened = try LedgerStore(container: LedgerPersistence.container(root: root))
        XCTAssertTrue(reopened.categories.isEmpty)
        XCTAssertNil(try reopened.cursor)
        let page = ChangePage(changes: [record], cursor: "good", hasMore: false)
        try reopened.receive(page); try reopened.receive(page)
        XCTAssertEqual(reopened.categories, [category])
        XCTAssertTrue(reopened.pendingChanges.isEmpty)
        XCTAssertEqual(reopened.saveCount, 0)
        XCTAssertEqual(try LedgerStore(container: LedgerPersistence.container(root: root)).cursor, "good")
    }

    func testPullPreservesDeletionAndPreparedEditAcrossMixedRevisionsInOnePage() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try autoreleasepool {
            let container = try LedgerPersistence.container(root: root)
            let store = try LedgerStore(container: container)
            let category = CategoryValue(id: UUID(), name: "Restaurants")
            let day = try ExpenseDay(iso: "2026-11-08")
            func expense(_ name: String) -> ExpenseValue {
                .init(id: UUID(), categoryID: category.id, amount: 500, personalShare: 500,
                      description: name, day: day, createdAt: Date(timeIntervalSince1970: 0))
            }
            func record(_ value: ExpenseValue, revision: Int64, deleted: Bool = false) throws -> RemoteRecord {
                .init(entity: "expense", entityID: value.id, revision: revision, deleted: deleted, payload: try .value(value))
            }
            let edited = expense("Original")
            try store.receive(.init(changes: [remote(category, revision: 1), record(edited, revision: 1)], cursor: "initial", hasMore: false))
            try store.saveExpense(id: edited.id, amount: 600, description: "Local edit", categoryID: category.id, day: day)
            let prepared = try XCTUnwrap(store.prepareNextOperation())

            let removed = expense("Deleted during catch-up")
            let old = try record(removed, revision: 1)
            let deletion = try record(removed, revision: 2, deleted: true)
            let remoteEditDeletion = try record(edited, revision: 2, deleted: true)
            try store.receive(.init(changes: [old, deletion, old, remoteEditDeletion], cursor: "mixed", hasMore: false))

            let reopened = try LedgerStore(container: container)
            XCTAssertEqual(reopened.expenses.map(\.description), ["Local edit"])
            XCTAssertEqual(try reopened.recordRevision("expense", removed.id), 2)
            XCTAssertEqual(try reopened.recordRevision("expense", edited.id), 2)
            XCTAssertEqual(try reopened.prepareNextOperation()?.1, prepared.1)
            XCTAssertEqual(try reopened.cursor, "mixed")
        }
    }

    func testImportIsExplicitAtomicAndDoesNotDuplicateOrModifyTheSource() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let local = try LedgerStore(container: LedgerPersistence.container(root: root))
        let originalCategory = try local.saveCategory(name: "Restaurants", year: 2026, annualAmount: 120000)
        let originalExpense = try local.saveExpense(amount: 7800, description: "Theodor", categoryID: originalCategory,
            day: ExpenseDay(iso: "2026-01-15"))
        let pending = local.pendingChanges
        let accountID = UUID(), server = URL(string: "https://example.test")!
        let account = try LedgerStore(container: LedgerPersistence.container(root: root, namespace: .serverAccount(server, accountID)))
        XCTAssertTrue(account.expenses.isEmpty)
        try account.importLocal(local)
        XCTAssertEqual(account.expenses.count, 1)
        XCTAssertNotEqual(account.expenses.first?.id, originalExpense)
        XCTAssertNotEqual(account.categories.first?.id, originalCategory)
        XCTAssertEqual(account.expenses.first?.categoryID, account.categories.first?.id)
        XCTAssertEqual(account.overview(month: .init(year: 2026, month: 1)).first?.remaining, 2200)
        let copiedOperations = account.pendingChanges
        try account.importLocal(local)
        XCTAssertEqual(account.pendingChanges, copiedOperations)
        XCTAssertEqual(local.pendingChanges, pending)
        XCTAssertEqual(local.expenses.first?.id, originalExpense)
        let otherServer = try LedgerStore(container: LedgerPersistence.container(root: root,
            namespace: .serverAccount(URL(string: "https://another.test")!, accountID)))
        XCTAssertTrue(otherServer.expenses.isEmpty)
        try otherServer.saveCategory(name: "Existing", year: 2026, annualAmount: nil)
        XCTAssertThrowsError(try otherServer.importLocal(local))
        XCTAssertEqual(otherServer.categories.count, 1)
    }

    func testFailedAcknowledgmentRetainsTheExactRetryAfterReopening() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var writer: LedgerStore? = try LedgerStore(container: LedgerPersistence.container(root: root))
        let id = try writer!.saveCategory(name: "Restaurants", year: 2026, annualAmount: nil)
        let request = try XCTUnwrap(writer!.prepareNextOperation())
        writer = nil
        let readOnly = try LedgerStore(container: LedgerPersistence.container(root: root, allowsSave: false))
        XCTAssertThrowsError(try readOnly.acknowledge(request.0, record: remote(.init(id: id, name: "Restaurants"), revision: 1)))
        let reopened = try LedgerStore(container: LedgerPersistence.container(root: root))
        XCTAssertEqual(try reopened.prepareNextOperation()?.1, request.1)
        XCTAssertEqual(reopened.pendingChanges.first?.id, request.0)
    }

    func testConcurrentNewYearBudgetsResolveToOneCanonicalRecord() throws {
        for keepLocal in [false, true] {
            let root = directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let store = try LedgerStore(container: LedgerPersistence.container(root: root))
            let category = try store.saveCategory(name: "Restaurants", year: 2026, annualAmount: nil)
            let first = try XCTUnwrap(store.prepareNextOperation())
            try store.acknowledge(first.0, record: remote(.init(id: category, name: "Restaurants"), revision: 1))
            try store.saveCategory(id: category, name: "Restaurants", year: 2026, annualAmount: 120000)
            let other = YearBudgetValue(id: UUID(), categoryID: category, year: 2026, amount: 240000)
            let record = RemoteRecord(entity: "year_budget", entityID: other.id, revision: 1, deleted: false, payload: try .value(other))
            try store.receive(.init(changes: [record], cursor: "budget-cursor", hasMore: false))
            XCTAssertEqual(store.budgets.count, 1)
            XCTAssertNotEqual(store.budgets.first?.id, other.id)
            let categoryRequest = try XCTUnwrap(store.prepareNextOperation())
            try store.acknowledge(categoryRequest.0, record: remote(.init(id: category, name: "Restaurants"), revision: 2))
            try store.resolve(XCTUnwrap(store.issues.first), keepLocal: keepLocal)
            XCTAssertEqual(store.budgets.count, 1)
            XCTAssertEqual(store.budgets.first?.id, other.id)
            XCTAssertEqual(store.budgets.first?.amount, keepLocal ? 120000 : 240000)
            if keepLocal {
                let next = try XCTUnwrap(store.prepareNextOperation())
                let wire = try JSONDecoder().decode(WireOperation.self, from: next.1)
                XCTAssertEqual(wire.entityID, other.id)
                XCTAssertEqual(wire.expectedRevision, 1)
            } else { XCTAssertTrue(store.pendingChanges.isEmpty) }
        }
    }

    func testKeepingAnExpenseDeletedElsewhereCreatesANewID() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LedgerStore(container: LedgerPersistence.container(root: root))
        let category = try store.saveCategory(name: "Restaurants", year: 2026, annualAmount: nil)
        let categoryRequest = try XCTUnwrap(store.prepareNextOperation())
        try store.acknowledge(categoryRequest.0, record: remote(.init(id: category, name: "Restaurants"), revision: 1))
        let id = try store.saveExpense(amount: 7800, description: "Theodor", categoryID: category, day: ExpenseDay(iso: "2026-01-15"))
        let initial = try XCTUnwrap(store.prepareNextOperation())
        let original = try store.localPayload(entity: "expense", id: id).1
        try store.acknowledge(initial.0, record: .init(entity: "expense", entityID: id, revision: 1, deleted: false, payload: original))
        try store.saveExpense(id: id, amount: 9800, description: "My edit", categoryID: category, day: ExpenseDay(iso: "2026-01-15"))
        let stale = try XCTUnwrap(store.prepareNextOperation())
        try store.recordIssue(stale.0, message: "Deleted elsewhere", current: .init(entity: "expense", entityID: id, revision: 2, deleted: true, payload: original))
        try store.resolve(XCTUnwrap(store.issues.first), keepLocal: true)
        XCTAssertEqual(store.expenses.count, 1)
        XCTAssertNotEqual(store.expenses.first?.id, id)
        XCTAssertEqual(store.expenses.first?.amount, 9800)
        let next = try XCTUnwrap(store.prepareNextOperation())
        XCTAssertEqual(try JSONDecoder().decode(WireOperation.self, from: next.1).expectedRevision, 0)
    }

    func testKeychainRoundTripUsesAnIsolatedService() throws {
        let vault = KeychainVault(serviceSuffix: ".unit-test." + UUID().uuidString)
        defer { try? vault.clear() }
        XCTAssertNil(try vault.read())
        let value = SessionCredential(userID: UUID(), username: "fixture", server: URL(string: "https://example.test")!, token: "synthetic-session-token")
        try vault.write(value)
        XCTAssertEqual(try vault.read(), value)
        try vault.clear()
        XCTAssertNil(try vault.read())
    }

    func testConfiguredServerIsDefaultAndTestsNeverFallBackToIt() {
        XCTAssertEqual(ServerAddress.initialSignInAddress(configured: "https://APP.example.invalid/"), "https://app.example.invalid")
        XCTAssertEqual(ServerAddress.initialSignInAddress(configured: nil), "")
        XCTAssertEqual(ServerAddress.initialSignInAddress(configured: "$(UNSET_SERVER)"), "")
        XCTAssertEqual(ServerAddress.initialSignInAddress(configured: "https://app.example.invalid", isTesting: true), "")
        XCTAssertEqual(ServerAddress.initialSignInAddress(configured: "https://app.example.invalid", isTesting: true, testingServer: "http://127.0.0.1:4004"), "http://127.0.0.1:4004")
        XCTAssertEqual(ServerAddress.initialSignInAddress(configured: "https://app.example.invalid", isTesting: true, testingServer: "not-a-url"), "")
    }

    func testOnlySecureRootServerAddressesAreAccepted() throws {
        XCTAssertEqual(try ServerAddress.parse("https://EXAMPLE.test:443/"), URL(string: "https://example.test"))
        for invalid in ["http://example.test", "https://user:password@example.test", "https://example.test/path", "https://example.test?token=secret", "https://example.test#fragment", "not-a-url"] {
            XCTAssertThrowsError(try ServerAddress.parse(invalid), invalid)
        }
    }
}


@MainActor
final class IncomePersistenceTests: XCTestCase {
    private func root() -> URL { FileManager.default.temporaryDirectory.appending(path: UUID().uuidString) }

    func testIncomePersistsAndDoesNotChangeSpendingOrCarryover() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        var store: LedgerStore? = try LedgerStore(container: LedgerPersistence.container(root: directory))
        let category = try store!.saveCategory(name: "Gehalt", year: 2026, annualAmount: nil)
        try store!.saveAnnualPlan(year: 2026, total: 120000, allocations: [])
        let before = try XCTUnwrap(store!.wholeBudget(month: .init(year: 2026, month: 2)))
        let id = try store!.saveExpense(amount: 200000, description: "Salary", categoryID: category,
            day: ExpenseDay(iso: "2026-01-31"), kind: .income)
        XCTAssertEqual(try store!.wholeBudget(month: .init(year: 2026, month: 2))?.total, before.total)
        XCTAssertEqual(try store!.wholeBudget(month: .init(year: 2026, month: 2))?.unbudgeted, before.unbudgeted)
        XCTAssertEqual(store!.expenses.first?.signedAmount, 200000)
        store = nil
        let reopened = try LedgerStore(container: LedgerPersistence.container(root: directory))
        XCTAssertTrue(try XCTUnwrap(reopened.expenses.first).isIncome)
        try reopened.saveExpense(id: id, amount: 210000, description: "Updated", categoryID: category, day: ExpenseDay(iso: "2026-01-31"))
        XCTAssertTrue(try XCTUnwrap(reopened.expenses.first).isIncome)
        let copy = try LedgerStore(container: LedgerPersistence.container(root: directory, namespace: .account(UUID())))
        try copy.importLocal(reopened)
        XCTAssertTrue(try XCTUnwrap(copy.expenses.first).isIncome)
        try reopened.deleteExpense(id)
        XCTAssertTrue(reopened.expenses.isEmpty)
    }

    func testIncomePullAndDeletionAreIdempotentAndBadTypeRollsBack() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LedgerStore(container: LedgerPersistence.container(root: directory))
        let category = CategoryValue(id: UUID(), name: "Gehalt")
        let income = ExpenseValue(id: UUID(), categoryID: category.id, amount: 200000, personalShare: 200000,
            description: "Salary", day: try ExpenseDay(iso: "2026-01-31"), createdAt: Date(timeIntervalSince1970: 0), kind: .income)
        let remote = RemoteRecord(entity: "expense", entityID: income.id, revision: 1, deleted: false, payload: try .value(income))
        let page = ChangePage(changes: [.init(entity: "category", entityID: category.id, revision: 1, deleted: false, payload: try .value(category)), remote], cursor: "income", hasMore: false)
        try store.receive(page); try store.receive(page)
        XCTAssertEqual(store.expenses, [income])
        XCTAssertEqual(store.overview(month: .init(year: 2026, month: 1)).first?.spent, 0)
        var invalid = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(income)) as? [String: Any])
        invalid["kind"] = "refund"
        let invalidValue = try JSONDecoder().decode(JSONValue.self, from: JSONSerialization.data(withJSONObject: invalid))
        XCTAssertThrowsError(try store.receive(.init(changes: [.init(entity: "expense", entityID: income.id, revision: 2, deleted: false, payload: invalidValue)], cursor: "bad", hasMore: false)))
        XCTAssertEqual(store.expenses, [income])
        let tombstone = RemoteRecord(entity: "expense", entityID: income.id, revision: 2, deleted: true, payload: try .value(income))
        try store.receive(.init(changes: [tombstone], cursor: "deleted", hasMore: false))
        try store.receive(.init(changes: [tombstone], cursor: "deleted", hasMore: false))
        XCTAssertTrue(store.expenses.isEmpty)
    }

    func testV5MigrationPreservesPreparedBytesAndExpenseDirection() throws {
        let directory = root(), namespace = StoreNamespace.account(UUID())
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appending(path: namespace.directoryName)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        let category = CategoryValue(id: UUID(), name: "Food"), opID = UUID()
        let expense = ExpenseValue(id: UUID(), categoryID: category.id, amount: 1200, personalShare: 1200,
            description: "Food", day: try ExpenseDay(iso: "2026-01-01"), createdAt: Date(timeIntervalSince1970: 0))
        let bytes = Data("prepared-before-income".utf8)
        do {
            let schema = Schema(versionedSchema: LedgerSchemaV5.self)
            let config = ModelConfiguration("MoneyTrack", schema: schema, url: path.appending(path: "ledger.store"), cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container); context.autosaveEnabled = false
            context.insert(CategoryRecord(category)); context.insert(ExpenseRecord(expense))
            context.insert(PendingChangeRecord(.init(id: opID, entityID: expense.id, entity: "expense", action: "upsert", sequence: 1, payload: Data("{}".utf8))))
            let state = LedgerSchemaV2.OperationState(id: opID, baseRevision: 1); state.wireData = bytes; context.insert(state)
            try context.save()
        }
        let migrated = try LedgerStore(container: LedgerPersistence.container(root: directory, namespace: namespace))
        XCTAssertEqual(migrated.expenses, [expense])
        XCTAssertEqual(try migrated.prepareNextOperation()?.1, bytes)
    }

    func testIncomeSaveFailureRollsBackMarkerDomainAndOutbox() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let store = try LedgerStore(container: LedgerPersistence.container(root: directory))
            _ = try store.saveCategory(name: "Gehalt", year: 2026, annualAmount: nil)
        }
        let container = try LedgerPersistence.container(root: directory, allowsSave: false)
        let store = try LedgerStore(container: container), before = store.pendingChanges.count
        XCTAssertThrowsError(try store.saveExpense(amount: 200000, description: "Salary", categoryID: store.categories.first!.id,
            day: ExpenseDay(iso: "2026-01-31"), kind: .income))
        XCTAssertTrue(store.expenses.isEmpty)
        XCTAssertEqual(store.pendingChanges.count, before)
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<LedgerSchemaV6.IncomeRecord>()).isEmpty)
    }
}
