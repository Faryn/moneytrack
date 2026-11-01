# Local iOS storage

The connected personal ledger uses SwiftData V2, with V1 preserved through a tested lightweight migration. See [ADR 0007](adr/0007-swiftdata-local-store-and-outbox.md) and the subsequent [personal sync contract](adr/0009-personal-sync-contract.md).

## Records and writes

V1 models remain unchanged: flat categories, category/year budgets, personal expenses, and pending changes. Expenses retain exact cents, category UUID, description, ISO calendar date, UTC client creation time, and optional deletion time. V2 adds operation state (base revision, prepared wire bytes, review issue), cached server revisions/snapshots, and cursor/import state. Balances are derived, never synchronized running totals.

`LedgerStore` owns one context with autosaving disabled. Domain changes and their pending operations save together, with rollback on failure. Preparation saves a complete immutable HTTP request before sending. Acknowledgment removes its pending operation and records the server result together. Dependent edits use our preceding acknowledged revision; they cannot silently rebase onto another device's edit. A failed acknowledgment retains the original bytes for a harmless retry.

Each pull page, cached snapshots, domain updates, and cursor save together. Pending records are not overwritten. Conflicts retain local/server versions for user choice. Deletions remain tombstones; retaining an edited item deleted elsewhere creates a new ID. Concurrent category/year budgets resolve to one canonical server record. A cursor reset replays retained history without deleting local work.

## Locations and identity

Normal stores live inside the app container at `Application Support/MoneyTrack/<namespace>/ledger.store`, outside the checkout. Unbound data uses `local-device`; connected data uses a hash of canonical server origin plus account UUID. Debug UI tests use `ui-testing`, isolated account caches, and a separate Keychain service. SwiftData may create sidecars; never copy a live database alone as a backup.

Keychain stores the active identity and revocable token with device-only accessibility after first unlock. Passwords are not saved. Session expiry preserves the active cache and queue. Switching accounts recreates the navigation root and cannot apply an old account's in-flight response to the new store. Sign-out retains each account's cached/pending data for its next sign-in.

Unbound entries stay separate by default. A deliberate one-time copy into an empty account remaps IDs and relationships and queues the current categories, budgets, and non-deleted expenses in one local save. Originals and their history remain untouched. Repeating that account copy is harmless. Merging two populated ledgers or repeatedly importing edits to the original copy is not implemented.

Store-open/migration failures show a retry screen and never trigger an automatic reset. CloudKit is disabled. Forward migration tests preserve populated V1 expenses, queued IDs/payloads, and tombstones. Before introducing V3, add populated V2 fixtures that include prepared requests, issues, metadata, and cursors.

## Verification and remaining work

Unit tests cover financial examples, strict dates, reopening, rollback, isolation, migration, prepared retries, atomic/idempotent pull, conflict resolution, and copying. `scripts/check-connected` adds real server/API and simulator account checks. Shared-expense permissions/history, invitation onboarding, passkeys, recovery, production backups/restoration, distribution, and released-client API compatibility remain work before the complete MVP release.

## Shared records in V3

V3 adds shared expense/invitation/assignment/repayment projections and source-acknowledgment dependencies without modifying V1/V2 model definitions. Personal and shared domain changes still commit with their outbox operations. Populated V2 migration, exact prepared bytes, failed shared saves, queued source revisions, and open-editor conflicts are covered by native tests. Source IDs are suppressed by their shared projection even after shared deletion, so replay cannot double-count or resurrect the original personal expense. See the [shared sync contract](contracts/shared-sync-v2.md).
