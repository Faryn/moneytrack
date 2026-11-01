import XCTest
import SwiftData
@testable import MoneyTrack

@MainActor
final class SharedPersistenceTests: XCTestCase {
    func testOfflineProposalBudgetAndFrozenRequestSurviveReopenAndFailedSave() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let namespace = StoreNamespace.account(UUID()), viewer = UUID()
        var store: LedgerStore? = try LedgerStore(container: LedgerPersistence.container(root: root, namespace: namespace))
        let category = try store!.saveCategory(name: "Restaurants", year: 2026, annualAmount: 600000)
        let id = try store!.saveExpense(amount: 7800, description: "Theodor", categoryID: category, day: ExpenseDay(iso: "2026-01-15"))
        try store!.shareExpense(id, viewerID: viewer, username: "owner", email: "partner@example.org", connection: nil, paidByUser: true, split: .half)
        XCTAssertEqual(store!.expenses.count, 1)
        XCTAssertEqual(store!.overview(month: .init(year: 2026, month: 1)).first?.remaining, 46100)
        while store!.pendingChanges.first?.entity != "shared_expense" {
            let (opID, data) = try XCTUnwrap(store!.prepareNextOperation())
            let wire = try JSONDecoder().decode(WireOperation.self, from: data)
            try store!.acknowledge(opID, record: RemoteRecord(entity: wire.entity, entityID: wire.entityID,
                revision: 1, deleted: false, payload: wire.payload))
        }
        let prepared = try XCTUnwrap(store!.prepareNextOperation())
        let wire = try JSONDecoder().decode(WireOperation.self, from: prepared.1)
        if case .object(let fields) = wire.payload { XCTAssertEqual(fields["sourceRevision"], .integer(1)) } else { XCTFail() }
        store = nil
        let reopened = try LedgerStore(container: LedgerPersistence.container(root: root, namespace: namespace))
        XCTAssertEqual(try reopened.prepareNextOperation()?.1, prepared.1)
        XCTAssertEqual(reopened.expenses.first?.personalShare, 3900)
        XCTAssertEqual(reopened.pendingChanges.count, 1)
        let readOnly = try LedgerStore(container: LedgerPersistence.container(root: root, namespace: namespace, allowsSave: false))
        XCTAssertThrowsError(try readOnly.deleteExpense(id))
        XCTAssertEqual(readOnly.expenses.first?.personalShare, 3900)
        XCTAssertEqual(readOnly.sharedExpenses.first?.deleted, false)
        XCTAssertEqual(readOnly.pendingChanges.count, 1)
    }
    func testPopulatedV2MigratesToV3WithoutChangingPreparedBytesOrLocalRecords() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let namespace = StoreNamespace.account(UUID())
        let directory = root.appending(path: namespace.directoryName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "ledger.store")
        let category = CategoryValue(id: UUID(), name: "Existing")
        let expense = ExpenseValue(id: UUID(), categoryID: category.id, amount: 7800, personalShare: 7800,
            description: "Preserve me", day: try ExpenseDay(iso: "2026-01-15"), createdAt: .now)
        let operationID = UUID(), frozen = Data("exact-prepared-request-v2".utf8)
        try autoreleasepool {
            let schema = Schema(versionedSchema: LedgerSchemaV2.self)
            let config = ModelConfiguration("MoneyTrack", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container); context.autosaveEnabled = false
            context.insert(CategoryRecord(category)); context.insert(ExpenseRecord(expense))
            context.insert(PendingChangeRecord(.init(id: operationID, entityID: expense.id, entity: "expense", action: "upsert", sequence: 1, payload: Data("{}".utf8))))
            let state = LedgerSchemaV2.OperationState(id: operationID, baseRevision: 2); state.wireData = frozen; context.insert(state)
            try context.save()
        }
        let upgraded = try LedgerStore(container: LedgerPersistence.container(root: root, namespace: namespace))
        XCTAssertEqual(upgraded.expenses.first?.description, "Preserve me")
        XCTAssertEqual(upgraded.categories.first?.name, "Existing")
        XCTAssertEqual(try upgraded.prepareNextOperation()?.1, frozen)
        XCTAssertTrue(upgraded.sharedExpenses.isEmpty)
        XCTAssertTrue(upgraded.repayments.isEmpty)
    }
    func testQueuedProposalDoesNotRebaseOntoAPeerSourceEdit() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LedgerStore(container: LedgerPersistence.container(root: root, namespace: .account(UUID())))
        let category = try store.saveCategory(name: "Restaurants", year: 2026, annualAmount: 600000)
        let id = try store.saveExpense(amount: 7800, description: "Original", categoryID: category, day: ExpenseDay(iso: "2026-01-15"))
        try acknowledgePersonal(store)
        try store.shareExpense(id, viewerID: UUID(), username: "owner", email: "other@example.org", connection: nil, paidByUser: true, split: .half)
        var changed = try XCTUnwrap(store.expenses.first); changed.amount = 9900; changed.personalShare = 9900
        try store.receive(ChangePage(changes: [.init(entity: "expense", entityID: id, revision: 2, deleted: false, payload: try .value(changed))], cursor: "test-cursor", hasMore: false))
        let wire = try JSONDecoder().decode(WireOperation.self, from: XCTUnwrap(store.prepareNextOperation()).1)
        if case .object(let fields) = wire.payload { XCTAssertEqual(fields["sourceRevision"], .integer(1)) } else { XCTFail() }
        XCTAssertEqual(store.expenses.first?.amount, 7800)
    }
    func testOpenEditorUsesItsDisplayedRevisionAndPrivateCategoryDoesNotOverwritePeerFacts() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LedgerStore(container: LedgerPersistence.container(root: root, namespace: .account(UUID())))
        let category = try store.saveCategory(name: "Restaurants", year: 2026, annualAmount: 600000)
        let otherCategory = try store.saveCategory(name: "Leisure", year: 2026, annualAmount: 120000)
        let id = try store.saveExpense(amount: 7800, description: "Original", categoryID: category, day: ExpenseDay(iso: "2026-01-15"))
        try acknowledgePersonal(store)
        try store.shareExpense(id, viewerID: UUID(), username: "owner", email: "other@example.org", connection: nil, paidByUser: true, split: .half)
        let pending = try XCTUnwrap(store.prepareNextOperation())
        var initial = try XCTUnwrap(store.sharedExpenses.first); initial.revision = 1
        try store.acknowledge(pending.0, record: .init(entity: "shared_expense", entityID: id, revision: 1, deleted: false, payload: try .value(initial)))
        let displayed = try XCTUnwrap(store.sharedExpenses.first)
        var peer = displayed; peer.amount = 8200; peer.revision = 2
        try store.receive(ChangePage(changes: [.init(entity: "shared_expense", entityID: id, revision: 2, deleted: false, payload: try .value(peer))], cursor: "peer-edit", hasMore: false))
        try store.editSharedExpense(displayed, amount: displayed.amount, description: displayed.description, categoryID: otherCategory,
            day: displayed.day, paidByUser: displayed.paidByUser, ownSplit: displayed.ownSplit)
        XCTAssertEqual(store.expenses.first?.amount, 8200)
        XCTAssertEqual(store.pendingChanges.map(\.entity), ["shared_assignment"])
        let categoryOp = try XCTUnwrap(store.prepareNextOperation())
        try store.acknowledge(categoryOp.0, record: .init(entity: "shared_assignment", entityID: id, revision: 2, deleted: false,
            payload: try .value(SharedAssignment(id: id, categoryID: otherCategory))))
        try store.editSharedExpense(displayed, amount: 8000, description: "My displayed edit", categoryID: category,
            day: displayed.day, paidByUser: displayed.paidByUser, ownSplit: displayed.ownSplit)
        let stale = try JSONDecoder().decode(WireOperation.self, from: XCTUnwrap(store.prepareNextOperation()).1)
        XCTAssertEqual(stale.expectedRevision, 1)
    }
    private func acknowledgePersonal(_ store: LedgerStore) throws {
        while let (id, bytes) = try store.prepareNextOperation() {
            let wire = try JSONDecoder().decode(WireOperation.self, from: bytes)
            try store.acknowledge(id, record: .init(entity: wire.entity, entityID: wire.entityID, revision: 1, deleted: false, payload: wire.payload))
        }
    }

}
