import Foundation

enum PersonalSplit: String, Codable, CaseIterable, Sendable {
    case all, half, none
    var title: String {
        switch self { case .all: "All"; case .half: "Half"; case .none: "None" }
    }
}
struct SharedAmounts: Equatable, Sendable {
    let personalShare: Int64
    let otherShare: Int64
    // Positive: the other person owes you. Negative: you owe the other person.
    let balance: Int64
}
enum SharedMath {
    static func calculate(amount: Int64, split: PersonalSplit, paidByUser: Bool) throws -> SharedAmounts {
        guard (1...Money.maximum).contains(amount) else { throw LedgerError.invalidAmount }
        let own: Int64
        switch split {
        case .all: own = amount
        case .none: own = 0
        case .half: own = amount / 2 + (paidByUser ? amount % 2 : 0)
        }
        return SharedAmounts(personalShare: own, otherShare: amount - own,
                             balance: (paidByUser ? amount : 0) - own)
    }
}

// Calculation inputs relative to the viewer, not a persisted/wire repayment record.
// Shared storage will identify the actual payer and recipient by account ID.
struct RepaymentAmounts: Sendable {
    let amount: Int64
    let paidByUser: Bool
}

struct SharedBalanceSummary: Equatable, Sendable {
    let personalSpending: Int64
    let otherSpending: Int64
    let expenseBalance: Int64
    let balance: Int64
}

enum SharedCalculationError: LocalizedError {
    case totalOverflow
    var errorDescription: String? { "The combined shared amount is too large to display." }
}

extension SharedMath {
    static func summarize(expenses: [SharedAmounts], repayments: [RepaymentAmounts]) throws -> SharedBalanceSummary {
        // Wider accumulation keeps cancellation order-independent without rounding or wrapping.
        var personal = Int128(0), other = Int128(0), expenseBalance = Int128(0)
        for expense in expenses {
            personal += Int128(expense.personalShare)
            other += Int128(expense.otherShare)
            expenseBalance += Int128(expense.balance)
        }
        var balance = expenseBalance
        for repayment in repayments {
            guard (1...Money.maximum).contains(repayment.amount) else { throw LedgerError.invalidAmount }
            // Paying reduces what you owe; receiving reduces what the other person owes you.
            balance += repayment.paidByUser ? Int128(repayment.amount) : -Int128(repayment.amount)
        }
        guard let personal = Int64(exactly: personal), let other = Int64(exactly: other),
              let expenseBalance = Int64(exactly: expenseBalance), let balance = Int64(exactly: balance) else {
            throw SharedCalculationError.totalOverflow
        }
        return SharedBalanceSummary(personalSpending: personal, otherSpending: other,
                                    expenseBalance: expenseBalance, balance: balance)
    }
}
