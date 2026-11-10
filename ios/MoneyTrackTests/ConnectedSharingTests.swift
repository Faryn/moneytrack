import XCTest
import SwiftData
@testable import MoneyTrack

@MainActor
final class ConnectedSharingTests: XCTestCase {
    func testTwoAccountsShareSettleConflictDeleteAndKeepPrivateCategories() async throws {
        guard ProcessInfo.processInfo.environment["MONEYTRACK_TEST_SERVER"] == "http://127.0.0.1:4004" else {
            throw XCTSkip("Run scripts/check-connected for the isolated sharing check.")
        }
        let transport = HTTPTransport(), server = try ServerAddress.parse("http://127.0.0.1:4004")
        let a = try await transport.signIn(server: server, username: "shared-a-fixture", password: "fixture-passphrase-2026")
        let b = try await transport.signIn(server: server, username: "shared-b-fixture", password: "fixture-passphrase-2026")
        let outsider = try await transport.signIn(server: server, username: "shared-outsider-fixture", password: "fixture-passphrase-2026")
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func store(_ name: String) throws -> LedgerStore {
            try LedgerStore(container: LedgerPersistence.container(root: root.appending(path: name), namespace: .account(UUID())))
        }
        var sa: LedgerStore? = try store("a")
        let sb = try store("b")
        let category = try sa!.saveCategory(name: "A private restaurants", year: 2026, annualAmount: 600000)
        let conversion = CurrencyConversion(originalAmount: 9750, originalCurrency: "USD", rate: "1.25", rateDate: "2026-11-03", source: "ECB")
        let id = try sa!.saveExpense(amount: 7800, description: "Theodor", categoryID: category, day: ExpenseDay(iso: "2026-01-15"), conversion: conversion)
        // Queue sharing before personal uploads: preparation must wait for the source acknowledgment.
        try sa!.shareExpense(id, viewerID: a.userID, username: a.username, email: "shared-b@example.org", connection: nil, paidByUser: true, split: .half)
        XCTAssertEqual(sa!.overview(month: .init(year: 2026, month: 1)).first?.remaining, 46100)
        while sa!.pendingChanges.first?.entity != "shared_expense" {
            let op = try XCTUnwrap(sa!.prepareNextOperation()); let result = try await transport.push(op.1, credential: a)
            try sa!.acknowledge(op.0, record: result)
        }
        let lost = try XCTUnwrap(sa!.prepareNextOperation())
        let committed = try await transport.push(lost.1, credential: a)
        XCTAssertEqual(committed.entity, "shared_expense")
        XCTAssertEqual(try committed.payload.decoded(SharedExpenseValue.self).conversion, conversion)
        let repeated = try await transport.push(lost.1, credential: a)
        XCTAssertEqual(committed, repeated)
        try sa!.acknowledge(lost.0, record: repeated)
        try await pump(sa!, transport, a)
        try await pump(sb, transport, b)

        XCTAssertTrue(sb.expenses.isEmpty)
        let invitation = try XCTUnwrap(sb.invitations.first)
        try sb.acceptInvitation(invitation)
        try await pump(sb, transport, b)
        try await pump(sa!, transport, a)
        XCTAssertEqual(sb.expenses.first?.personalShare, 3900)
        XCTAssertEqual(sb.expenses.first?.conversion, conversion)
        XCTAssertEqual(sa!.expenses.filter { $0.id == id }.count, 1)
        XCTAssertFalse(sb.categories.contains { $0.name == "A private restaurants" })
        let connection = try XCTUnwrap(sa!.sharingConnections.first)
        XCTAssertEqual(try sa!.sharedBalance(connection.id), 3900)
        XCTAssertEqual(try sb.sharedBalance(connection.id), -3900)
        let bCategory = try sb.saveCategory(name: "B private leisure", year: 2026, annualAmount: 120000)
        let initial = try XCTUnwrap(sb.sharedExpenses.first)
        try sb.editSharedExpense(initial, amount: 7800, description: initial.description, categoryID: bCategory,
            day: initial.day, paidByUser: initial.paidByUser, ownSplit: initial.ownSplit)
        try await pump(sb, transport, b); try await pump(sa!, transport, a)
        XCTAssertFalse(sa!.categories.contains { $0.name == "B private leisure" })
        try sa!.recordRepayment(connection: connection, viewerID: a.userID, username: a.username, amount: 1500, day: ExpenseDay(iso: "2027-01-01"))
        XCTAssertEqual(try sa!.sharedBalance(connection.id), 2400)
        XCTAssertEqual(sa!.overview(month: .init(year: 2026, month: 1)).first?.remaining, 46100)
        let repayment = try XCTUnwrap(sa!.prepareNextOperation())
        let repaymentAck = try await transport.push(repayment.1, credential: a)
        let repaymentReplay = try await transport.push(repayment.1, credential: a)
        XCTAssertEqual(repaymentAck, repaymentReplay)
        try sa!.acknowledge(repayment.0, record: repaymentAck)
        try await pump(sa!, transport, a); try await pump(sb, transport, b)
        XCTAssertEqual(try sb.sharedBalance(connection.id), -2400)
        XCTAssertEqual(sb.repayments.count, 1)
        // Peer common edit makes an offline edit conflict; own assignment stays private.
        let old = try XCTUnwrap(sa!.sharedExpenses.first)
        try sa!.editSharedExpense(old, amount: 8000, description: "A offline edit", categoryID: old.categoryID,
            day: old.day, paidByUser: old.paidByUser, ownSplit: old.ownSplit)
        let peer = try XCTUnwrap(sb.sharedExpenses.first)
        try sb.editSharedExpense(peer, amount: 8200, description: "B common edit", categoryID: bCategory,
            day: peer.day, paidByUser: peer.paidByUser, ownSplit: peer.ownSplit)
        try await pump(sb, transport, b)
        let stale = try XCTUnwrap(sa!.prepareNextOperation())
        do { _ = try await transport.push(stale.1, credential: a); XCTFail("Expected a shared revision conflict") }
        catch let rejection as ServerRejection { try sa!.recordIssue(stale.0, message: rejection.message, current: rejection.current) }
        XCTAssertEqual(sa!.sharedExpenses.first?.description, "A offline edit")
        try sa!.resolve(XCTUnwrap(sa!.issues.first), keepLocal: false)
        XCTAssertEqual(sa!.sharedExpenses.first?.amount, 8200)
        let forbidden = try JSONEncoder().encode(WireOperation(operationID: UUID(), entity: "shared_expense", entityID: id,
            action: "delete", expectedRevision: 3, payload: .object(["id": .string(id.uuidString)])))
        do { _ = try await transport.push(forbidden, credential: outsider); XCTFail("Outsider must not mutate shared data") } catch is ServerRejection {}
        let empty = try await transport.pull(cursor: nil, credential: outsider)
        XCTAssertTrue(empty.changes.isEmpty)
        try sa!.deleteExpense(id)
        try await pump(sa!, transport, a); try await pump(sb, transport, b)
        XCTAssertTrue(sa!.expenses.isEmpty); XCTAssertTrue(sb.expenses.isEmpty)
        XCTAssertEqual(try sa!.sharedBalance(connection.id), -1500)
        XCTAssertEqual(sa!.repayments.count, 1)
        XCTAssertEqual(sb.sharedExpenses.first?.deleted, true)
        XCTAssertEqual(sa!.overview(month: .init(year: 2026, month: 1)).first?.remaining, 50000)
        let quick = try QuickExpenseParser.parse("5.01 rewe shared with \(connection.otherName)", categories: sa!.categories, connections: sa!.sharingConnections)
        let fromEntry = try sa!.saveExpense(amount: quick.amount, description: quick.description, categoryID: category,
            day: ExpenseDay(iso: "2026-01-15"), sharing: NewExpenseSharing(userID: a.userID, username: a.username, connection: try XCTUnwrap(quick.sharingConnection)))
        XCTAssertEqual(sa!.expenses.first { $0.id == fromEntry }?.personalShare, 251)
        try await pump(sa!, transport, a); try await pump(sb, transport, b)
        XCTAssertEqual(sb.expenses.first { $0.id == fromEntry }?.personalShare, 250)
        XCTAssertEqual(sb.sharedExpenses.first { $0.id == fromEntry }?.status, "accepted")
        XCTAssertTrue(sb.invitations.isEmpty)
        sa = nil
        try await transport.signOut(a); try await transport.signOut(b); try await transport.signOut(outsider)
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
