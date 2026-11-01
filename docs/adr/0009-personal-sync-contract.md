# ADR 0009: Personal expense synchronization

- Status: Accepted implementation contract for personal records
- Date: 2026-11-01

## Scope

Implement the first connected flow for private categories, category/year budgets, and personal expenses. This does not approve the shared-expense invitation/repayment assumptions in the separate draft. Both website and API writes use `MoneyTrack.Ledger`.

## Contract

- API prefix `/api/v1`. `POST /sessions` exchanges username/password for a revocable device token and identity. `GET /session` checks it; `DELETE /session` revokes it. Protected routes require a device Bearer token; browser cookies are not API credentials.
- `POST /sync` accepts exactly `operationID`, `entity`, `entityID`, `action`, `expectedRevision`, and `payload`. IDs are UUIDs; amounts are integer EUR cents. Payload shapes match the documented Swift category/year-budget/expense value types. Calendar dates are explicit year/month/day fields; `createdAt` is ISO 8601 UTC, canonicalized to seconds. Only personal, 100% own-share expenses are accepted in this slice.
- Expected revision zero means create. A stale revision produces HTTP 409 with the owner-visible server version. Missing/inaccessible records return a generic error. A deleted expense remains a tombstone and cannot be resurrected by an update.
- One SQLite transaction validates ownership and references, changes the record/revision, appends an owner-private change, and stores the operation result. Account/operation UUID deduplication survives device session renewal. Identical retries return the original result; reuse with different JSON content is rejected. Retain operation and deletion history for this MVP.
- `GET /sync?cursor=...` returns changes, a new cursor, and `hasMore`. Pages contain at most 100 changes. Signed cursors are bound to the account and carry a per-user sequence and a frozen upper boundary during catch-up. New writes are fetched in the next cycle. Cursors never depend on client clocks.
- SwiftData V2 adds operation state, cached server revisions/snapshots, and cursor/import state. V1 models remain unchanged. A lightweight migration preserves populated V1 data, original queued payloads/IDs, and tombstones.
- Preparing a pending operation saves its complete wire bytes and base revision before sending. Retry those bytes unchanged until acknowledgment or explicit user resolution. Acknowledgment removes the pending operation and updates cached revisions atomically. Dependent local edits use the preceding acknowledged revision, never an unseen foreign revision.
- Apply each pulled page, server snapshots, and its cursor together. Pending local records are not overwritten. A bad cursor restarts catch-up without deleting pending work or cached tombstones.
- Financial conflicts preserve the current local version and server version. Users choose the server version or explicitly submit their current local version against the displayed revision. If the server changed again, review again. Keeping an expense deleted elsewhere creates a new expense ID rather than restoring the deleted record. Concurrent creation of a category/year budget resolves to its existing canonical record.
- Validation failures remain pending for correction/review. Do not silently discard them. Duplicate category names can be corrected through the review screen's category editor.
- Sync on foreground, connectivity recovery, local writes, and manual refresh. Background delivery is an optimization, not a guarantee.

## Account ownership and initial data

Native stores are scoped by canonical server origin plus account UUID. Keychain holds the active identity/token; switching profiles recreates the navigation root and never applies a previous profile's in-flight response to a new one. Expired authentication keeps the active cache and pending changes.

Sign-in leaves unbound on-device data separate by default. An explicit, one-time copy is offered for an empty account. Copy current categories, budgets, and non-deleted expenses in one local transaction, remapping IDs/references and queuing new operations. Preserve the original store and its history unchanged. Repeating the same account copy is harmless. Merging independently populated ledgers, or repeatedly importing edits to the original unbound copy, is not implemented.

## Verification

Server tests cover account isolation, retry deduplication, revision conflicts, tombstones, frozen pagination, and website writes through the same feed. Native tests cover populated V1 migration, exact retry persistence, failed acknowledgment rollback, atomic/idempotent pull, conflict resolution, and explicit import isolation. `scripts/check-connected` uses a temporary database and synthetic accounts to run real native API and simulator sign-in/relaunch checks; it refuses to reuse a server already occupying its test port.
