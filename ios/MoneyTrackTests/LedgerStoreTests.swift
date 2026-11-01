import XCTest
import SwiftData
@testable import MoneyTrack

@MainActor
final class LedgerStoreTests: XCTestCase {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    func testSaveEditDeleteAndOutboxSurviveReopening() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var store: LedgerStore? = try LedgerStore(container: LedgerPersistence.container(root: root))
        let category = try store!.saveCategory(name: "Restaurants", year: 2026, annualAmount: 120000)
        let id = try store!.saveExpense(amount: 7800, description: "Theodor", categoryID: category,
                                        day: ExpenseDay(iso: "2026-01-10"))
        let originalOperations = store!.pendingChanges.map(\.id)
        XCTAssertEqual(store!.pendingChanges.count, 3)
        store = nil
        let reopened = try LedgerStore(container: LedgerPersistence.container(root: root))
        XCTAssertEqual(reopened.expenses.first?.id, id)
        XCTAssertEqual(reopened.expenses.first?.amount, 7800)
        XCTAssertEqual(reopened.pendingChanges.map(\.id), originalOperations)
        XCTAssertEqual(reopened.overview(month: .init(year: 2026, month: 1)).first?.remaining, 2200)
        try reopened.saveExpense(id: id, amount: 9800, description: "Theodor", categoryID: category,
                                 day: ExpenseDay(iso: "2026-01-10"))
        XCTAssertEqual(reopened.overview(month: .init(year: 2026, month: 1)).first?.remaining, 200)
        try reopened.deleteExpense(id)
        let finalContainer = try LedgerPersistence.container(root: root)
        let final = try LedgerStore(container: finalContainer)
        XCTAssertTrue(final.expenses.isEmpty)
        XCTAssertEqual(final.overview(month: .init(year: 2026, month: 1)).first?.remaining, 10000)
        XCTAssertEqual(final.pendingChanges.map(\.sequence), [1, 2, 3, 4, 5])
        XCTAssertEqual(final.pendingChanges.last?.action, "delete")
        let tombstones = try ModelContext(finalContainer).fetch(FetchDescriptor<ExpenseRecord>())
        XCTAssertEqual(tombstones.count, 1)
        XCTAssertNotNil(tombstones.first?.deletedAt)
        for operation in final.pendingChanges {
            XCTAssertNotNil(try JSONSerialization.jsonObject(with: operation.payload))
        }
    }

    func testInvalidMutationLeavesDataAndOutboxUnchanged() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LedgerStore(container: LedgerPersistence.container(root: root))
        let category = try store.saveCategory(name: "Restaurants", year: 2026, annualAmount: 120000)
        let before = store.pendingChanges
        XCTAssertThrowsError(try store.saveExpense(amount: 0, description: "", categoryID: category,
                                                   day: ExpenseDay(iso: "2026-01-10")))
        XCTAssertThrowsError(try store.saveExpense(amount: 100, description: "", categoryID: UUID(),
                                                   day: ExpenseDay(iso: "2026-01-10")))
        XCTAssertThrowsError(try store.saveCategory(name: "restaurants", year: 2026, annualAmount: 120000))
        XCTAssertEqual(store.pendingChanges, before)
        XCTAssertTrue(store.expenses.isEmpty)
    }

    func testSeparateProfilesDoNotShareDataOrPendingOperations() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try LedgerStore(container: LedgerPersistence.container(root: root, namespace: .account(UUID())))
        try first.saveCategory(name: "Private", year: 2026, annualAmount: 120000)
        let second = try LedgerStore(container: LedgerPersistence.container(root: root, namespace: .account(UUID())))
        XCTAssertTrue(second.categories.isEmpty)
        XCTAssertTrue(second.pendingChanges.isEmpty)
        XCTAssertFalse(first.pendingChanges.isEmpty)
    }

    func testFailedDiskSaveRollsBackExpenseCategoryAndOutboxTogether() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var writable: LedgerStore? = try LedgerStore(container: LedgerPersistence.container(root: root))
        let category = try writable!.saveCategory(name: "Restaurants", year: 2026, annualAmount: 120000)
        let operations = writable!.pendingChanges
        writable = nil
        let readOnly = try LedgerStore(container: LedgerPersistence.container(root: root, allowsSave: false))
        XCTAssertThrowsError(try readOnly.saveExpense(amount: 7800, description: "Theodor", categoryID: category,
                                                      day: ExpenseDay(iso: "2026-01-10")))
        XCTAssertThrowsError(try readOnly.saveCategory(id: category, name: "Changed", year: 2026, annualAmount: 240000))
        XCTAssertTrue(readOnly.expenses.isEmpty)
        XCTAssertEqual(readOnly.categories.first?.name, "Restaurants")
        XCTAssertEqual(readOnly.budget(for: category, year: 2026)?.amount, 120000)
        XCTAssertEqual(readOnly.pendingChanges, operations)
        XCTAssertEqual(readOnly.saveCount, 0)
        let reopened = try LedgerStore(container: LedgerPersistence.container(root: root))
        XCTAssertTrue(reopened.expenses.isEmpty)
        XCTAssertEqual(reopened.categories.first?.name, "Restaurants")
        XCTAssertEqual(reopened.budget(for: category, year: 2026)?.amount, 120000)
        XCTAssertEqual(reopened.pendingChanges, operations)
    }

    func testAnnualEditAndBackdatedExpenseRecalculateTheYear() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LedgerStore(container: LedgerPersistence.container(root: root))
        let category = try store.saveCategory(name: "Restaurants", year: 2026, annualAmount: 120000)
        let expenseID = try store.saveExpense(amount: 15000, description: "", categoryID: category,
                                              day: ExpenseDay(iso: "2026-01-10"))
        XCTAssertEqual(store.overview(month: .init(year: 2026, month: 2)).first?.remaining, 5000)
        try store.saveCategory(id: category, name: "Restaurants", year: 2026, annualAmount: 240000)
        XCTAssertEqual(store.overview(month: .init(year: 2026, month: 2)).first?.remaining, 25000)
        try store.saveExpense(id: expenseID, amount: 15000, description: "", categoryID: category,
                              day: ExpenseDay(iso: "2026-02-10"))
        XCTAssertEqual(store.overview(month: .init(year: 2026, month: 1)).first?.remaining, 20000)
        XCTAssertEqual(store.overview(month: .init(year: 2026, month: 2)).first?.remaining, 25000)
    }
}
