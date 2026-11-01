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
    private(set) var annualPlans: [AnnualBudgetPlan] = []
    private(set) var sharedExpenses: [SharedExpenseValue] = []
    private(set) var invitations: [SharingInvitation] = []
    private(set) var repayments: [RepaymentValue] = []
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
        try reloadAll()
    }

    func budget(for categoryID: UUID, year: Int) -> YearBudgetValue? {
        if let plan = annualPlan(year: year) {
            return plan.allocations.first { $0.categoryID == categoryID }.map { YearBudgetValue(id: categoryID, categoryID: categoryID, year: year, amount: $0.amount) }
        }
        return budgets.first { $0.categoryID == categoryID && $0.year == year }
    }

    func overview(month: BudgetMonth) -> [CategoryBudget] {
        if let plan = annualPlan(year: month.year) { return (try? AnnualBudgetCalculator.overview(plan, month: month, categories: categories, expenses: expenses).categories) ?? [] }
        return categories.map {
            BudgetCalculator.category($0, month: month, annual: budget(for: $0.id, year: month.year)?.amount, expenses: expenses)
        }
    }

    func suggestedCategory(description: String) -> UUID? {
        let normalized = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return expenses.first { $0.description.compare(normalized, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }?.categoryID
    }

    @discardableResult
    func saveCategory(id: UUID? = nil, name: String, year: Int, annualAmount: Int64?, planSnapshot: AnnualBudgetPlan? = nil, expectedPlanRevision: Int64? = nil) throws -> UUID {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LedgerError.emptyCategory }
        guard name.count <= 100 else { throw LedgerError.categoryTooLong }
        guard (1900...9999).contains(year),
              annualAmount == nil || (0...Money.maximum).contains(annualAmount!) else { throw LedgerError.invalidAmount }
        let id = id ?? UUID()
        guard !categories.contains(where: { $0.id != id && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame })
        else { throw LedgerError.duplicateCategory }
        let category = CategoryValue(id: id, name: name)
        let existingPlan = planSnapshot ?? annualPlan(year: year)
        if let planSnapshot, let current = annualPlan(year: year), current.id != planSnapshot.id {
            throw ConnectionError.rejected("This year's plan changed. Reopen it before assigning money.")
        }
        let allocationBase = try effectivePlanRevision(snapshot: planSnapshot, expected: expectedPlanRevision)
        var updatedPlan = existingPlan
        if let amount = annualAmount, var plan = updatedPlan {
            guard id != plan.freeCategoryID else { throw ConnectionError.rejected("The default category uses guilt-free spending.") }
            plan.allocations.removeAll { $0.categoryID == id }
            if amount > 0 { plan.allocations.append(CategoryAllocation(categoryID: id, amount: amount)) }
            plan.allocations.sort { $0.categoryID.uuidString < $1.categoryID.uuidString }
            try plan.validate(); updatedPlan = plan
        }
        let annual = (existingPlan == nil ? annualAmount : nil).map { YearBudgetValue(id: budget(for: id, year: year)?.id ?? UUID(), categoryID: id, year: year, amount: $0) }
        var changes: [PendingChangeValue] = []
        try commit {
            if let record = try context.fetch(FetchDescriptor<CategoryRecord>()).first(where: { $0.id == id }) {
                record.name = name
            } else { context.insert(CategoryRecord(category)) }
            changes.append(try enqueue(entity: "category", id: id, action: "upsert", payload: category, offset: changes.count))
            if let updatedPlan, updatedPlan != existingPlan {
                try putAnnualPlan(updatedPlan)
                let prior = pendingChanges.contains { $0.entity == "budget_plan" && $0.entityID == updatedPlan.id }
                let change = try enqueue(entity: "budget_plan", id: updatedPlan.id, action: "upsert", payload: updatedPlan, offset: changes.count)
                if let allocationBase, !prior { try operationState(change.id)?.baseRevision = allocationBase }
                changes.append(change)
            }
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
        if updatedPlan != existingPlan { try reloadAll() }
        return id
    }

    @discardableResult
    func saveExpense(id: UUID? = nil, amount: Int64, description: String, categoryID: UUID?, day: ExpenseDay, expectedRevision: Int64? = nil) throws -> UUID {
        if let id, let shared = sharedExpenses.first(where: { $0.id == id }) {
            guard let categoryID else { throw LedgerError.missingCategory }
            if expectedRevision != nil { throw LedgerError.sharedEditingUnavailable }
            try editSharedExpense(shared, amount: amount, description: description, categoryID: categoryID,
                                  day: day, paidByUser: shared.paidByUser, ownSplit: shared.ownSplit)
            return id
        }
        guard (1...Money.maximum).contains(amount) else { throw LedgerError.invalidAmount }
        guard description.count <= 500 else { throw LedgerError.descriptionTooLong }
        let fallback = categoryID == nil ? defaultSpendingCategory(year: day.year) : nil
        let categoryID = categoryID ?? fallback!.id
        guard categories.contains(where: { $0.id == categoryID }) || fallback != nil else { throw LedgerError.missingCategory }
        let existing = id.flatMap { identifier in expenses.first { $0.id == identifier } }
        if id != nil && existing == nil { throw LedgerError.missingExpense }
        guard existing == nil || existing!.personalShare == existing!.amount else { throw LedgerError.sharedEditingUnavailable }
        let value = ExpenseValue(id: id ?? UUID(), categoryID: categoryID, amount: amount, personalShare: amount,
                                 description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                                 day: day, createdAt: existing?.createdAt ?? .now)
        var pending: PendingChangeValue!
        let priorPending = pendingChanges.contains { $0.entity == "expense" && $0.entityID == value.id }
        try commit {
            var offset = 0
            if let fallback, !categories.contains(where: { $0.id == fallback.id }) {
                context.insert(CategoryRecord(fallback))
                _ = try enqueue(entity: "category", id: fallback.id, action: "upsert", payload: fallback)
                offset = 1
            }
            if let record = try context.fetch(FetchDescriptor<ExpenseRecord>()).first(where: { $0.id == value.id }) {
                guard record.deletedAt == nil else { throw LedgerError.missingExpense }
                record.amount = amount; record.personalShare = amount; record.categoryID = categoryID
                record.descriptionText = value.description; record.calendarDay = day.iso
            } else { context.insert(ExpenseRecord(value)) }
            pending = try enqueue(entity: "expense", id: value.id, action: "upsert", payload: value, offset: offset)
            if let expectedRevision, !priorPending { try operationState(pending.id)?.baseRevision = expectedRevision }
        }
        expenses.removeAll { $0.id == value.id }; expenses.append(value)
        expenses.sort { $0.day == $1.day ? $0.createdAt > $1.createdAt : $0.day > $1.day }
        if fallback != nil { try reloadAll() } else { pendingChanges.append(pending) }
        return value.id
    }

    func deleteExpense(_ id: UUID) throws {
        if sharedExpenses.contains(where: { $0.id == id }) { try deleteSharedExpense(id); return }
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
            ($0.entityKind == entity || (entity == "shared_assignment" && $0.entityKind == "shared_expense")) && $0.entityID == id
        }
        let base = prior ? nil : try remoteState(entity, id)?.revision ?? 0
        context.insert(LedgerSchemaV2.OperationState(id: value.id, baseRevision: base))
        context.insert(PendingChangeRecord(value))
        return value
    }
}

