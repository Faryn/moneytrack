import Foundation

struct CategoryAllocation: Codable, Equatable, Sendable {
    let categoryID: UUID
    let amount: Int64
}
struct AnnualBudgetPlan: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let year: Int
    var total: Int64
    let freeCategoryID: UUID
    var allocations: [CategoryAllocation]
    var allocated: Int64 { allocations.reduce(0) { $0 + $1.amount } }
    var unallocated: Int64 { total - allocated }
    func validate() throws {
        guard (1900...9999).contains(year), (0...Money.maximum).contains(total),
              allocations.allSatisfy({ (1...Money.maximum).contains($0.amount) && $0.categoryID != freeCategoryID }),
              Set(allocations.map(\.categoryID)).count == allocations.count else { throw LedgerError.invalidAmount }
        guard allocations.reduce(Int128(0), { $0 + Int128($1.amount) }) <= Int128(total) else { throw LedgerError.allocationsExceedTotal }
    }
}
struct BudgetAmounts: Equatable, Sendable {
    let allocation: Int64
    let carryover: Int64
    let spent: Int64
    var available: Int64 { allocation + carryover }
    var remaining: Int64 { available - spent }
}
struct AnnualBudgetOverview: Sendable {
    let total: BudgetAmounts
    let unallocated: Int64
    let unbudgeted: BudgetAmounts
    let categories: [CategoryBudget]
}
enum AnnualBudgetCalculator {
    static func monthlyAllocations(_ plan: AnnualBudgetPlan) throws -> [UUID: [Int64]] {
        try plan.validate()
        let parts = plan.allocations.sorted { $0.categoryID.uuidString < $1.categoryID.uuidString } +
            [CategoryAllocation(categoryID: plan.freeCategoryID, amount: plan.unallocated)]
        let base = parts.reduce(Int64(0)) { $0 + $1.amount / 12 }
        var capacity = (0..<12).map { plan.total / 12 + (Int64($0) < plan.total % 12 ? 1 : 0) - base }
        var result: [UUID: [Int64]] = [:]
        for part in parts {
            var amounts = Array(repeating: part.amount / 12, count: 12)
            let months = (0..<12).sorted { capacity[$0] == capacity[$1] ? $0 < $1 : capacity[$0] > capacity[$1] }
            for month in months.prefix(Int(part.amount % 12)) {
                guard capacity[month] > 0 else { throw LedgerError.invalidAmount }
                amounts[month] += 1; capacity[month] -= 1
            }
            result[part.categoryID] = amounts
        }
        return result
    }
    static func overview(_ plan: AnnualBudgetPlan, month: BudgetMonth, categories: [CategoryValue], expenses: [ExpenseValue]) throws -> AnnualBudgetOverview {
        let monthly = try monthlyAllocations(plan)
        let expenses = expenses.filter { !$0.isIncome }
        func amounts(_ allocation: [Int64], _ entries: [ExpenseValue]) -> BudgetAmounts {
            let yearEntries = entries.filter { $0.day.year == month.year }
            let before = yearEntries.filter { $0.day.month < month.month }.reduce(Int64(0)) { $0 + $1.personalShare }
            let spent = yearEntries.filter { $0.day.month == month.month }.reduce(Int64(0)) { $0 + $1.personalShare }
            return BudgetAmounts(allocation: allocation[month.month - 1], carryover: allocation.prefix(month.month - 1).reduce(0,+) - before, spent: spent)
        }
        let allocatedIDs = Set(plan.allocations.map(\.categoryID))
        let unbudgeted = amounts(Array(repeating: 0, count: 12), expenses.filter { !allocatedIDs.contains($0.categoryID) })
        let assignedMonths = (0..<12).map { month in
            plan.allocations.reduce(Int64(0)) { $0 + monthly[$1.categoryID]![month] }
        }
        let rows = categories.map { category -> CategoryBudget in
            let entries = expenses.filter { $0.categoryID == category.id }
            if let allocation = plan.allocations.first(where: { $0.categoryID == category.id }), let schedule = monthly[category.id] {
                let result = amounts(schedule, entries)
                return CategoryBudget(category: category, annual: allocation.amount, allocation: result.allocation, carryover: result.carryover, spent: result.spent, remaining: result.remaining)
            }
            let spent = entries.filter { $0.day.year == month.year && $0.day.month == month.month }.reduce(Int64(0)) { $0 + $1.personalShare }
            return CategoryBudget(category: category, annual: nil, allocation: 0, carryover: 0, spent: spent, remaining: 0)
        }
        return AnnualBudgetOverview(total: amounts(assignedMonths, expenses), unallocated: plan.unallocated, unbudgeted: unbudgeted, categories: rows)
    }
}
