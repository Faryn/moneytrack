import Foundation
import SwiftData

enum LedgerSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [CategoryRecord.self, YearBudgetRecord.self, ExpenseRecord.self, PendingChangeRecord.self]
    }

    @Model final class CategoryRecord {
        @Attribute(.unique) var id: UUID
        var name: String
        init(_ value: CategoryValue) { id = value.id; name = value.name }
        var value: CategoryValue { .init(id: id, name: name) }
    }

    @Model final class YearBudgetRecord {
        @Attribute(.unique) var id: UUID
        var categoryID: UUID
        var year: Int
        var amount: Int64
        init(_ value: YearBudgetValue) {
            id = value.id; categoryID = value.categoryID; year = value.year; amount = value.amount
        }
        var value: YearBudgetValue { .init(id: id, categoryID: categoryID, year: year, amount: amount) }
    }

    @Model final class ExpenseRecord {
        @Attribute(.unique) var id: UUID
        var categoryID: UUID
        var amount: Int64
        var personalShare: Int64
        var descriptionText: String
        var calendarDay: String
        var createdAt: Date
        var deletedAt: Date?

        init(_ value: ExpenseValue) {
            id = value.id; categoryID = value.categoryID; amount = value.amount
            personalShare = value.personalShare; descriptionText = value.description
            calendarDay = value.day.iso; createdAt = value.createdAt; deletedAt = nil
        }
        func value() throws -> ExpenseValue {
            .init(id: id, categoryID: categoryID, amount: amount, personalShare: personalShare,
                  description: descriptionText, day: try ExpenseDay(iso: calendarDay), createdAt: createdAt)
        }
    }

    @Model final class PendingChangeRecord {
        @Attribute(.unique) var id: UUID
        var entityID: UUID
        var entityKind: String
        var action: String
        var sequence: Int64
        var payload: Data
        var createdAt: Date

        init(_ value: PendingChangeValue) {
            id = value.id; entityID = value.entityID; entityKind = value.entity; action = value.action
            sequence = value.sequence; payload = value.payload; createdAt = .now
        }
        var value: PendingChangeValue {
            .init(id: id, entityID: entityID, entity: entityKind, action: action, sequence: sequence, payload: payload)
        }
    }
}

enum LedgerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LedgerSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

typealias CategoryRecord = LedgerSchemaV1.CategoryRecord
typealias YearBudgetRecord = LedgerSchemaV1.YearBudgetRecord
typealias ExpenseRecord = LedgerSchemaV1.ExpenseRecord
typealias PendingChangeRecord = LedgerSchemaV1.PendingChangeRecord

enum StoreNamespace {
    case localDevice
    case account(UUID)
    case uiTesting
    var directoryName: String {
        switch self {
        case .localDevice: "local-device"
        case .account(let id): id.uuidString.lowercased()
        case .uiTesting: "ui-testing"
        }
    }
}

enum LedgerPersistence {
    static func container(
        root: URL? = nil, namespace: StoreNamespace = .localDevice, allowsSave: Bool = true
    ) throws -> ModelContainer {
        let base = try root ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appending(path: "MoneyTrack", directoryHint: .isDirectory)
        let directory = base.appending(path: namespace.directoryName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: LedgerSchemaV1.self)
        let configuration = ModelConfiguration(
            "MoneyTrack", schema: schema, url: directory.appending(path: "ledger.store"),
            allowsSave: allowsSave, cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, migrationPlan: LedgerMigrationPlan.self, configurations: [configuration])
    }
}