// Synchronization never creates a second local domain mutation or running balance.
extension LedgerStore {
    func recordRevision(_ entity: String, _ id: UUID) throws -> Int64 { try remoteState(entity, id)?.revision ?? 0 }
    var cursor: String? { get throws { try syncState().cursor } }
    var hasImportedLocal: Bool { get throws { try syncState().importedLocal } }

    func prepareNextOperation() throws -> (UUID, Data)? {
        guard let pending = pendingChanges.first else { return nil }
        let state = try operationState(pending.id) ?? LedgerSchemaV2.OperationState(id: pending.id, baseRevision: 0)
        if state.issueData != nil { return nil }
        if let data = state.wireData { return (pending.id, data) }
        var payload = try JSONDecoder().decode(JSONValue.self, from: pending.payload)
        if pending.entity == "shared_expense", case .object(var fields) = payload,
           fields["command"] == .string("share") {
            if fields["sourceRevision"] == nil {
                guard let row = try context.fetch(FetchDescriptor<LedgerSchemaV3.SharedRecord>()).first(where: { $0.key == RemoteRecord.key("source_ack", pending.entityID) }),
                      case .object(let ack) = try JSONDecoder().decode(JSONValue.self, from: row.data),
                      ack["operationID"] == fields["sourceOperationID"], let revision = ack["revision"] else { throw ConnectionError.invalidData }
                fields["sourceRevision"] = revision
            }
            fields.removeValue(forKey: "sourceOperationID")
            payload = .object(fields)
        }
        let expectedRevision: Int64
        if let base = state.baseRevision { expectedRevision = base }
        else { expectedRevision = try remoteState(pending.entity, pending.entityID)?.revision ?? 0 }
        let wire = WireOperation(operationID: pending.id, entity: pending.entity, entityID: pending.entityID,
                                 action: pending.action, expectedRevision: expectedRevision, payload: payload)
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
            if pending.entity == "expense" {
                try putShared("source_ack", pending.entityID, payload: .object(["operationID": .string(id.uuidString), "revision": .integer(record.revision)]), deleted: false)
            }
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
                if record.entity == "budget_plan" {
                    let value = try record.payload.decoded(AnnualBudgetPlan.self)
                    if let old = annualPlans.first(where: { $0.year == value.year && $0.id != value.id }),
                       let pending = pendingChanges.first(where: { $0.entity == "budget_plan" && $0.entityID == old.id }) {
                        let state = try operationState(pending.id) ?? LedgerSchemaV2.OperationState(id: pending.id, baseRevision: 0)
                        if try operationState(pending.id) == nil { context.insert(state) }
                        state.issueData = try JSONEncoder().encode(SyncIssue(id: pending.id, entity: "budget_plan", entityID: old.id,
                            message: "Another device created this year's budget. Review both plans.", current: record))
                        continue
                    }
                }
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
        if issue.entity == "budget_plan" { try resolvePlan(issue, keepLocal: keepLocal); return }
        if issue.entity == "year_budget", issue.current == nil, !keepLocal {
            try syncCommit {
                for pending in pendingChanges.filter({ $0.entity == issue.entity && $0.entityID == issue.entityID }) { try removeOperation(pending.id) }
                if let cached = try remoteState(issue.entity, issue.entityID) { try applyRemote(JSONDecoder().decode(RemoteRecord.self, from: cached.data)) }
                else if let row = try context.fetch(FetchDescriptor<YearBudgetRecord>()).first(where: { $0.id == issue.entityID }) { context.delete(row) }
            }
            try reloadAll(); saveCount += 1; return
        }
        if ["shared_expense", "shared_assignment", "repayment"].contains(issue.entity) {
            try resolveShared(issue, keepLocal: keepLocal); return
        }
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
        guard categories.isEmpty, budgets.isEmpty, annualPlans.isEmpty, expenses.isEmpty, pendingChanges.isEmpty else { throw ConnectionError.notEmpty }
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
            for original in source.annualPlans {
                guard let free = categoryIDs[original.freeCategoryID] else { throw ConnectionError.invalidData }
                let value = AnnualBudgetPlan(id: UUID(), year: original.year, total: original.total, freeCategoryID: free,
                    allocations: try original.allocations.map { item in
                        guard let category = categoryIDs[item.categoryID] else { throw ConnectionError.invalidData }
                        return CategoryAllocation(categoryID: category, amount: item.amount)
                    })
                try putAnnualPlan(value)
                _ = try enqueue(entity: "budget_plan", id: value.id, action: "upsert", payload: value, offset: offset)
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
        case "budget_plan":
            guard let value = annualPlans.first(where: { $0.id == id }) else { throw ConnectionError.invalidData }
            return ("upsert", try .value(value))
        case "expense":
            guard let value = try context.fetch(FetchDescriptor<ExpenseRecord>()).first(where: { $0.id == id }) else { throw ConnectionError.invalidData }
            if let deleted = value.deletedAt {
                return ("delete", .object(["id": .string(id.uuidString), "deletedAt": .string(deleted.ISO8601Format())]))
            }
            return ("upsert", try .value(value.value()))
        default:
            if let pending = pendingChanges.last(where: { $0.entity == entity && $0.entityID == id }) {
                return (pending.action, try JSONDecoder().decode(JSONValue.self, from: pending.payload))
            }
            throw ConnectionError.invalidData
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
        case "budget_plan":
            let value = try record.payload.decoded(AnnualBudgetPlan.self)
            try value.validate()
            guard value.id == record.entityID, !record.deleted else { throw ConnectionError.invalidData }
            try putAnnualPlan(value)
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
        case "shared_expense", "shared_assignment", "sharing_invitation", "repayment":
            try applySharingRecord(record)
        default: throw ConnectionError.invalidData
        }
    }
    private func syncCommit(_ changes: () throws -> Void) throws {
        do { try changes(); try context.save() }
        catch { context.rollback(); throw error }
    }
    private func reloadAll() throws {
        annualPlans = try context.fetch(FetchDescriptor<LedgerSchemaV4.AnnualPlanRecord>()).map { try $0.value() }
        categories = try context.fetch(FetchDescriptor<CategoryRecord>()).map(\.value)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        budgets = try context.fetch(FetchDescriptor<YearBudgetRecord>()).map(\.value)
        expenses = try context.fetch(FetchDescriptor<ExpenseRecord>()).filter { $0.deletedAt == nil }.map { try $0.value() }
            .sorted { $0.day == $1.day ? $0.createdAt > $1.createdAt : $0.day > $1.day }
        try reloadSharing()
        let sharedIDs = Set(sharedExpenses.map(\.id))
        expenses.removeAll { sharedIDs.contains($0.id) }
        expenses += try sharedExpenses.filter { !$0.deleted }.map { try $0.expense }
        expenses.sort { $0.day == $1.day ? $0.createdAt > $1.createdAt : $0.day > $1.day }
        pendingChanges = try context.fetch(FetchDescriptor<PendingChangeRecord>()).map(\.value).sorted { $0.sequence < $1.sequence }
        issues = try context.fetch(FetchDescriptor<LedgerSchemaV2.OperationState>()).compactMap {
            try $0.issueData.map { try JSONDecoder().decode(SyncIssue.self, from: $0) }
        }
    }
}

