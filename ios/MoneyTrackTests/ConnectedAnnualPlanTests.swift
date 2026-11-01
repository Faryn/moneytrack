import XCTest
@testable import MoneyTrack

@MainActor
final class ConnectedAnnualPlanTests: XCTestCase {
    func testWholePlanGuiltFreeSyncRetryAndConflict() async throws {
        guard ProcessInfo.processInfo.environment["MONEYTRACK_TEST_SERVER"] == "http://127.0.0.1:4004" else { throw XCTSkip("Run scripts/check-connected for the temporary backend.") }
        let transport = HTTPTransport(), server = try ServerAddress.parse("http://127.0.0.1:4004")
        let credential = try await transport.signIn(server: server, username: "plan-fixture", password: "fixture-passphrase-2026")
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try LedgerStore(container: LedgerPersistence.container(root: root.appending(path: "a"), namespace: .account(credential.userID)))
        let b = try LedgerStore(container: LedgerPersistence.container(root: root.appending(path: "b"), namespace: .account(credential.userID)))
        try a.saveAnnualPlan(year: 2026, total: 120000, allocations: [])
        let category = try a.saveCategory(name: "Food", year: 2026, annualAmount: 60000)
        try a.saveExpense(amount: 2000, description: "Unassigned", categoryID: nil, day: ExpenseDay(iso: "2026-01-15"))
        try a.saveExpense(amount: 6000, description: "Category overspending", categoryID: category, day: ExpenseDay(iso: "2026-01-15"))
        try await pump(a, transport, credential)
        try await pump(b, transport, credential)
        let result = try XCTUnwrap(b.wholeBudget(month: .init(year: 2026, month: 1)))
        XCTAssertEqual(result.total.remaining, 2000)
        XCTAssertEqual(result.guiltFree.remaining, 3000)
        XCTAssertEqual(result.categories.first { $0.id == category }?.remaining, -1000)
        let plan = try XCTUnwrap(a.annualPlans.first)
        try a.saveAnnualPlan(year: 2026, total: 180000, allocations: plan.allocations)
        let lost = try XCTUnwrap(a.prepareNextOperation())
        let ack = try await transport.push(lost.1, credential: credential)
        let repeated = try await transport.push(lost.1, credential: credential)
        XCTAssertEqual(ack, repeated); try a.acknowledge(lost.0, record: ack)
        let stale = try XCTUnwrap(b.annualPlans.first)
        try b.saveAnnualPlan(year: 2026, total: 240000, allocations: stale.allocations)
        let pending = try XCTUnwrap(b.prepareNextOperation())
        do { _ = try await transport.push(pending.1, credential: credential); XCTFail("Stale plan must require review") }
        catch let rejection as ServerRejection { try b.recordIssue(pending.0, message: rejection.message, current: rejection.current) }
        XCTAssertEqual(b.annualPlans.first?.total, 240000)
        try b.resolve(XCTUnwrap(b.issues.first), keepLocal: false)
        XCTAssertEqual(b.annualPlans.first?.total, 180000)
        try await transport.signOut(credential)
    }
    private func pump(_ store: LedgerStore, _ transport: HTTPTransport, _ credential: SessionCredential) async throws {
        while let (id, data) = try store.prepareNextOperation() {
            let value = try await transport.push(data, credential: credential); try store.acknowledge(id, record: value)
        }
        repeat {
            let page = try await transport.pull(cursor: store.cursor, credential: credential); try store.receive(page)
            if !page.hasMore { break }
        } while true
    }
}
