import XCTest
import SwiftData
@testable import MoneyTrack

@MainActor
final class AnnualPlanPersistenceTests: XCTestCase {
    func testTotalFirstDefaultSpendingPersistenceAndFailedSave() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let namespace = StoreNamespace.account(UUID())
        var store: LedgerStore? = try LedgerStore(container: LedgerPersistence.container(root: root, namespace: namespace))
        try store!.saveAnnualPlan(year: 2026, total: 120000, allocations: [])
        XCTAssertEqual(store!.annualPlans.first?.guiltFree, 120000)
        _ = try store!.saveExpense(amount: 5000, description: "Coffee and friends", categoryID: nil, day: ExpenseDay(iso: "2026-01-15"))
        let food = try store!.saveCategory(name: "Food", year: 2026, annualAmount: 60000)
        let result = try XCTUnwrap(store!.wholeBudget(month: .init(year: 2026, month: 1)))
        XCTAssertEqual(result.total.remaining, 5000)
        XCTAssertEqual(result.guiltFree.remaining, 0)
        XCTAssertEqual(result.categories.first { $0.id == food }?.remaining, 5000)
        let pending = store!.pendingChanges.count
        XCTAssertThrowsError(try store!.saveCategory(name: "Too much", year: 2026, annualAmount: 70000))
        XCTAssertEqual(store!.pendingChanges.count, pending)
        XCTAssertFalse(store!.categories.contains { $0.name == "Too much" })
        store = nil
        let reopened = try LedgerStore(container: LedgerPersistence.container(root: root, namespace: namespace))
        XCTAssertEqual(try reopened.wholeBudget(month: .init(year: 2026, month: 1))?.guiltFree.remaining, 0)
        XCTAssertEqual(reopened.expenses.count, 1)
        let readOnly = try LedgerStore(container: LedgerPersistence.container(root: root, namespace: namespace, allowsSave: false))
        XCTAssertThrowsError(try readOnly.saveAnnualPlan(year: 2026, total: 240000, allocations: readOnly.annualPlans[0].allocations))
        XCTAssertEqual(readOnly.annualPlans.first?.total, 120000)
        XCTAssertEqual(readOnly.pendingChanges.count, pending)
    }
    func testV3MigrationPreservesLegacyBudgetAndPreparedBytes() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let namespace = StoreNamespace.account(UUID()), category = CategoryValue(id: UUID(), name: "Old category")
        let directory = root.appending(path: namespace.directoryName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bytes = Data("prepared-v3-request-untouched".utf8), opID = UUID()
        try autoreleasepool {
            let schema = Schema(versionedSchema: LedgerSchemaV3.self)
            let config = ModelConfiguration("MoneyTrack", schema: schema, url: directory.appending(path: "ledger.store"), cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container); context.autosaveEnabled = false
            context.insert(CategoryRecord(category))
            context.insert(YearBudgetRecord(.init(id: UUID(), categoryID: category.id, year: 2026, amount: 120000)))
            context.insert(PendingChangeRecord(.init(id: opID, entityID: category.id, entity: "category", action: "upsert", sequence: 1, payload: Data("{}".utf8))))
            let state = LedgerSchemaV2.OperationState(id: opID, baseRevision: 1); state.wireData = bytes; context.insert(state)
            try context.save()
        }
        let migrated = try LedgerStore(container: LedgerPersistence.container(root: root, namespace: namespace))
        XCTAssertTrue(migrated.annualPlans.isEmpty)
        XCTAssertEqual(migrated.overview(month: .init(year: 2026, month: 1)).first?.remaining, 10000)
        XCTAssertEqual(try migrated.prepareNextOperation()?.1, bytes)
        try migrated.saveAnnualPlan(year: 2026, total: 120000, allocations: migrated.legacyAllocations(year: 2026))
        XCTAssertEqual(migrated.annualPlans.first?.guiltFree, 0)
        XCTAssertEqual(try migrated.prepareNextOperation()?.1, bytes)
    }
    func testNaturalYearCollisionResolvesToCanonicalPlanAndCopyRemapsReferences() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LedgerStore(container: LedgerPersistence.container(root: root, namespace: .account(UUID())))
        try store.saveAnnualPlan(year: 2026, total: 120000, allocations: [])
        while store.pendingChanges.first?.entity == "category" {
            let (id,data) = try XCTUnwrap(store.prepareNextOperation()), wire = try JSONDecoder().decode(WireOperation.self, from: data)
            try store.acknowledge(id, record: .init(entity: wire.entity, entityID: wire.entityID, revision: 1, deleted: false, payload: wire.payload))
        }
        let old = try XCTUnwrap(store.annualPlans.first)
        let remote = AnnualBudgetPlan(id: UUID(), year: 2026, total: 240000, freeCategoryID: old.freeCategoryID, allocations: [])
        try store.receive(ChangePage(changes: [.init(entity: "budget_plan", entityID: remote.id, revision: 1, deleted: false, payload: try .value(remote))], cursor: "test", hasMore: false))
        XCTAssertEqual(store.annualPlans.first?.id, old.id)
        try store.resolve(XCTUnwrap(store.issues.first), keepLocal: true)
        XCTAssertEqual(store.annualPlans.count, 1)
        XCTAssertEqual(store.annualPlans.first?.id, remote.id)
        let request = try JSONDecoder().decode(WireOperation.self, from: XCTUnwrap(store.prepareNextOperation()).1)
        XCTAssertEqual(request.expectedRevision, 1)
        let destination = try LedgerStore(container: LedgerPersistence.container(root: root, namespace: .account(UUID())))
        try destination.importLocal(store)
        XCTAssertNotEqual(destination.annualPlans.first?.freeCategoryID, store.annualPlans.first?.freeCategoryID)
        XCTAssertTrue(destination.categories.contains { $0.id == destination.annualPlans.first?.freeCategoryID })
        XCTAssertEqual(destination.annualPlans.first?.total, 120000)
    }
    func testDiscardRejectedEditRestoresConfirmedPlan() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LedgerStore(container: LedgerPersistence.container(root: root, namespace: .account(UUID())))
        try store.saveAnnualPlan(year: 2026, total: 120000, allocations: [])
        while let (id,bytes) = try store.prepareNextOperation() {
            let wire = try JSONDecoder().decode(WireOperation.self, from: bytes)
            try store.acknowledge(id, record: .init(entity: wire.entity, entityID: wire.entityID, revision: 1, deleted: false, payload: wire.payload))
        }
        try store.saveAnnualPlan(year: 2026, total: 240000, allocations: [])
        let (id,_) = try XCTUnwrap(store.prepareNextOperation())
        try store.recordIssue(id, message: "This update was rejected.", current: nil)
        try store.resolve(XCTUnwrap(store.issues.first), keepLocal: false)
        XCTAssertEqual(store.annualPlan(year: 2026)?.total, 120000)
        XCTAssertTrue(store.pendingChanges.isEmpty)
        XCTAssertTrue(store.issues.isEmpty)
    }
    func testDisplayedPendingPlanCanAllocateAfterItsOwnAcknowledgment() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LedgerStore(container: LedgerPersistence.container(root: root, namespace: .account(UUID())))
        try store.saveAnnualPlan(year: 2026, total: 120000, allocations: [])
        let displayed = try XCTUnwrap(store.annualPlans.first)
        while let (id,bytes) = try store.prepareNextOperation() {
            let wire = try JSONDecoder().decode(WireOperation.self, from: bytes)
            try store.acknowledge(id, record: .init(entity: wire.entity, entityID: wire.entityID, revision: 1, deleted: false, payload: wire.payload))
        }
        try store.saveCategory(name: "Food", year: 2026, annualAmount: 60000, planSnapshot: displayed, expectedPlanRevision: 0)
        while store.pendingChanges.first?.entity == "category" {
            let (id,bytes) = try XCTUnwrap(store.prepareNextOperation()), wire = try JSONDecoder().decode(WireOperation.self, from: bytes)
            try store.acknowledge(id, record: .init(entity: wire.entity, entityID: wire.entityID, revision: 1, deleted: false, payload: wire.payload))
        }
        let plan = try JSONDecoder().decode(WireOperation.self, from: XCTUnwrap(store.prepareNextOperation()).1)
        XCTAssertEqual(plan.expectedRevision, 1)
    }

}
