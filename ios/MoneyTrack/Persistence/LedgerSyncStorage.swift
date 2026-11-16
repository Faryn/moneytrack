import Foundation
import SwiftData

/// Persistence for the outbox, sync cursor, and server revisions.
/// LedgerStore owns saves and rollbacks for this shared context.
@MainActor
struct LedgerSyncStorage {
    private let context: ModelContext

    init(context: ModelContext) { self.context = context }

    func enqueue<T: Encodable>(
        entity: String, id: UUID, action: String, payload: T, sequence: Int64
    ) throws -> PendingChangeValue {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let value = PendingChangeValue(id: UUID(), entityID: id, entity: entity, action: action,
                                       sequence: sequence, payload: try encoder.encode(payload))
        let prior = try context.fetch(FetchDescriptor<PendingChangeRecord>()).contains {
            ($0.entityKind == entity || (entity == "shared_assignment" && $0.entityKind == "shared_expense")) && $0.entityID == id
        }
        let base = prior ? nil : try remoteState(entity, id)?.revision ?? 0
        context.insert(LedgerSchemaV2.OperationState(id: value.id, baseRevision: base))
        context.insert(PendingChangeRecord(value))
        return value
    }

    func encodeOperation(_ pending: PendingChangeValue, baseRevision: Int64?) throws -> Data {
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
        if let base = baseRevision { expectedRevision = base }
        else { expectedRevision = try remoteState(pending.entity, pending.entityID)?.revision ?? 0 }
        let wire = WireOperation(operationID: pending.id, entity: pending.entity, entityID: pending.entityID,
                                 action: pending.action, expectedRevision: expectedRevision, payload: payload)
        return try JSONEncoder().encode(wire)
    }

    func recordIssue(_ issue: SyncIssue) throws {
        let state = try stateForWrite(issue.id, initialBase: 0)
        state.issueData = try JSONEncoder().encode(issue)
    }

    func freeze(_ data: Data, for id: UUID) throws {
        try stateForWrite(id, initialBase: 0).wireData = data
    }

    func advanceDependentBase(after acknowledged: PendingChangeValue, revision: Int64) throws -> Bool {
        let remaining = try pendingRecords().first {
            $0.entityKind == acknowledged.entity && $0.entityID == acknowledged.entityID
        }
        guard let remaining else { return false }
        let state = try stateForWrite(remaining.id, initialBase: nil)
        // A dependent edit uses our acknowledged revision, even if a newer peer revision exists.
        if state.baseRevision == nil { state.baseRevision = revision }
        return true
    }

    func pendingRecords() throws -> [PendingChangeRecord] {
        try context.fetch(FetchDescriptor<PendingChangeRecord>(sortBy: [SortDescriptor(\.sequence)]))
    }

    func pendingChanges() throws -> [PendingChangeValue] {
        try pendingRecords().map(\.value)
    }

    func issues() throws -> [SyncIssue] {
        try context.fetch(FetchDescriptor<LedgerSchemaV2.OperationState>()).compactMap {
            try $0.issueData.map { try JSONDecoder().decode(SyncIssue.self, from: $0) }
        }
    }

    func replaceSequence(_ id: UUID, with sequence: Int64, base: Int64) throws {
        try context.fetch(FetchDescriptor<PendingChangeRecord>()).first(where: { $0.id == id })?.sequence = sequence
        try operationState(id)?.baseRevision = base
    }
    func removeOperation(_ id: UUID) throws {
        if let value = try context.fetch(FetchDescriptor<PendingChangeRecord>()).first(where: { $0.id == id }) { context.delete(value) }
        if let value = try operationState(id) { context.delete(value) }
    }
    func operationState(_ id: UUID) throws -> LedgerSchemaV2.OperationState? {
        try context.fetch(FetchDescriptor<LedgerSchemaV2.OperationState>()).first { $0.id == id }
    }

    private func stateForWrite(_ id: UUID, initialBase: Int64?) throws -> LedgerSchemaV2.OperationState {
        if let state = try operationState(id) { return state }
        let state = LedgerSchemaV2.OperationState(id: id, baseRevision: initialBase)
        context.insert(state)
        return state
    }
    func remoteState(_ entity: String, _ id: UUID) throws -> LedgerSchemaV2.RemoteState? {
        let key = RemoteRecord.key(entity, id)
        return try context.fetch(FetchDescriptor<LedgerSchemaV2.RemoteState>(predicate: #Predicate { $0.key == key })).first
    }
    func metadata() throws -> LedgerSchemaV2.SyncState {
        if let state = try context.fetch(FetchDescriptor<LedgerSchemaV2.SyncState>()).first { return state }
        let state = LedgerSchemaV2.SyncState(); context.insert(state); return state
    }
    @discardableResult
    func remember(_ record: RemoteRecord) throws -> RemoteRecord {
        guard record.revision > 0 else { throw ConnectionError.invalidData }
        if let saved = try remoteState(record.entity, record.entityID) {
            if saved.revision > record.revision {
                return try JSONDecoder().decode(RemoteRecord.self, from: saved.data)
            }
            saved.data = try JSONEncoder().encode(record)
            saved.revision = record.revision
        } else {
            context.insert(LedgerSchemaV2.RemoteState(key: record.key, revision: record.revision,
                data: try JSONEncoder().encode(record)))
        }
        return record
    }
}
