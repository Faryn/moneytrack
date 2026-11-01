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
    private(set) var issues: [SyncIssue] = []
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
        issues = try context.fetch(FetchDescriptor<LedgerSchemaV2.OperationState>()).compactMap {
            try $0.issueData.map { try JSONDecoder().decode(SyncIssue.self, from: $0) }
        }
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
        guard name.count <= 100 else { throw LedgerError.categoryTooLong }
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
        guard description.count <= 500 else { throw LedgerError.descriptionTooLong }
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
        let prior = try context.fetch(FetchDescriptor<PendingChangeRecord>()).contains {
            $0.entityKind == entity && $0.entityID == id
        }
        let base = prior ? nil : try remoteState(entity, id)?.revision ?? 0
        context.insert(LedgerSchemaV2.OperationState(id: value.id, baseRevision: base))
        context.insert(PendingChangeRecord(value))
        return value
    }
}

// Synchronization never creates a second local domain mutation or running balance.
extension LedgerStore {
    var cursor: String? { get throws { try syncState().cursor } }
    var hasImportedLocal: Bool { get throws { try syncState().importedLocal } }

    func prepareNextOperation() throws -> (UUID, Data)? {
        guard let pending = pendingChanges.first else { return nil }
        let state = try operationState(pending.id) ?? LedgerSchemaV2.OperationState(id: pending.id, baseRevision: 0)
        if state.issueData != nil { return nil }
        if let data = state.wireData { return (pending.id, data) }
        let payload = try JSONDecoder().decode(JSONValue.self, from: pending.payload)
        let wire = WireOperation(operationID: pending.id, entity: pending.entity, entityID: pending.entityID,
                                 action: pending.action, expectedRevision: state.baseRevision ?? 0, payload: payload)
        let data = try JSONEncoder().encode(wire)
        try syncCommit {
            if try operationState(pending.id) == nil { context.insert(state) }
            state.wireData = data
        }
        return (pending.id, data)
    }

    func acknowledge(_ id: UUID, record: RemoteRecord) throws {
        guard let pending = pendingChanges.first(where: { $0.id == id }),
              pending.entity == record.entity, pending.entityID == record.entityID else { throw ConnectionError.invalidData }
        try syncCommit {
            try removeOperation(id)
            try remember(record)
            let remaining = try context.fetch(FetchDescriptor<PendingChangeRecord>())
                .filter { $0.entityKind == pending.entity && $0.entityID == pending.entityID }.sorted { $0.sequence < $1.sequence }
            if let next = remaining.first {
                let state = try operationState(next.id) ?? LedgerSchemaV2.OperationState(id: next.id, baseRevision: nil)
                if try operationState(next.id) == nil { context.insert(state) }
                // Depend on our acknowledged revision, never silently on someone else's later edit.
                if state.baseRevision == nil { state.baseRevision = record.revision }
            } else {
                let latest = try remoteState(record.entity, record.entityID).flatMap { try JSONDecoder().decode(RemoteRecord.self, from: $0.data) }
                try applyRemote(latest ?? record)
            }
        }
        try reloadAll()
    }

    func restartPull() throws { try syncCommit { try syncState().cursor = nil } }

