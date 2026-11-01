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
