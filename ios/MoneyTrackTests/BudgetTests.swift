import XCTest
@testable import MoneyTrack

final class BudgetTests: XCTestCase {
    func testCurrencyUsesTwoDecimalPlacesAndRoundTripsExactly() throws {
        for localeID in ["en_US", "de_DE"] {
            let locale = Locale(identifier: localeID)
            let separator = locale.decimalSeparator!
            for cents in [Int64(0), 1, 10, 100, 7850, Money.maximum] {
                let input = Money.input(cents, locale: locale)
                XCTAssertEqual(input.components(separatedBy: separator).last?.count, 2)
                XCTAssertEqual(try Money.parse(input, allowZero: true), cents)
                XCTAssertTrue(Money.format(cents, locale: locale).contains(separator + String(format: "%02lld", cents % 100)))
            }
        }
        for invalid in ["1.001", "1,999", "0.009", "1.234,56", "1,234.56"] {
            XCTAssertThrowsError(try Money.parse(invalid))
        }
    }
    private struct Examples: Decodable {
        let version: Int
        let cases: [Example]
    }
    private struct Example: Decodable {
        let id: String
        let year: Int
        let month: Int
        let annual: Int64
        let expenses: [Entry]
        let expected: Result
    }
    private struct Entry: Decodable {
        let day: String
        let amount: Int64
        let personalShare: Int64
    }
    private struct Result: Decodable { let allocation: Int64, carryover: Int64, spent: Int64, remaining: Int64 }

    func testSharedFinancialExamples() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "budget-examples", withExtension: "json"))
        let examples = try JSONDecoder().decode(Examples.self, from: Data(contentsOf: url))
        XCTAssertEqual(examples.version, 1)
        let category = CategoryValue(id: UUID(), name: "Example")
        for example in examples.cases {
            let expenses = try example.expenses.map {
                ExpenseValue(id: UUID(), categoryID: category.id, amount: $0.amount, personalShare: $0.personalShare,
                             description: "", day: try ExpenseDay(iso: $0.day), createdAt: Date(timeIntervalSince1970: 0))
            }
            let result = BudgetCalculator.category(category, month: .init(year: example.year, month: example.month),
                                                   annual: example.annual, expenses: expenses)
            XCTAssertEqual(result.allocation, example.expected.allocation, example.id)
            XCTAssertEqual(result.carryover, example.expected.carryover, example.id)
            XCTAssertEqual(result.spent, example.expected.spent, example.id)
            XCTAssertEqual(result.remaining, example.expected.remaining, example.id)
        }
    }

    func testAllocationPreservesEveryCent() {
        for annual in [Int64(0), 1, 11, 12, 13, 100, 101, 600000, 999999] {
            let allocations = (1...12).map {
                BudgetCalculator.cumulativeAllocation(annual: annual, through: $0)
                    - BudgetCalculator.cumulativeAllocation(annual: annual, through: $0 - 1)
            }
            XCTAssertEqual(allocations.reduce(0, +), annual)
            XCTAssertLessThanOrEqual(allocations.max()! - allocations.min()!, 1)
        }
    }

    func testGermanAndEnglishAmountsRemainExact() throws {
        let amounts: [(String, Int64)] = [("78", 7800), ("78€", 7800), ("78,50", 7850), ("78.50", 7850), ("0,01", 1)]
        for (text, expected) in amounts {
            XCTAssertEqual(try Money.parse(text), expected)
        }
        XCTAssertEqual(try Money.parse("0", allowZero: true), 0)
        for invalid in ["", "-1", "0", "1.234", "1,234", "1e3", "7€8", "NaN", "78oops", "999999999999999999999"] {
            XCTAssertThrowsError(try Money.parse(invalid), invalid)
        }
        for locale in [Locale(identifier: "de_DE"), Locale(identifier: "en_US")] {
            XCTAssertEqual(try Money.parse(Money.input(7850, locale: locale)), 7850)
        }
    }

    func testCalendarDaysAreStrictAndIndependentOfTimeZone() throws {
        XCTAssertThrowsError(try ExpenseDay(iso: "2026-02-29"))
        XCTAssertThrowsError(try ExpenseDay(iso: "2026-02-30"))
        XCTAssertThrowsError(try ExpenseDay(iso: "2026-2-001"))
        XCTAssertThrowsError(try ExpenseDay(iso: "2026-+1-01"))
        XCTAssertThrowsError(try ExpenseDay(iso: "2026-01-+1"))
        XCTAssertEqual(try ExpenseDay(iso: "2024-02-29").iso, "2024-02-29")
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-01T00:30:00Z"))
        XCTAssertEqual(ExpenseDay(date: instant, timeZone: TimeZone(identifier: "America/Los_Angeles")!).iso, "2026-10-31")
        XCTAssertEqual(ExpenseDay(date: instant, timeZone: TimeZone(identifier: "Asia/Tokyo")!).iso, "2026-11-01")
        XCTAssertEqual(try ExpenseDay(iso: "2026-11-01").iso, "2026-11-01")
    }
}