    func receive(_ page: ChangePage) throws {
        try syncCommit {
            for record in page.changes {
                try remember(record)
                if record.entity == "year_budget" {
                    let remote = try record.payload.decoded(YearBudgetValue.self)
                    let pendingRecords = try context.fetch(FetchDescriptor<PendingChangeRecord>())
                    let budgetRecords = try context.fetch(FetchDescriptor<YearBudgetRecord>())
                    if let pending = pendingRecords.sorted(by: { $0.sequence < $1.sequence }).first(where: { pending in
                        pending.entityKind == "year_budget" && pending.entityID != record.entityID && budgetRecords.contains {
                            $0.id == pending.entityID && $0.categoryID == remote.categoryID && $0.year == remote.year
                        }
                    }) {
                        let issue = SyncIssue(id: pending.id, entity: "year_budget", entityID: pending.entityID,
                            message: "Another device created a budget for this category and year. Choose which amount to keep.", current: record)
                        let state = try operationState(pending.id) ?? LedgerSchemaV2.OperationState(id: pending.id, baseRevision: 0)
                        if try operationState(pending.id) == nil { context.insert(state) }
                        state.issueData = try JSONEncoder().encode(issue)
                        continue
                    }
                }
                let localPending = try context.fetch(FetchDescriptor<PendingChangeRecord>()).contains {
                    $0.entityKind == record.entity && $0.entityID == record.entityID
                }
                if !localPending, let latest = try remoteState(record.entity, record.entityID) {
                    try applyRemote(JSONDecoder().decode(RemoteRecord.self, from: latest.data))
                }
            }
            try syncState().cursor = page.cursor
        }
        try reloadAll()
    }

    func recordIssue(_ id: UUID, message: String, current: RemoteRecord?) throws {
        guard let pending = pendingChanges.first(where: { $0.id == id }) else { throw ConnectionError.invalidData }
        let issue = SyncIssue(id: id, entity: pending.entity, entityID: pending.entityID, message: message, current: current)
        try syncCommit {
            if let current { try remember(current) }
            let state = try operationState(id) ?? LedgerSchemaV2.OperationState(id: id, baseRevision: 0)
            if try operationState(id) == nil { context.insert(state) }
            state.issueData = try JSONEncoder().encode(issue)
        }
        try reloadAll()
    }

    func resolve(_ issue: SyncIssue, keepLocal: Bool) throws {
        guard let first = pendingChanges.first(where: { $0.id == issue.id }) else { throw ConnectionError.invalidData }
        let selected = pendingChanges.filter { $0.entity == issue.entity && $0.entityID == issue.entityID }
        let originalBase = try operationState(first.id)?.baseRevision ?? 0
        try syncCommit {
            let latest = try localPayload(entity: issue.entity, id: issue.entityID)
            for pending in selected { try removeOperation(pending.id) }
            if !keepLocal {
                guard let current = issue.current else { throw ConnectionError.invalidData }
                let cached = try remoteState(current.entity, current.entityID)
                    .flatMap { try JSONDecoder().decode(RemoteRecord.self, from: $0.data) }
                if current.entityID != issue.entityID && issue.entity == "year_budget" {
                    if let old = try context.fetch(FetchDescriptor<YearBudgetRecord>()).first(where: { $0.id == issue.entityID }) { context.delete(old) }
                }
                try applyRemote(cached ?? current)
            } else if let current = issue.current, current.entityID != issue.entityID && issue.entity == "year_budget" {
                let old = try latest.1.decoded(YearBudgetValue.self)
                let value = YearBudgetValue(id: current.entityID, categoryID: old.categoryID, year: old.year, amount: old.amount)
                if let oldRecord = try context.fetch(FetchDescriptor<YearBudgetRecord>()).first(where: { $0.id == old.id }) { context.delete(oldRecord) }
                if let saved = try context.fetch(FetchDescriptor<YearBudgetRecord>()).first(where: { $0.id == value.id }) { saved.amount = value.amount }
                else { context.insert(YearBudgetRecord(value)) }
                let pending = try enqueue(entity: "year_budget", id: value.id, action: "upsert", payload: value)
                try replaceSequence(pending.id, with: first.sequence, base: current.revision)
            } else if issue.current?.deleted == true && issue.entity == "expense" && latest.0 == "upsert" {
                let old = try latest.1.decoded(ExpenseValue.self)
                let value = ExpenseValue(id: UUID(), categoryID: old.categoryID, amount: old.amount,
                    personalShare: old.personalShare, description: old.description, day: old.day, createdAt: old.createdAt)
                if let current = issue.current { try applyRemote(current) }
                context.insert(ExpenseRecord(value))
                let pending = try enqueue(entity: "expense", id: value.id, action: "upsert", payload: value)
                try replaceSequence(pending.id, with: first.sequence, base: 0)
            } else if issue.current?.deleted == true && latest.0 == "delete" {
                if let current = issue.current { try applyRemote(current) }
            } else {
                let pending = try enqueue(entity: issue.entity, id: issue.entityID, action: latest.0, payload: latest.1)
                let base = issue.current?.revision ?? originalBase
                try replaceSequence(pending.id, with: first.sequence, base: base)
            }
        }
        try reloadAll()
        saveCount += 1
    }