extension LedgerStore {
    var sharingConnections: [SharingConnection] {
        let all = sharedExpenses.compactMap(\.connection) + repayments.map(\.connection)
        return Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }).values.sorted { $0.otherName < $1.otherName }
    }
    func sharedBalance(_ connection: UUID, excludingRepayment: UUID? = nil) throws -> Int64 {
        try SharedMath.summarize(expenses: sharedExpenses.filter { !$0.deleted && $0.status == "accepted" && $0.connection?.id == connection }.map { try $0.amounts },
            repayments: repayments.filter { $0.connectionID == connection && $0.id != excludingRepayment }
                .map { RepaymentAmounts(amount: $0.amount, paidByUser: $0.paidByUser) }).balance
    }
    func shareExpense(_ id: UUID, viewerID: UUID, username: String, email: String,
                      connection: SharingConnection?, paidByUser: Bool, split: PersonalSplit) throws {
        guard let source = expenses.first(where: { $0.id == id }), !sharedExpenses.contains(where: { $0.id == id }) else { throw LedgerError.missingExpense }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard connection != nil || (email.contains("@") && email.count <= 254) else { throw ConnectionError.rejected("Enter the other person's email address.") }
        let value = SharedExpenseValue(id: id, viewerID: viewerID, creatorID: viewerID,
            recipientID: connection?.otherID, creatorName: username, recipientName: connection?.otherName,
            recipientEmail: connection == nil ? email : nil, status: connection == nil ? "pending" : "accepted",
            amount: source.amount, description: source.description, day: source.day, createdAt: source.createdAt,
            paidByCreator: paidByUser, creatorSplit: split, categoryID: source.categoryID, assignmentRevision: 1, revision: 0,
            connection: connection, bootstrapRecords: [], history: [], deleted: false)
        var fields: [String: JSONValue] = ["id": .string(id.uuidString), "command": .string("share"),
            "paidByCreator": .bool(paidByUser), "creatorSplit": .string(split.rawValue)]
        if let dependency = pendingChanges.last(where: { $0.entity == "expense" && $0.entityID == id }) {
            fields["sourceOperationID"] = .string(dependency.id.uuidString)
        } else {
            guard let revision = try remoteState("expense", id)?.revision else { throw ConnectionError.rejected("Sync this expense before sharing.") }
            fields["sourceRevision"] = .integer(revision)
        }
        if let connection { fields["recipientID"] = .string(connection.otherID.uuidString) }
        else { fields["recipientEmail"] = .string(email) }
        try commit {
            try putShared("shared_expense", id, payload: .value(value), deleted: false)
            _ = try enqueue(entity: "shared_expense", id: id, action: "upsert", payload: JSONValue.object(fields))
        }
        try reloadAll()
    }
    func acceptInvitation(_ invitation: SharingInvitation) throws {
        let revision = try remoteState("sharing_invitation", invitation.id)?.revision ?? 1
        try commit {
            let pending = try enqueue(entity: "shared_expense", id: invitation.id, action: "upsert",
                payload: JSONValue.object(["id": .string(invitation.id.uuidString), "command": .string("accept")]))
            try operationState(pending.id)?.baseRevision = revision
        }
        try reloadAll()
    }
    func editSharedExpense(_ original: SharedExpenseValue, amount: Int64, description: String, categoryID: UUID,
                           day: ExpenseDay, paidByUser: Bool, ownSplit: PersonalSplit) throws {
        guard !original.deleted, sharedExpenses.first(where: { $0.id == original.id })?.deleted == false,
              (1...Money.maximum).contains(amount), description.count <= 500 else { throw LedgerError.invalidAmount }
        guard categories.contains(where: { $0.id == categoryID }) else { throw LedgerError.missingCategory }
        let commonChanged = amount != original.amount || description.trimmingCharacters(in: .whitespacesAndNewlines) != original.description ||
            day != original.day || paidByUser != original.paidByUser || ownSplit != original.ownSplit
        var value = commonChanged ? original : sharedExpenses.first(where: { $0.id == original.id }) ?? original
        value.amount = commonChanged ? amount : value.amount; value.description = description.trimmingCharacters(in: .whitespacesAndNewlines); value.day = day
        value.paidByCreator = original.isCreator == paidByUser
        value.creatorSplit = original.isCreator ? ownSplit : ownSplit.reversed
        if !commonChanged, let current = sharedExpenses.first(where: { $0.id == original.id }) { value = current }
        value.categoryID = categoryID
        let priorCommon = pendingChanges.contains { $0.entity == "shared_expense" && $0.entityID == value.id }
        let priorAssignment = pendingChanges.contains { $0.entity == "shared_assignment" && $0.entityID == value.id }
        try commit {
            try putShared("shared_expense", value.id, payload: .value(value), deleted: false)
            if commonChanged {
                let pending = try enqueue(entity: "shared_expense", id: value.id, action: "upsert", payload: commonCommand(value))
                if !priorCommon { try operationState(pending.id)?.baseRevision = original.revision }
            }
            if categoryID != original.categoryID {
                let payload = SharedAssignment(id: value.id, categoryID: categoryID)
                try putShared("shared_assignment", value.id, payload: .value(payload), deleted: false)
                let pending = try enqueue(entity: "shared_assignment", id: value.id, action: "upsert", payload: payload, offset: 1)
                if !priorAssignment { try operationState(pending.id)?.baseRevision = original.assignmentRevision }
            }
        }
        try reloadAll()
    }
    func deleteSharedExpense(_ id: UUID) throws {
        guard var value = sharedExpenses.first(where: { $0.id == id && !$0.deleted }) else { throw LedgerError.missingExpense }
        value.deleted = true
        try commit {
            try putShared("shared_expense", id, payload: .value(value), deleted: true)
            _ = try enqueue(entity: "shared_expense", id: id, action: "delete", payload: JSONValue.object(["id": .string(id.uuidString)]))
        }
        try reloadAll()
    }
    func recordRepayment(connection: SharingConnection, viewerID: UUID, username: String, amount: Int64, day: ExpenseDay) throws {
        let balance = try sharedBalance(connection.id)
        guard balance != 0, (1...Money.maximum).contains(amount), amount <= abs(balance) else { throw LedgerError.invalidAmount }
        let value = RepaymentValue(id: UUID(), viewerID: viewerID, connectionID: connection.id,
            payerID: balance < 0 ? viewerID : connection.otherID, recipientID: balance < 0 ? connection.otherID : viewerID,
            amount: amount, day: day, createdAt: .now, actorName: username, connection: connection)
        guard case .object(var fields) = try JSONValue.value(value) else { throw ConnectionError.invalidData }
        fields["balanceAtConfirmation"] = .integer(balance)
        try commit {
            try putShared("repayment", value.id, payload: .value(value), deleted: false)
            _ = try enqueue(entity: "repayment", id: value.id, action: "upsert", payload: JSONValue.object(fields))
        }
        try reloadAll()
    }

    private func commonCommand(_ value: SharedExpenseValue) throws -> JSONValue {
        .object(["id": .string(value.id.uuidString), "amount": .integer(value.amount), "description": .string(value.description),
            "day": try .value(value.day), "paidByCreator": .bool(value.paidByCreator), "creatorSplit": .string(value.creatorSplit.rawValue)])
    }
    private func putShared(_ kind: String, _ id: UUID, payload: JSONValue, deleted: Bool) throws {
        let data = try JSONEncoder().encode(payload), key = RemoteRecord.key(kind, id)
        if let saved = try context.fetch(FetchDescriptor<LedgerSchemaV3.SharedRecord>()).first(where: { $0.key == key }) {
            saved.data = data; saved.deleted = deleted
        } else { context.insert(LedgerSchemaV3.SharedRecord(entity: kind, id: id, data: data, deleted: deleted)) }
    }
    private func applySharingRecord(_ record: RemoteRecord) throws {
        if record.entity == "shared_expense" {
            var value = try record.payload.decoded(SharedExpenseValue.self)
            guard value.id == record.entityID, value.viewerID == value.creatorID || value.viewerID == value.recipientID else { throw ConnectionError.invalidData }
            _ = try value.amounts
            _ = try ExpenseDay(iso: value.day.iso)
            for bootstrap in value.bootstrapRecords {
                let pending = try context.fetch(FetchDescriptor<PendingChangeRecord>()).contains { $0.entityKind == bootstrap.entity && $0.entityID == bootstrap.entityID }
                try remember(bootstrap)
                if !pending, let cached = try remoteState(bootstrap.entity, bootstrap.entityID) {
                    try applyRemote(JSONDecoder().decode(RemoteRecord.self, from: cached.data))
                }
            }
            let assignmentPending = try context.fetch(FetchDescriptor<PendingChangeRecord>()).contains { $0.entityKind == "shared_assignment" && $0.entityID == value.id }
            let assignmentKey = RemoteRecord.key("shared_assignment", value.id)
            let cached = try context.fetch(FetchDescriptor<LedgerSchemaV3.SharedRecord>()).first { $0.key == assignmentKey }
            let knownRevision = try remoteState("shared_assignment", value.id)?.revision ?? 0
            let serverAssignment = SharedAssignment(id: value.id, categoryID: value.categoryID)
            try remember(RemoteRecord(entity: "shared_assignment", entityID: value.id, revision: value.assignmentRevision,
                deleted: false, payload: try .value(serverAssignment)))
            if let cached, assignmentPending || knownRevision > value.assignmentRevision {
                value.categoryID = try JSONDecoder().decode(JSONValue.self, from: cached.data).decoded(SharedAssignment.self).categoryID
            } else {
                let a = SharedAssignment(id: value.id, categoryID: value.categoryID)
                let envelope = RemoteRecord(entity: "shared_assignment", entityID: value.id, revision: value.assignmentRevision, deleted: false, payload: try .value(a))
                try remember(envelope)
                try putShared("shared_assignment", value.id, payload: envelope.payload, deleted: false)
            }
            value.deleted = record.deleted
            value.revision = record.revision
            try putShared(record.entity, record.entityID, payload: .value(value), deleted: record.deleted)
        } else {
            try putShared(record.entity, record.entityID, payload: record.payload, deleted: record.deleted)
        }
    }
    private func reloadSharing() throws {
        let rows = try context.fetch(FetchDescriptor<LedgerSchemaV3.SharedRecord>())
        func values<T: Decodable>(_ kind: String, _ type: T.Type) throws -> [T] {
            try rows.filter { $0.entityKind == kind && (kind == "shared_expense" || !$0.deleted) }
                .map { try JSONDecoder().decode(JSONValue.self, from: $0.data).decoded(type) }
        }
        sharedExpenses = try values("shared_expense", SharedExpenseValue.self)
        let assignments = try values("shared_assignment", SharedAssignment.self)
        for index in sharedExpenses.indices {
            if let a = assignments.first(where: { $0.id == sharedExpenses[index].id }) { sharedExpenses[index].categoryID = a.categoryID }
        }
        let accepted = Set(sharedExpenses.filter { $0.status == "accepted" || $0.deleted }.map(\.id))
        invitations = try values("sharing_invitation", SharingInvitation.self).filter { !accepted.contains($0.id) }
        repayments = try values("repayment", RepaymentValue.self).sorted { $0.day > $1.day }
    }
    private func resolveShared(_ issue: SyncIssue, keepLocal: Bool) throws {
        let selected = pendingChanges.filter { $0.entity == issue.entity && $0.entityID == issue.entityID }
        guard let first = selected.first else { throw ConnectionError.invalidData }
        if keepLocal, case .object(let fields) = try JSONDecoder().decode(JSONValue.self, from: first.payload),
           fields["command"] == .string("share") {
            throw ConnectionError.rejected("This expense already has a sharing record. Use the server version and review its participants.")
        }
        try syncCommit {
            var latest = try localPayload(entity: issue.entity, id: issue.entityID)
            if issue.entity == "shared_expense", let value = sharedExpenses.first(where: { $0.id == issue.entityID }), !value.deleted {
                latest = ("upsert", try commonCommand(value))
            }
            for pending in selected { try removeOperation(pending.id) }
            if keepLocal {
                guard issue.current?.deleted != true else { throw ConnectionError.rejected("This shared expense was deleted. Keep its history and create a new expense if needed.") }
                let pending = try enqueue(entity: issue.entity, id: issue.entityID, action: latest.0, payload: latest.1)
                try replaceSequence(pending.id, with: first.sequence, base: issue.current?.revision ?? 0)
            } else if let cached = try remoteState(issue.entity, issue.entityID) {
                try applyRemote(JSONDecoder().decode(RemoteRecord.self, from: cached.data))
            } else {
                let key = RemoteRecord.key(issue.entity, issue.entityID)
                if let row = try context.fetch(FetchDescriptor<LedgerSchemaV3.SharedRecord>()).first(where: { $0.key == key }) { context.delete(row) }
            }
        }
        try reloadAll(); saveCount += 1
    }
}

