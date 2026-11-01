# Local iOS storage

The first working personal-expense slice uses the versioned SwiftData store selected in [ADR 0007](adr/0007-swiftdata-local-store-and-outbox.md). It is fully local; account login and network synchronization are not implemented.

## Records and writes

V1 stores flat categories, category/year budget amounts, personal expenses, and pending changes. Expense records keep their purchase amount, personal share, category UUID, description, ISO calendar date, UTC creation timestamp, and optional deletion timestamp. No personal data or default financial records are seeded.

`LedgerStore` owns one context with autosaving disabled. It validates a mutation, changes domain records and inserts the matching pending operations, then explicitly saves once. Errors roll back the context and leave the displayed snapshots unchanged. An operation has a stable UUID, entity UUID/kind, action, local sequence, creation timestamp, and JSON payload. A deleted expense becomes a tombstone; it is removed from budget calculations without deleting its pending operation.

The pending payload is an internal prototype format, not the proposed HTTP sync contract. It lacks expected server revisions and acknowledgment state. Do not transmit it blindly or drop it when adding synchronization; design and test its forward migration first. Budget balances are derived from records rather than stored running totals.

## Locations and identity

Normal stores live in the app container under `Application Support/MoneyTrack/<namespace>/ledger.store`, outside the source checkout. Namespaces are `local-device`, an account UUID, or `ui-testing`. SwiftData may create sidecar files; never copy a live database alone as a backup.

The current app uses `local-device` without a logged-in identity. Account namespaces are tested for isolation but are not connected to login yet. A future account bootstrap must explicitly decide how existing local-device data is assigned/imported. Do not silently upload it to whichever account signs in next.

Store initialization errors produce a visible retry/error screen. There is no automatic reset or destructive recovery fallback. CloudKit is explicitly disabled.

## Tests and next requirements

Unit tests use temporary directories and cover exact-cent budgets, strict dates, save/edit/delete across reopening, stable pending operations, tombstones, namespaces, invalid input, and failed-save rollback against a read-only disk store. UI tests use only an isolated debug `ui-testing` namespace, reset that namespace explicitly, and verify the native creation/edit/relaunch/deletion flow.

Before synchronization is ready, implement authenticated ownership, stable server revisions, retry deduplication, acknowledgments, ordered dependent writes, pull cursors, conflict preservation, remote deletions, session expiry recovery, and real account switching. Before changing V1, verify forward migration using populated records and pending work. See the [draft sync design](data-model-and-sync.md).