    // A deliberate, one-time copy into an empty account. The original store stays intact.
    func importLocal(_ source: LedgerStore) throws {
        if try syncState().importedLocal { return }
        guard categories.isEmpty, budgets.isEmpty, expenses.isEmpty, pendingChanges.isEmpty else { throw ConnectionError.notEmpty }
        var categoryIDs: [UUID: UUID] = [:]
        try syncCommit {
            var offset = 0
            for original in source.categories {
                let value = CategoryValue(id: UUID(), name: original.name)
                categoryIDs[original.id] = value.id
                context.insert(CategoryRecord(value))
                _ = try enqueue(entity: "category", id: value.id, action: "upsert", payload: value, offset: offset)
                offset += 1
            }
            for original in source.budgets {
                guard let category = categoryIDs[original.categoryID] else { throw ConnectionError.invalidData }
                let value = YearBudgetValue(id: UUID(), categoryID: category, year: original.year, amount: original.amount)
                context.insert(YearBudgetRecord(value))
                _ = try enqueue(entity: "year_budget", id: value.id, action: "upsert", payload: value, offset: offset)
                offset += 1
            }
            for original in source.expenses {
                guard let category = categoryIDs[original.categoryID] else { throw ConnectionError.invalidData }
                let value = ExpenseValue(id: UUID(), categoryID: category, amount: original.amount, personalShare: original.personalShare,
                    description: original.description, day: original.day, createdAt: original.createdAt)
                context.insert(ExpenseRecord(value))
                _ = try enqueue(entity: "expense", id: value.id, action: "upsert", payload: value, offset: offset)
                offset += 1
            }
            try syncState().importedLocal = true
        }
        try reloadAll()
    }

    func localPayload(entity: String, id: UUID) throws -> (String, JSONValue) {
        switch entity {
        case "category":
            guard let value = categories.first(where: { $0.id == id }) else { throw ConnectionError.invalidData }
            return ("upsert", try .value(value))
        case "year_budget":
            guard let value = budgets.first(where: { $0.id == id }) else { throw ConnectionError.invalidData }
            return ("upsert", try .value(value))
        case "expense":
            guard let value = try context.fetch(FetchDescriptor<ExpenseRecord>()).first(where: { $0.id == id }) else { throw ConnectionError.invalidData }
            if let deleted = value.deletedAt {
                return ("delete", .object(["id": .string(id.uuidString), "deletedAt": .string(deleted.ISO8601Format())]))
            }
            return ("upsert", try .value(value.value()))
        default: throw ConnectionError.invalidData
        }
    }