extension LedgerStore {
    func annualPlan(year: Int) -> AnnualBudgetPlan? { annualPlans.first { $0.year == year } }
    func wholeBudget(month: BudgetMonth) throws -> AnnualBudgetOverview? {
        try annualPlan(year: month.year).map { try AnnualBudgetCalculator.overview($0, month: month, categories: categories, expenses: expenses) }
    }
    func legacyAllocations(year: Int) -> [CategoryAllocation] {
        budgets.filter { $0.year == year && $0.amount > 0 }.map { CategoryAllocation(categoryID: $0.categoryID, amount: $0.amount) }
    }
    func defaultSpendingCategory(year: Int) -> CategoryValue {
        if let id = annualPlan(year: year)?.freeCategoryID, let category = categories.first(where: { $0.id == id }) { return category }
        return categories.first { $0.name.compare("Uncategorized", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame } ?? CategoryValue(id: UUID(), name: "Uncategorized")
    }
    func saveAnnualPlan(year: Int, total: Int64, allocations: [CategoryAllocation], expectedRevision: Int64? = nil, confirmedPlan: AnnualBudgetPlan? = nil) throws {
        let existing = annualPlan(year: year)
        let confirmedBase = try effectivePlanRevision(snapshot: confirmedPlan, expected: expectedRevision)
        let ids = Set(allocations.map(\.categoryID))
        var free = existing.flatMap { p in categories.first { $0.id == p.freeCategoryID } } ?? defaultSpendingCategory(year: year)
        if ids.contains(free.id) {
            guard existing == nil else { throw ConnectionError.rejected("Leave the default category for guilt-free spending.") }
            if let candidate = categories.first(where: { $0.name == "Guilt-free spending" && !ids.contains($0.id) }) { free = candidate }
            else {
                var name = "Guilt-free spending", suffix = 2
                while categories.contains(where: { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
                    name = "Guilt-free spending \(suffix)"; suffix += 1
                }
                free = CategoryValue(id: UUID(), name: name)
            }
        }
        let value = AnnualBudgetPlan(id: existing?.id ?? UUID(), year: year, total: total, freeCategoryID: free.id,
            allocations: allocations.sorted { $0.categoryID.uuidString < $1.categoryID.uuidString })
        try value.validate()
        guard allocations.allSatisfy({ a in categories.contains { $0.id == a.categoryID } }) else { throw LedgerError.missingCategory }
        let prior = pendingChanges.contains { $0.entity == "budget_plan" && $0.entityID == value.id }
        try commit {
            var offset = 0
            if !categories.contains(where: { $0.id == free.id }) {
                context.insert(CategoryRecord(free))
                _ = try enqueue(entity: "category", id: free.id, action: "upsert", payload: free)
                offset = 1
            }
            try putAnnualPlan(value)
            let pending = try enqueue(entity: "budget_plan", id: value.id, action: "upsert", payload: value, offset: offset)
            if let confirmedBase, !prior { try operationState(pending.id)?.baseRevision = confirmedBase }
        }
        try reloadAll()
    }
    private func effectivePlanRevision(snapshot: AnnualBudgetPlan?, expected: Int64?) throws -> Int64? {
        guard let snapshot, let cached = try remoteState("budget_plan", snapshot.id),
              try JSONDecoder().decode(RemoteRecord.self, from: cached.data).payload.decoded(AnnualBudgetPlan.self) == snapshot else { return expected }
        return cached.revision
    }
    private func putAnnualPlan(_ original: AnnualBudgetPlan) throws {
        var value = original
        value.allocations.sort { $0.categoryID.uuidString < $1.categoryID.uuidString }
        if let saved = try context.fetch(FetchDescriptor<LedgerSchemaV4.AnnualPlanRecord>()).first(where: { $0.id == value.id }) {
            saved.data = try JSONEncoder().encode(value)
        } else { context.insert(try LedgerSchemaV4.AnnualPlanRecord(value)) }
    }
}

extension LedgerStore {
    private func resolvePlan(_ issue: SyncIssue, keepLocal: Bool) throws {
        let selected = pendingChanges.filter { $0.entity == "budget_plan" && $0.entityID == issue.entityID }
        guard let first = selected.first, let local = annualPlans.first(where: { $0.id == issue.entityID }) else { throw ConnectionError.invalidData }
        try syncCommit {
            for change in selected { try removeOperation(change.id) }
            if keepLocal {
                let canonical = issue.current?.entityID ?? local.id
                let value = AnnualBudgetPlan(id: canonical, year: local.year, total: local.total, freeCategoryID: local.freeCategoryID, allocations: local.allocations)
                if canonical != local.id, let row = try context.fetch(FetchDescriptor<LedgerSchemaV4.AnnualPlanRecord>()).first(where: { $0.id == local.id }) { context.delete(row) }
                try putAnnualPlan(value)
                let pending = try enqueue(entity: "budget_plan", id: canonical, action: "upsert", payload: value)
                try replaceSequence(pending.id, with: first.sequence, base: issue.current?.revision ?? 0)
            } else {
                if let row = try context.fetch(FetchDescriptor<LedgerSchemaV4.AnnualPlanRecord>()).first(where: { $0.id == local.id }) { context.delete(row) }
                if let current = issue.current {
                    let latest = try remoteState(current.entity, current.entityID).flatMap { try JSONDecoder().decode(RemoteRecord.self, from: $0.data) }
                    try applyRemote(latest ?? current)
                } else if let cached = try remoteState("budget_plan", local.id) {
                    try applyRemote(JSONDecoder().decode(RemoteRecord.self, from: cached.data))
                }
            }
        }
        try reloadAll(); saveCount += 1
    }
}
