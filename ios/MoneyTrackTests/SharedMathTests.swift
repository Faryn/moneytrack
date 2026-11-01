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
}
