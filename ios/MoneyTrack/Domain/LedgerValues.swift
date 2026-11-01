import Foundation

enum LedgerError: LocalizedError {
    case invalidAmount, invalidDate, missingCategory, emptyCategory, duplicateCategory, missingExpense
    case sharedEditingUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidAmount: "Enter a valid amount with at most two decimal places."
        case .invalidDate: "Choose a valid calendar date."
        case .missingCategory: "Choose a category for this expense."
        case .emptyCategory: "Enter a category name."
        case .duplicateCategory: "A category with this name already exists."
        case .missingExpense: "This expense is no longer available."
        case .sharedEditingUnavailable: "This shared expense needs to be edited through its connected account."
        }
    }
}

enum Money {
    static let maximum: Int64 = 999_999_999_99

    static func parse(_ input: String, allowZero: Bool = false) throws -> Int64 {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix("€") { text.removeLast(); text = text.trimmingCharacters(in: .whitespaces) }
        let parts = text.replacingOccurrences(of: ",", with: ".")
            .split(separator: ".", omittingEmptySubsequences: false)
        func digits(_ part: Substring) -> Bool {
            !part.isEmpty && part.utf8.allSatisfy { (48...57).contains($0) }
        }
        guard (1...2).contains(parts.count), digits(parts[0]),
              parts.count == 1 || (digits(parts[1]) && parts[1].count <= 2),
              let whole = Int64(parts[0]), whole <= maximum / 100 else { throw LedgerError.invalidAmount }
        let fraction = parts.count == 2 ? Int64(parts[1])! * (parts[1].count == 1 ? 10 : 1) : 0
        let amount = whole * 100 + fraction
        guard amount <= maximum, amount > 0 || (allowZero && amount == 0) else { throw LedgerError.invalidAmount }
        return amount
    }

    static func format(_ amount: Int64, locale: Locale = .current) -> String {
        (Decimal(amount) / 100).formatted(.currency(code: "EUR").locale(locale))
    }

    static func input(_ amount: Int64, locale: Locale = .current) -> String {
        let separator = locale.decimalSeparator ?? "."
        return "\(amount / 100)\(separator)\(String(format: "%02lld", amount % 100))"
    }
}

struct ExpenseDay: Hashable, Codable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year!
        month = components.month!
        day = components.day!
    }

    init(iso: String) throws {
        let fields = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard iso.count == 10, fields.count == 3,
              fields[0].count == 4, fields[1].count == 2, fields[2].count == 2,
              fields.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let year = Int(fields[0]), let month = Int(fields[1]), let day = Int(fields[2]),
              (1900...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else {
            throw LedgerError.invalidDate
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else { throw LedgerError.invalidDate }
        self.year = year; self.month = month; self.day = day
    }

    var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
    var date: Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.iso < rhs.iso }
}

struct BudgetMonth: Hashable, Sendable {
    var year: Int
    var month: Int

    init(year: Int, month: Int) { self.year = year; self.month = month }
    init(date: Date) {
        let day = ExpenseDay(date: date)
        year = day.year; month = day.month
    }
    var title: String {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: 15))!
        return date.formatted(.dateTime.month(.wide).year())
    }
    func moved(by offset: Int) -> Self {
        let index = year * 12 + month - 1 + offset
        return Self(year: index / 12, month: index % 12 + 1)
    }
}

struct CategoryValue: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
}

struct YearBudgetValue: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let categoryID: UUID
    let year: Int
    var amount: Int64
}

struct ExpenseValue: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var categoryID: UUID
    var amount: Int64
    var personalShare: Int64
    var description: String
    var day: ExpenseDay
    let createdAt: Date
}

struct PendingChangeValue: Identifiable, Equatable, Sendable {
    let id: UUID
    let entityID: UUID
    let entity: String
    let action: String
    let sequence: Int64
    let payload: Data
}

struct CategoryBudget: Identifiable, Sendable {
    let category: CategoryValue
    let annual: Int64?
    let allocation: Int64
    let carryover: Int64
    let spent: Int64
    let remaining: Int64
    var id: UUID { category.id }
    var available: Int64 { allocation + carryover }
}

enum BudgetCalculator {
    static func cumulativeAllocation(annual: Int64, through month: Int) -> Int64 {
        precondition(annual >= 0 && (0...12).contains(month))
        return annual / 12 * Int64(month) + min(annual % 12, Int64(month))
    }

    static func category(
        _ category: CategoryValue, month: BudgetMonth, annual: Int64?, expenses: [ExpenseValue]
    ) -> CategoryBudget {
        let relevant = expenses.filter { $0.categoryID == category.id && $0.day.year == month.year }
        let before = relevant.filter { $0.day.month < month.month }.reduce(Int64(0)) { $0 + $1.personalShare }
        let spent = relevant.filter { $0.day.month == month.month }.reduce(Int64(0)) { $0 + $1.personalShare }
        let priorAllocation = cumulativeAllocation(annual: annual ?? 0, through: month.month - 1)
        let allocation = cumulativeAllocation(annual: annual ?? 0, through: month.month) - priorAllocation
        let carryover = priorAllocation - before
        return CategoryBudget(category: category, annual: annual, allocation: allocation,
                              carryover: carryover, spent: spent, remaining: allocation + carryover - spent)
    }
}
