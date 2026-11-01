import XCTest
@testable import MoneyTrack

final class SharedMathTests: XCTestCase {
    private struct Examples: Decodable { let version: Int; let cases: [Example] }
    private struct Example: Decodable {
        struct Expected: Decodable { let personalShare: Int64; let otherShare: Int64; let balance: Int64 }
        let id: String; let amount: Int64; let split: PersonalSplit; let paidByUser: Bool; let expected: Expected
    }
    func testCommonSharedExpenseExamples() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "shared-expense-examples", withExtension: "json"))
        let examples = try JSONDecoder().decode(Examples.self, from: Data(contentsOf: url))
        XCTAssertEqual(examples.version, 1)
        for e in examples.cases {
            let value = try SharedMath.calculate(amount: e.amount, split: e.split, paidByUser: e.paidByUser)
            XCTAssertEqual(value.personalShare, e.expected.personalShare, e.id)
            XCTAssertEqual(value.otherShare, e.expected.otherShare, e.id)
            XCTAssertEqual(value.balance, e.expected.balance, e.id)
        }
    }
    func testBothViewsConserveTheAmountAndBalance() throws {
        for amount in [Int64(1), 2, 3, 99, 100, 101, Money.maximum] {
            for split in PersonalSplit.allCases {
                for payer in [true, false] {
                    let inverse: PersonalSplit = split == .all ? .none : split == .none ? .all : .half
                    let own = try SharedMath.calculate(amount: amount, split: split, paidByUser: payer)
                    let other = try SharedMath.calculate(amount: amount, split: inverse, paidByUser: !payer)
                    XCTAssertEqual(own.personalShare + other.personalShare, amount)
                    XCTAssertEqual(own.balance, -other.balance)
                }
            }
        }
        for invalid in [Int64(0), -1, Money.maximum + 1] {
            XCTAssertThrowsError(try SharedMath.calculate(amount: invalid, split: .half, paidByUser: true))
        }
    }

    private struct SettlementExamples: Decodable { let version: Int; let cases: [SettlementExample] }
    private struct SettlementExample: Decodable {
        struct Expense: Decodable { let amount: Int64; let split: PersonalSplit; let paidByUser: Bool }
        struct Repayment: Decodable { let amount: Int64; let paidByUser: Bool }
        struct Expected: Decodable { let personalSpending: Int64; let otherSpending: Int64; let expenseBalance: Int64; let balance: Int64 }
        let id: String; let expenses: [Expense]; let repayments: [Repayment]; let expected: Expected
    }
    func testCommonRecordedRepaymentExamples() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "settlement-examples", withExtension: "json"))
        let examples = try JSONDecoder().decode(SettlementExamples.self, from: Data(contentsOf: url))
        XCTAssertEqual(examples.version, 1)
        for e in examples.cases {
            let expenses = try e.expenses.map { try SharedMath.calculate(amount: $0.amount, split: $0.split, paidByUser: $0.paidByUser) }
            let repayments = e.repayments.map { RepaymentAmounts(amount: $0.amount, paidByUser: $0.paidByUser) }
            let result = try SharedMath.summarize(expenses: expenses, repayments: repayments)
            XCTAssertEqual(result.personalSpending, e.expected.personalSpending, e.id)
            XCTAssertEqual(result.otherSpending, e.expected.otherSpending, e.id)
            XCTAssertEqual(result.expenseBalance, e.expected.expenseBalance, e.id)
            XCTAssertEqual(result.balance, e.expected.balance, e.id)
            let before = try SharedMath.summarize(expenses: expenses, repayments: [])
            XCTAssertEqual(result.personalSpending, before.personalSpending, e.id)
            XCTAssertEqual(result.otherSpending, before.otherSpending, e.id)
            let peerExpenses = expenses.map { SharedAmounts(personalShare: $0.otherShare, otherShare: $0.personalShare, balance: -$0.balance) }
            let peer = try SharedMath.summarize(expenses: peerExpenses,
                repayments: repayments.map { RepaymentAmounts(amount: $0.amount, paidByUser: !$0.paidByUser) })
            XCTAssertEqual(peer.balance, -result.balance, e.id)
            XCTAssertEqual(peer.personalSpending, result.otherSpending, e.id)
            XCTAssertEqual(try SharedMath.summarize(expenses: expenses.reversed(), repayments: repayments.reversed()), result, e.id)
        }
    }

    func testRepaymentsRejectInvalidAmountsAndTotalsNeverWrap() throws {
        for amount in [Int64(0), -1, Money.maximum + 1] {
            XCTAssertThrowsError(try SharedMath.summarize(expenses: [], repayments: [.init(amount: amount, paidByUser: true)]))
        }
        let nearLimit = SharedAmounts(personalShare: 0, otherShare: 0, balance: Int64.max)
        XCTAssertThrowsError(try SharedMath.summarize(expenses: [nearLimit], repayments: [.init(amount: 1, paidByUser: true)]))
        let offset = SharedAmounts(personalShare: 0, otherShare: 0, balance: -Int64.max)
        let values = [nearLimit, nearLimit, offset]
        XCTAssertEqual(try SharedMath.summarize(expenses: values, repayments: []).balance, Int64.max)
        XCTAssertEqual(try SharedMath.summarize(expenses: values.reversed(), repayments: []).balance, Int64.max)
    }

}
