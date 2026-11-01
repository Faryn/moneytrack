import Foundation

struct SharingConnection: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let otherID: UUID
    let otherName: String
}
struct SharedHistory: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let actorName: String
    let action: String
    let at: Date
    let changes: JSONValue
}
struct SharedExpenseValue: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let viewerID: UUID
    let creatorID: UUID
    var recipientID: UUID?
    let creatorName: String
    var recipientName: String?
    let recipientEmail: String?
    var status: String
    var amount: Int64
    var description: String
    var day: ExpenseDay
    let createdAt: Date
    var paidByCreator: Bool
    var creatorSplit: PersonalSplit
    var categoryID: UUID
    var assignmentRevision: Int64
    var revision: Int64
    var connection: SharingConnection?
    var bootstrapRecords: [RemoteRecord]
    var history: [SharedHistory]
    var deleted: Bool
    var isCreator: Bool { viewerID == creatorID }
    var otherName: String { isCreator ? recipientName ?? recipientEmail ?? "Other person" : creatorName }
    var ownSplit: PersonalSplit { isCreator ? creatorSplit : creatorSplit.reversed }
    var paidByUser: Bool { isCreator == paidByCreator }
    var amounts: SharedAmounts { get throws { try SharedMath.calculate(amount: amount, split: ownSplit, paidByUser: paidByUser) } }
    var expense: ExpenseValue { get throws {
        .init(id: id, categoryID: categoryID, amount: amount, personalShare: try amounts.personalShare,
              description: description, day: day, createdAt: createdAt)
    } }
}
struct SharingInvitation: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let senderName: String
    let email: String
    let createdAt: Date
}
struct SharedAssignment: Codable, Sendable { let id: UUID; let categoryID: UUID }
struct RepaymentValue: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let viewerID: UUID
    let connectionID: UUID
    let payerID: UUID
    let recipientID: UUID
    let amount: Int64
    let day: ExpenseDay
    let createdAt: Date
    let actorName: String
    let connection: SharingConnection
    var paidByUser: Bool { payerID == viewerID }
}
extension PersonalSplit {
    var reversed: Self { switch self { case .all: .none; case .none: .all; case .half: .half } }
}
