import XCTest
@testable import MoneyTrack

final class AnnualPlanTests: XCTestCase {
    private struct Examples: Decodable { let version: Int; let cases: [Example] }
    private struct Example: Decodable {
        struct Entry: Decodable { let day: String; let categoryID: UUID; let amount: Int64; let personalShare: Int64 }
        struct Expected: Decodable { let total: Result; let guiltFree: Result; let categories: [String: Result] }
        struct Result: Decodable { let allocation: Int64; let carryover: Int64; let spent: Int64; let remaining: Int64 }
        let id: String; let year: Int; let month: Int; let total: Int64; let freeCategoryID: UUID
        let allocations: [CategoryAllocation]; let expenses: [Entry]; let expected: Expected
    }
    func testSharedWholeBudgetExamplesAndExactMonthlyConservation() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "annual-plan-examples", withExtension: "json"))
        let examples = try JSONDecoder().decode(Examples.self, from: Data(contentsOf: url))
        XCTAssertEqual(examples.version, 1)
        for e in examples.cases {
            let plan = AnnualBudgetPlan(id: UUID(), year: e.year, total: e.total, freeCategoryID: e.freeCategoryID, allocations: e.allocations)
            let ids = Set(e.allocations.map(\.categoryID) + e.expenses.map(\.categoryID) + [e.freeCategoryID])
            let categories = ids.map { CategoryValue(id: $0, name: "Category") }
            let expenses = try e.expenses.map { ExpenseValue(id: UUID(), categoryID: $0.categoryID, amount: $0.amount, personalShare: $0.personalShare,
                description: "", day: try ExpenseDay(iso: $0.day), createdAt: .now) }
            let result = try AnnualBudgetCalculator.overview(plan, month: .init(year: e.year, month: e.month), categories: categories, expenses: expenses)
            check(result.total, e.expected.total, e.id); check(result.guiltFree, e.expected.guiltFree, e.id)
            for row in result.categories where row.annual != nil {
                let expected = try XCTUnwrap(e.expected.categories[row.id.uuidString.lowercased()])
                check(.init(allocation: row.allocation, carryover: row.carryover, spent: row.spent), expected, e.id)
            }
            XCTAssertEqual(result.total.remaining, result.guiltFree.remaining + result.categories.filter { $0.annual != nil }.reduce(0) { $0 + $1.remaining }, e.id)
            let monthly = try AnnualBudgetCalculator.monthlyAllocations(plan)
            for month in 1...12 {
                XCTAssertEqual(monthly.values.reduce(0) { $0 + $1[month - 1] }, BudgetCalculator.cumulativeAllocation(annual: plan.total, through: month)-BudgetCalculator.cumulativeAllocation(annual: plan.total, through: month-1), e.id)
            }
            for allocation in e.allocations { XCTAssertEqual(monthly[allocation.categoryID]?.reduce(0,+), allocation.amount, e.id) }
        }
    }
    func testOverallocationsAndDefaultCategoryAllocationsAreRejected() throws {
        let id = UUID(), free = UUID()
        XCTAssertThrowsError(try AnnualBudgetPlan(id: UUID(), year: 2026, total: 100, freeCategoryID: free, allocations: [.init(categoryID: id, amount: 101)]).validate())
        XCTAssertThrowsError(try AnnualBudgetPlan(id: UUID(), year: 2026, total: 100, freeCategoryID: free, allocations: [.init(categoryID: free, amount: 1)]).validate())
    }
    private func check(_ value: BudgetAmounts, _ expected: Example.Result, _ id: String) {
        XCTAssertEqual(value.allocation, expected.allocation, id); XCTAssertEqual(value.carryover, expected.carryover, id)
        XCTAssertEqual(value.spent, expected.spent, id); XCTAssertEqual(value.remaining, expected.remaining, id)
    }
}
