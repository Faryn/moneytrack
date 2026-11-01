# Data model and sync proposal

Status: draft for implementation planning, not an accepted sync ADR. Accepted product choices are in [SPEC.md](../SPEC.md) and [ADR 0005](adr/0005-shared-expenses-and-email-invitations.md). Proposed behavior below still needs review.

The personal-record subset is implemented in [ADR 0009](adr/0009-personal-sync-contract.md). Accounts/transport are selected in [ADR 0008](adr/0008-connected-accounts-and-transport.md). The shared records, invitation lifecycle, and repayment behavior below remain proposals.

## Ownership

Separate common financial facts from private budgeting choices:

- An expense's amount, description, date, payer, and split are common to its participants.
- Each participant owns their category assignment. Neither participant can fetch or edit the other's categories, budgets, or assignment.
- Remaining budget and interpersonal balances are calculated from records, not stored as editable running totals.
- An email invitation grants no financial-data access until accepted by the intended recipient.

## Proposed records

| Record | Main fields and purpose | Visibility |
| --- | --- | --- |
| User | UUID, username, password hash, account status | Own account; minimal identity for accepted counterparties |
| VerifiedEmail | User ID, email identity, verification state | Own account and server invitation logic |
| PasskeyCredential | User ID, credential ID, public key, credential metadata | Own credential management; never other participants |
| DeviceSession | User ID, device label, hashed credential, expiry/revocation | Own account |
| SharingConnection | Two accepted user IDs and state | The two users |
| SharingInvitation | Sender, recipient email, token hash, expiry/state, optional initial expense proposal | Sender and acceptance service; minimal invitation preview for recipient |
| Category | UUID, owner ID, name, archived state | Owner only |
| CategoryYearBudget | UUID, owner ID, category ID, calendar year, yearly minor-unit amount | Owner only |
| Expense | UUID, creator, amount/currency, description, calendar date, payer, participant shares, optional connection ID, revision/deletion state | Creator for personal expenses; both participants for shared expenses |
| ExpenseAssignment | UUID, expense ID, owner ID, category ID, revision | Owner only |
| ExpenseHistory | UUID, expense ID, revision, actor, UTC time, action, common-field changes | Both accepted participants; excludes private assignments |
| Repayment | UUID, connection ID, sender, recipient, amount/currency, calendar date, revision/deletion state | Both users in the connection |
| ProcessedOperation | Actor/device scope, operation UUID, request fingerprint, result | Sync service only |
| UserChange | User-scoped sequence, entity reference, change kind, own visible payload/revision | Named user only |

The tables are conceptual. Ecto schemas may use embedded split values or a participant table. Amount, payer, participants, and split form one atomic expense revision regardless of physical schema.

Use client-generated UUIDs for offline-created business records, integer minor currency units, calendar dates for expense attribution, and UTC audit timestamps. Require a unique category budget per owner/category/year and no duplicate accepted connection for a user pair. Database constraints and application authorization must enforce ownership and membership.

## Proposed invitation flow

1. Save a personal expense normally.
2. In its menu, enter the recipient's email and choose payer and split.
3. If there is no accepted connection, persist a pending invitation proposal. Queue it offline and send it after synchronization.
4. Recipient follows an expiring invitation link, signs in or creates an account, and proves control of the target address. Use a single-use token bound to the recipient email and invitation; an already verified matching address may satisfy this requirement. A forwarded link alone must not let a different address claim the invitation.
5. Acceptance creates the connection and applies the proposed sharing to the original expense atomically. Record the expense revision against which the proposal was made; if it changed, require refreshed confirmation rather than applying stale amounts.
6. Future expenses may be shared with that accepted account without another email invitation. The connection is an access prerequisite, not permission to read all expenses between the users: each expense must explicitly include both participants.

Proposed pending behavior: until initial acceptance, keep the expense personal for budget/debt calculations and show the prospective split separately. Reject expired, cancelled, or already used invitations safely. Declining leaves the expense personal. Cancellation and acceptance races are resolved by a transactional invitation state check.

An invitation exposes only the minimum sender/recipient and acceptance information before acceptance, not an expense history. Send no email or expense content as part of this documentation work.

## Proposed budgets and balances

When an expense becomes shared, each participant's personal spending uses their share in the expense's original calendar month. Preserve the creator's existing category assignment. Give the other participant an owner-private, system-provided Uncategorized category with a zero yearly allocation until they choose a category. Include that category in totals, so spending is counted immediately even before categorization.

For example, a €78 restaurant expense paid by Alice and split equally uses €39 of Alice's budget, €39 of Bob's budget, and creates a €39 obligation from Bob to Alice. Alice may categorize it as Restaurants while Bob chooses Leisure; neither sees the other's choice. A €39 repayment clears that obligation and changes neither budget.

