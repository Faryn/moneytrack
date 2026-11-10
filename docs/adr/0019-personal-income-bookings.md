# ADR 0019: Personal income bookings

- Status: Accepted
- Date: 2026-11-05

The user requested importing the complete bookings CSV into Paul’s account, replacing existing bookings and importing its categories. After being told the file includes income and the app only supports expenses, the user explicitly selected adding income support and importing everything. Budget amounts will be updated separately.

## Decision

- Add private income alongside expenses. The booking type is an explicit financial field in the same revision as amount, date and category. Amounts remain positive exact EUR cents; direction comes from type. Original currency conversion continues to use ADR 0017.
- Income is visible, editable and deletable in the bookings list, with a positive sign, Income label and accessible green amount semantics. Details offers an Expense/Income selector. Quick Entry retains its expense default.
- Income does not consume spending budgets, alter carryover, or automatically set a yearly plan. Budget numbers remain explicit owner choices. Monthly income and spending are shown separately.
- Income is private and cannot be shared or used as a repayment. Shared expense rules stay unchanged.
- Retain the `expense` sync entity and add optional `kind` (`expense` or `income`); omitted means expense. Introduce API v5. V1–v4 reject sync for accounts with income history or attempts to submit income, preserving pending operations instead of letting older apps reinterpret income as expenses. Existing prepared expense requests remain valid, byte for byte, through v5. Updates to an existing income require an explicit kind.
- SQLite adds a constrained kind column with expense as its default. SwiftData V6 adds separate income markers while V1–V5 models remain frozen. Domain mutations, marker changes and outbox entries save atomically. Migration never resets a failed store.

## Import

Validate every CSV record, exact amount, ISO calendar date, type and currency before mutation. Decode HTML entities in category names and retain source notes. Keep identical source rows as distinct bookings. Blank source categories use the existing private Uncategorized category or create it. Do not infer sharing from notes; the source has no participants.

Take a verified SQLite backup outside the checkout. Replace active bookings using owner-scoped ledger contexts and revisions in one transaction, retaining synchronized deletion history and duplicate-safe import operations. Import named categories without inventing budget numbers; preserve existing yearly totals and allocations for later editing. Shared deletions use the shared context and history. Recorded repayments and sharing connections remain separate.

This resolves the income deferral in SPEC.md and extends ADRs 0009, 0013 and 0017. It does not introduce bank synchronization, account reconciliation, recurring bookings or a general refund workflow.

## Verification

Verify income CRUD, account isolation, type validation, sharing rejection, duplicate retries, revisions, synchronized deletion, preserved currency conversion and unchanged budgets in Elixir and Swift. Verify populated V5 migration, immutable old operations, failed-save rollback, reopen/copy/pull/conflict retention and old-client upgrade responses. Reconcile all imported rows and per-type/per-year totals to the CSV after commit.
