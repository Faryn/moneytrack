import XCTest
@testable import MoneyTrack

@MainActor
final class ConnectedAPITests: XCTestCase {
    func testRealServerRetryConflictDeletionAndExpiredSessionRecovery() async throws {
        guard let address = ProcessInfo.processInfo.environment["MONEYTRACK_TEST_SERVER"],
              address == "http://127.0.0.1:4004" else { throw XCTSkip("Run scripts/check-connected for the isolated real-server check.") }
        let server = try ServerAddress.parse(address)
        let transport = HTTPTransport()
        let credential = try await transport.signIn(server: server, username: "native-core-fixture", password: "fixture-passphrase-2026")
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let aRoot = root.appending(path: "device-a"), bRoot = root.appending(path: "device-b")
        let namespace = StoreNamespace.serverAccount(server, credential.userID)
        var a: LedgerStore? = try LedgerStore(container: LedgerPersistence.container(root: aRoot, namespace: namespace))
        let category = try a!.saveCategory(name: "Restaurants", year: 2026, annualAmount: 120000)
        let expense = try a!.saveExpense(amount: 7800, description: "Theodor", categoryID: category, day: ExpenseDay(iso: "2026-01-15"))
        let lost = try XCTUnwrap(a!.prepareNextOperation())
        let committed = try await transport.push(lost.1, credential: credential)
        a = nil
        a = try LedgerStore(container: LedgerPersistence.container(root: aRoot, namespace: namespace))
        XCTAssertEqual(try a!.prepareNextOperation()?.1, lost.1)
        let replay = try await transport.push(lost.1, credential: credential)
        XCTAssertEqual(replay, committed)
        try a!.acknowledge(lost.0, record: replay)
        try await pump(a!, transport, credential)
        XCTAssertEqual(a!.overview(month: .init(year: 2026, month: 1)).first?.remaining, 2200)
        let b = try LedgerStore(container: LedgerPersistence.container(root: bRoot, namespace: namespace))
        try await pump(b, transport, credential)
        XCTAssertEqual(b.expenses.count, 1)
        try b.saveExpense(id: expense, amount: 9800, description: "Changed on another client", categoryID: category, day: ExpenseDay(iso: "2026-01-15"))
        try await pump(b, transport, credential)
        try a!.saveExpense(id: expense, amount: 8800, description: "My offline edit", categoryID: category, day: ExpenseDay(iso: "2026-01-15"))
        let stale = try XCTUnwrap(a!.prepareNextOperation())
        do {
            _ = try await transport.push(stale.1, credential: credential)
            XCTFail("Stale edit should not overwrite the server")
        } catch let conflict as ServerRejection {
            XCTAssertEqual(try conflict.current?.payload.decoded(ExpenseValue.self).amount, 9800)
            try a!.recordIssue(stale.0, message: conflict.message, current: conflict.current)
        }
        XCTAssertEqual(a!.expenses.first?.amount, 8800)
        try a!.resolve(XCTUnwrap(a!.issues.first), keepLocal: true)
        try await pump(a!, transport, credential)
        try await pump(b, transport, credential)
        XCTAssertEqual(b.expenses.first?.amount, 8800)
        try b.deleteExpense(expense)
        let deletion = try XCTUnwrap(b.prepareNextOperation())
        try await pump(b, transport, credential)
        let repeatedDeletion = try await transport.push(deletion.1, credential: credential)
        XCTAssertTrue(repeatedDeletion.deleted)
        try await pump(a!, transport, credential)
        XCTAssertTrue(a!.expenses.isEmpty)
        XCTAssertEqual(a!.overview(month: .init(year: 2026, month: 1)).first?.remaining, 10000)

        try await transport.signOut(credential)
        let vault = EphemeralVault(); try vault.write(credential)
        let session = AppSession(vault: vault, transport: transport, root: aRoot)
        try session.open()
        try session.store!.saveExpense(amount: 5000, description: "Saved after session expired", categoryID: category, day: ExpenseDay(iso: "2026-01-15"))
        await session.synchronize()
        let deadline = Date.now.addingTimeInterval(10)
        while !session.needsAuthentication && Date.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(session.needsAuthentication)
        XCTAssertEqual(session.store?.pendingChanges.count, 1)
        let preserved = try XCTUnwrap(session.store?.prepareNextOperation())
        try await session.signIn(server: address, username: "native-core-fixture", password: "fixture-passphrase-2026", copyLocal: false)
        let syncDeadline = Date.now.addingTimeInterval(10)
        while (session.store?.pendingChanges.isEmpty != true || session.isSyncing) && Date.now < syncDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(session.store?.pendingChanges.count, 0)
        XCTAssertEqual(session.store?.expenses.count, 1)
        XCTAssertEqual(session.store?.expenses.first?.amount, 5000)
        let request = try JSONDecoder().decode(WireOperation.self, from: preserved.1)
        XCTAssertEqual(session.store?.expenses.first?.id, request.entityID)
        try await session.signOut()
    }

    private func pump(_ store: LedgerStore, _ transport: HTTPTransport, _ credential: SessionCredential) async throws {
        while let (id, data) = try store.prepareNextOperation() {
            let response = try await transport.push(data, credential: credential)
            try store.acknowledge(id, record: response)
        }
        repeat {
            let page = try await transport.pull(cursor: store.cursor, credential: credential)
            try store.receive(page)
            if !page.hasMore { break }
        } while true
    }
}
