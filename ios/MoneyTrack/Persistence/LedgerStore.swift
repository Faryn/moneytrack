import Foundation
import Observation
import SwiftData

@MainActor @Observable
final class LedgerStore {
    private let context: ModelContext
    private(set) var categories: [CategoryValue]
    private(set) var budgets: [YearBudgetValue]
    private(set) var expenses: [ExpenseValue]
    private(set) var pendingChanges: [PendingChangeValue]
    private(set) var saveCount = 0
    private let fixedToday: Date?
    var today: Date { fixedToday ?? .now }

    init(container: ModelContainer, today: Date? = nil) throws {
        context = ModelContext(container)
        context.autosaveEnabled = false
        fixedToday = today
        categories = try context.fetch(FetchDescriptor<CategoryRecord>()).map(\.value)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        budgets = try context.fetch(FetchDescriptor<YearBudgetRecord>()).map(\.value)
        expenses = try context.fetch(FetchDescriptor<ExpenseRecord>()).filter { $0.deletedAt == nil }
            .map { try $0.value() }
            .sorted { $0.day == $1.day ? $0.createdAt > $1.createdAt : $0.day > $1.day }
        pendingChanges = try context.fetch(FetchDescriptor<PendingChangeRecord>()).map(\.value)
            .sorted { $0.sequence < $1.sequence }
    }

    func budget(for categoryID: UUID, year: Int) -> YearBudgetValue? {
        budgets.first { $0.categoryID == categoryID && $0.year == year }
    }

    func overview(month: BudgetMonth) -> [CategoryBudget] {
        categories.map {
            BudgetCalculator.category($0, month: month, annual: budget(for: $0.id, year: month.year)?.amount, expenses: expenses)
        }
    }

    func suggestedCategory(description: String) -> UUID? {
        let normalized = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return expenses.first { $0.description.compare(normalized, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }?.categoryID
    }

    @discardableResult
    func saveCategory(id: UUID? = nil, name: String, year: Int, annualAmount: Int64?) throws -> UUID {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LedgerError.emptyCategory }
        guard (1900...9999).contains(year),
              annualAmount == nil || (0...Money.maximum).contains(annualAmount!) else { throw LedgerError.invalidAmount }
        let id = id ?? UUID()
        guard !categories.contains(where: { $0.id != id && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame })
        else { throw LedgerError.duplicateCategory }
        let category = CategoryValue(id: id, name: name)
        let annual = annualAmount.map { YearBudgetValue(id: budget(for: id, year: year)?.id ?? UUID(), categoryID: id, year: year, amount: $0) }
        var changes: [PendingChangeValue] = []
        try commit {
            if let record = try context.fetch(FetchDescriptor<CategoryRecord>()).first(where: { $0.id == id }) {
                record.name = name
            } else { context.insert(CategoryRecord(category)) }
            changes.append(try enqueue(entity: "category", id: id, action: "upsert", payload: category, offset: changes.count))
            if let annual {
                if let record = try context.fetch(FetchDescriptor<YearBudgetRecord>()).first(where: { $0.id == annual.id }) {
                    record.amount = annual.amount
                } else { context.insert(YearBudgetRecord(annual)) }
                changes.append(try enqueue(entity: "year_budget", id: annual.id, action: "upsert", payload: annual, offset: changes.count))
            }
        }
        categories.removeAll { $0.id == id }; categories.append(category)
        categories.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if let annual { budgets.removeAll { $0.id == annual.id }; budgets.append(annual) }
        pendingChanges.append(contentsOf: changes)
        return id
    }

    @discardableResult
    func saveExpense(id: UUID? = nil, amount: Int64, description: String, categoryID: UUID, day: ExpenseDay) throws -> UUID {
        guard (1...Money.maximum).contains(amount) else { throw LedgerError.invalidAmount }
        guard categories.contains(where: { $0.id == categoryID }) else { throw LedgerError.missingCategory }
        let existing = id.flatMap { identifier in expenses.first { $0.id == identifier } }
        if id != nil && existing == nil { throw LedgerError.missingExpense }
        guard existing == nil || existing!.personalShare == existing!.amount else { throw LedgerError.sharedEditingUnavailable }
        let value = ExpenseValue(id: id ?? UUID(), categoryID: categoryID, amount: amount, personalShare: amount,
                                 description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                                 day: day, createdAt: existing?.createdAt ?? .now)
        var pending: PendingChangeValue!
        try commit {
            if let record = try context.fetch(FetchDescriptor<ExpenseRecord>()).first(where: { $0.id == value.id }) {
                guard record.deletedAt == nil else { throw LedgerError.missingExpense }
                record.amount = amount; record.personalShare = amount; record.categoryID = categoryID
                record.descriptionText = value.description; record.calendarDay = day.iso
            } else { context.insert(ExpenseRecord(value)) }
            pending = try enqueue(entity: "expense", id: value.id, action: "upsert", payload: value)
        }
        expenses.removeAll { $0.id == value.id }; expenses.append(value)
        expenses.sort { $0.day == $1.day ? $0.createdAt > $1.createdAt : $0.day > $1.day }
        pendingChanges.append(pending)
        return value.id
    }

    func deleteExpense(_ id: UUID) throws {
        guard let value = expenses.first(where: { $0.id == id }) else { throw LedgerError.missingExpense }
        guard value.personalShare == value.amount else { throw LedgerError.sharedEditingUnavailable }
        struct Deletion: Codable { let id: UUID; let deletedAt: Date }
        var pending: PendingChangeValue!
        try commit {
            guard let record = try context.fetch(FetchDescriptor<ExpenseRecord>()).first(where: { $0.id == id && $0.deletedAt == nil })
            else { throw LedgerError.missingExpense }
            let now = Date.now
            record.deletedAt = now
            pending = try enqueue(entity: "expense", id: id, action: "delete", payload: Deletion(id: id, deletedAt: now))
        }
        expenses.removeAll { $0.id == id }
        pendingChanges.append(pending)
    }

    private func commit(_ changes: () throws -> Void) throws {
        do {
            try changes()
            // One explicit save commits domain data and outbox entries together.
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        saveCount += 1
    }

    private func enqueue<T: Encodable>(
        entity: String, id: UUID, action: String, payload: T, offset: Int = 0
    ) throws -> PendingChangeValue {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let value = PendingChangeValue(id: UUID(), entityID: id, entity: entity, action: action,
                                       sequence: (pendingChanges.last?.sequence ?? 0) + Int64(offset) + 1,
                                       payload: try encoder.encode(payload))
        context.insert(PendingChangeRecord(value))
        return value
    }
}