    private func replaceSequence(_ id: UUID, with sequence: Int64, base: Int64) throws {
        try context.fetch(FetchDescriptor<PendingChangeRecord>()).first(where: { $0.id == id })?.sequence = sequence
        try operationState(id)?.baseRevision = base
    }
    private func removeOperation(_ id: UUID) throws {
        if let value = try context.fetch(FetchDescriptor<PendingChangeRecord>()).first(where: { $0.id == id }) { context.delete(value) }
        if let value = try operationState(id) { context.delete(value) }
    }
    private func operationState(_ id: UUID) throws -> LedgerSchemaV2.OperationState? {
        try context.fetch(FetchDescriptor<LedgerSchemaV2.OperationState>()).first { $0.id == id }
    }
    private func remoteState(_ entity: String, _ id: UUID) throws -> LedgerSchemaV2.RemoteState? {
        let key = RemoteRecord.key(entity, id)
        return try context.fetch(FetchDescriptor<LedgerSchemaV2.RemoteState>()).first { $0.key == key }
    }
    private func syncState() throws -> LedgerSchemaV2.SyncState {
        if let state = try context.fetch(FetchDescriptor<LedgerSchemaV2.SyncState>()).first { return state }
        let state = LedgerSchemaV2.SyncState(); context.insert(state); return state
    }
    private func remember(_ record: RemoteRecord) throws {
        guard record.revision > 0 else { throw ConnectionError.invalidData }
        let data = try JSONEncoder().encode(record)
        if let saved = try remoteState(record.entity, record.entityID) {
            if record.revision >= saved.revision { saved.revision = record.revision; saved.data = data }
        } else { context.insert(LedgerSchemaV2.RemoteState(key: record.key, revision: record.revision, data: data)) }
    }
    private func applyRemote(_ record: RemoteRecord) throws {
        switch record.entity {
        case "category":
            let value = try record.payload.decoded(CategoryValue.self)
            guard value.id == record.entityID, !record.deleted, !value.name.isEmpty else { throw ConnectionError.invalidData }
            if let saved = try context.fetch(FetchDescriptor<CategoryRecord>()).first(where: { $0.id == value.id }) { saved.name = value.name }
            else { context.insert(CategoryRecord(value)) }
        case "year_budget":
            let value = try record.payload.decoded(YearBudgetValue.self)
            guard value.id == record.entityID, !record.deleted, (0...Money.maximum).contains(value.amount),
                  (1900...9999).contains(value.year) else { throw ConnectionError.invalidData }
            if let saved = try context.fetch(FetchDescriptor<YearBudgetRecord>()).first(where: { $0.id == value.id }) { saved.amount = value.amount }
            else { context.insert(YearBudgetRecord(value)) }
        case "expense":
            let value = try record.payload.decoded(ExpenseValue.self)
            guard value.id == record.entityID, (1...Money.maximum).contains(value.amount), value.personalShare == value.amount else { throw ConnectionError.invalidData }
            guard (1900...9999).contains(value.day.year) else { throw ConnectionError.invalidData }
            _ = try ExpenseDay(iso: value.day.iso)
            let saved = try context.fetch(FetchDescriptor<ExpenseRecord>()).first(where: { $0.id == value.id }) ?? ExpenseRecord(value)
            if saved.modelContext == nil { context.insert(saved) }
            saved.categoryID = value.categoryID; saved.amount = value.amount; saved.personalShare = value.personalShare
            saved.descriptionText = value.description; saved.calendarDay = value.day.iso; saved.createdAt = value.createdAt
            saved.deletedAt = record.deleted ? .now : nil
        default: throw ConnectionError.invalidData
        }
    }
    private func syncCommit(_ changes: () throws -> Void) throws {
        do { try changes(); try context.save() }
        catch { context.rollback(); throw error }
    }
    private func reloadAll() throws {
        categories = try context.fetch(FetchDescriptor<CategoryRecord>()).map(\.value)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        budgets = try context.fetch(FetchDescriptor<YearBudgetRecord>()).map(\.value)
        expenses = try context.fetch(FetchDescriptor<ExpenseRecord>()).filter { $0.deletedAt == nil }.map { try $0.value() }
            .sorted { $0.day == $1.day ? $0.createdAt > $1.createdAt : $0.day > $1.day }
        pendingChanges = try context.fetch(FetchDescriptor<PendingChangeRecord>()).map(\.value).sorted { $0.sequence < $1.sequence }
        issues = try context.fetch(FetchDescriptor<LedgerSchemaV2.OperationState>()).compactMap {
            try $0.issueData.map { try JSONDecoder().decode(SyncIssue.self, from: $0) }
        }
    }
}
