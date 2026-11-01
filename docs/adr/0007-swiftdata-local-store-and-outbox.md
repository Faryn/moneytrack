# ADR 0007: SwiftData local storage and durable pending changes

- Status: Accepted implementation choice for the first local iOS version
- Date: 2026-11-01

## Context

The iOS app must save expenses offline, preserve pending work through restarts, and fit a native SwiftUI implementation. The prototype now verifies disk-backed reopening, edit/delete behavior, account namespaces, and rollback when a real read-only store refuses a save.

## Decision

- Use SwiftData with an explicit schema version and migration plan. Disable automatic saving; the repository's store is the writer.
- Save each domain mutation and its pending-change records in one explicit `ModelContext.save()`. Roll back the context on failure; update observable snapshots only after saving succeeds.
- Give entities and queued operations stable UUIDs. Preserve queued payloads on disk and order them locally.
- Keep deletion tombstones alongside queued deletion operations.
- Keep a separate file namespace for local-device data, each account UUID, and UI test data. An account connection must not implicitly send another namespace's pending changes.
- Store expense dates as validated calendar dates and money as exact cents.
- Disable CloudKit. The Phoenix API remains the intended sync backend.
- Surface store-open and migration failures without deleting data or silently opening an empty replacement store.

## Consequences and boundaries

The first app works locally without authentication or a server connection. Its outbox is a durability foundation; it has no sender, acknowledgments, server revisions, change cursor, conflict resolution, or implemented wire contract. Those belong to the next milestone and may require a forward migration. Linking existing local data to a newly authenticated account needs an explicit import/ownership flow.

V1 is the first implemented schema. Before the first schema change, add and test a forward migration against populated V1 fixtures, including pending operations and tombstones. This prototype does not claim to have tested a V1-to-V2 migration.

Use record property names that avoid underlying Core Data reserved names, such as `entityKind` instead of `entity`. Store implementation and limitations are described in [local storage](../local-storage.md). Server SQLite remains a separate Ecto-managed database.

## Subsequent implementation

[ADR 0009](0009-personal-sync-contract.md) implements personal synchronization and a tested V1-to-V2 lightweight migration. V1 model definitions remain frozen; the migration adds separate operation/server/cursor state while preserving records, queued IDs/payloads, and tombstones. The original local-only prototype boundaries above describe the initial decision, not the current feature set.

[ADR 0012](0012-sharing-defaults-and-connected-flow.md) subsequently adds V3 shared records. [ADR 0013](0013-whole-year-budget-and-guilt-free-spending.md) adds V4 annual plans; populated forward-migration fixtures preserve earlier records and prepared bytes.