Use the confirmed budget rounding, positive/negative carryover, whole-year recalculation after yearly edits, and January reset rules in [ADR 0006](adr/0006-calendar-year-budget-calculation.md). These financial rules are settled independently of this draft sync protocol.

## Editing and access policy

- Accepted in ADR 0005: both accepted participants may edit common expense fields and delete shared expenses. Show the actor, time, and shared changes in a history available to both, including deletion.
- Accepted: categories can be edited only by their owner. Proposed implementation: give private assignments separate revisions, so Alice categorizing an expense does not conflict with Bob categorizing it. Do not include either private assignment in shared history.
- Proposed: do not silently convert an accepted shared expense back to a personal record. The original personal expense no longer describes both users' history; an explicit removal/reversal policy needs agreement.
- Proposed: repayments become effective immediately when recorded by either participant and are visible to both. Confirmation/dispute requirements remain open.
- Deleting an expense removes its obligation and personal spending for both users. Existing repayments remain, potentially reversing the net balance; proposed UI: preview that outcome before confirmation.
- Proposed: reject changes by an actor who has lost access, even if their device queued the change earlier. Revocation cannot instantly erase an already downloaded copy from an offline device; remove cached common data when revocation is received, without sending other private data.

## Proposed sync contract

Use a versioned JSON API and a durable local outbox. SwiftData is selected in [ADR 0007](adr/0007-swiftdata-local-store-and-outbox.md), with domain/outbox saves and rollback tested. The subsequent personal implementation in ADR 0009 adds a tested V2 migration, prepared wire requests, explicit account copying, revisions, acknowledgments, and conflict review. Shared history/permissions and invitation work are still outside that implementation.

### Push

- Each operation carries a stable operation UUID, entity UUID, expected server revision, operation type, and validated payload. Never trust actor/owner identity supplied in a payload.
- Within one SQLite transaction, authorize membership, validate the expected revision and financial invariants, save the record, increment its revision, append common expense history and participant-specific change events, and save the operation result. Private category updates do not append to common expense history.
- Scope deduplication by authenticated actor/device. Replaying the same operation with the same payload returns its original result; reusing its UUID with different content is rejected. A retry must not increment revisions, send another email, or apply another debt.
- Persist invitation-delivery work in the same transaction and process it afterward. Retrying delivery must reuse the invitation and delivery identity rather than creating another invitation or a new access grant.
- Each changed shared expense produces an event for both participants. Personal category and budget changes produce an event only for their owner. Each response includes only records currently visible to that caller.
- Website actions use these same contexts and change-tracking transactions, even though they do not pass through the iOS outbox.

### Pull

- Return paginated changes after an opaque per-user cursor. Advance only to the last event actually returned; do not use client clocks as sync cursors.
- Persist each page and the new cursor together locally. Applying the same page again must be harmless.
- Represent deletions and lost access explicitly. An access-removal event contains only enough identity to evict the cached record, not its former content. Recheck authorization when serving historical events.
- Freeze an upper event boundary for a paginated catch-up so newly arriving writes cannot cause gaps. After the catch-up, request changes beyond that boundary.
- Keep deletion and operation-deduplication history for the MVP. If retention is added later, define a sync-generation reset and a consistent full snapshot boundary first. A stale device must not recreate removed records.

### Conflicts and offline edits

- A stale expected revision returns a conflict with the caller-visible current record. Retain the local attempted edit for review. Do not combine payer, amount, or split from different versions automatically.
- A delete/edit race is also a conflict. Do not automatically resurrect a deleted expense.
- Send dependent local operations in order, waiting for acknowledgment before basing a later edit on the resulting server revision. Coalesce only operations not yet sent; once sent, retain their ID and exact payload until resolved.
- Preserve pending work through sign-out/session expiry and isolate it by account. Reauthentication must not apply one user's queue to another user's account.
- Sync on foreground entry, local changes, and manual refresh. Background work is an optimization.

## Validation before calling sync ready

- Retrying a committed operation after a lost response changes financial results exactly once.
- A shared expense and its revisions reach both users, with distinct private categories.
- A third account cannot read or mutate the expense, private assignment, invitation, or either user's change feed.
- Invitation acceptance requires the intended email identity; replay and concurrent cancellation do not duplicate participants.
- Pagination and reconnects neither skip changes nor resurrect deleted expenses.
- A concurrent website edit and offline iOS edit surface a resolvable conflict.
- A freshly accepted expense counts toward the recipient's budget before manual categorization.
- A repayment affects only the interpersonal balance; deletion preserves the separately recorded repayment.
- Shared financial examples produce identical results in Swift and Elixir.

## Remaining review choices

Prioritize pending-invitation treatment, reuse of accepted connections, removal of sharing, repayment confirmation, recovery policy, and the Uncategorized behavior. Common edit/delete permissions with shared history are accepted in ADR 0005. After remaining choices are settled, promote the sync design to an ADR and scaffold a small end-to-end flow.
