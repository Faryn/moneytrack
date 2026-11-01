# Shared sync, API v2

Extends the personal operation/feed contract in [ADR 0009](../adr/0009-personal-sync-contract.md). Decisions: [ADR 0010](../adr/0010-pending-share-budget-treatment.md), [ADR 0011](../adr/0011-record-only-settle-up.md), and [ADR 0012](../adr/0012-sharing-defaults-and-connected-flow.md).

## Compatibility and transactions

New native clients use authenticated `POST/GET /api/v2/sync` for both personal and shared records. The operation's six top-level fields, operation ID/fingerprint deduplication, revision checks, account-bound cursors, frozen retry bytes, and existing personal payloads remain unchanged. Session/email endpoints remain at v1. V1 sync returns 426 for accounts with shared activity or an attempted shared mutation; it must not let an old client omit shared spending or overwrite common facts. Pending native work is retained for an updated client.

Server financial writes run through `Ledger.apply_operation`, including website actions. A transaction includes domain changes, common history, affected participant feeds, invitation/mail jobs where applicable, and the original operation result. Retrying the exact operation returns that result; reuse with altered content fails. Private category changes emit to the owner alone. Participant notifications are sent after committed financial writes.

SwiftData V3 adds generic local shared records while preserving the frozen V1 and V2 schemas, personal rows, operation state, and cursors. Existing prepared requests are never rewritten. Local common/assignment/repayment changes and their outbox entries save together. No storage-open failure resets data.

## Share a personal expense

Use entity `shared_expense`, entityID equal to the existing personal expense ID, action `upsert`, expectedRevision 0. Payload:

```json
{
  "id": "<personal-expense UUID>",
  "command": "share",
  "sourceRevision": 1,
  "recipientEmail": "person@example.org",
  "paidByCreator": true,
  "creatorSplit": "half"
}
```

Alternatively supply `recipientID` for an already accepted connection. The server checks source ownership and revision, captures its common facts, preserves the creator's private category, and retires the personal source row in the same transaction. The first invitation remains pending; reusing an accepted account pair applies sharing immediately without another invitation.

The creator's own budget uses the proposed share immediately, including offline. The native projection replaces the personal source by stable ID, so processing a shared envelope cannot double-count it or briefly omit spending across feed pages. Deleted shared records continue to suppress their original source.

The source revision is the version confirmed when sharing. If personal uploads are pending, the new proposal depends on the last source operation's acknowledgment. Preparation uses that exact acknowledged revision, even if a later peer version is already cached. Once prepared, retry bytes stay immutable. A peer source change requires review rather than silently sharing a new amount.

An invitation is delivered to the intended mailbox through durable local/test mail. Its message contains no expense amounts, private categories, or budget data. An authenticated account sees minimal `sharing_invitation` records only after verifying the matching email. Knowing/forwarding an expense identifier does not provide access. Administrator-created accounts remain required.

## Accept and reuse

Accept with entity `shared_expense`, the invitation's ID/revision, action `upsert`, payload `{"id":"<UUID>","command":"accept"}`. The authenticated account must have the exact verified normalized address and differ from the creator. A pending invitation grants no financial access before acceptance.

Acceptance establishes/reuses the canonical two-user connection, adds the recipient's owner-private assignment, records common history, and emits the common record to both users. A newly created Uncategorized category gets a zero yearly budget; existing owner choices are retained. Separate pending expenses between the same pair join that same connection when accepted. Multiple accepted connections for a pair are prohibited.

## Common facts, assignments, and history

A shared envelope contains ID, common revision, deletion state, amount, description, calendar day, immutable creation time, creator/recipient identities, canonical payer/split, pending/accepted status, minimal connection identity, shared history, and only the viewer's private assignment. `creatorSplit` is all/half/none relative to the creator, not the current viewer. Equal odd-cent splits give the extra cent to the payer.

Owner-only `bootstrapRecords` include the viewer's category/year budget so applying a new shared record is atomic even when the regular private feed did not previously contain them. Private assignment revisions are independent of common revisions. A newer or locally pending private category is preserved when a common update arrives. Neither participant receives the other's category, yearly amounts, or private assignment history.

Edit common facts with entity `shared_expense`, expected common revision, action `upsert`, payload containing id, amount, description, day, paidByCreator, creatorSplit. Both participants may edit the entire financial snapshot. Native editor state captures the revision displayed when opened; receiving a peer update while the form is open does not rebase its save silently. Stale edits retain the local draft and require explicit review. A category-only save preserves any newer common facts.

Delete using that entity/ID/revision with action `delete`. It removes spending/obligation for both and retains common history. Deleted records cannot be resurrected. Recorded repayments are independent records; deletion confirmations explain the resulting balance. Pending cancellation/decline and removal of accepted sharing are not separate actions in this version.

Change only one's category with entity `shared_assignment`, entityID equal to shared expense ID, action `upsert`, expected assignment revision, payload `{"id":"<UUID>","categoryID":"<own-category UUID>"}`. No common history/peer feed is generated.

## Record Settle Up

Use entity `repayment`, a new client UUID, action `upsert`, expectedRevision 0, with:

```json
{
  "id": "<repayment UUID>",
  "connectionID": "<accepted-connection UUID>",
  "payerID": "<actual payer account UUID>",
  "amount": 1500,
  "day": {"year":2027,"month":1,"day":1},
  "createdAt": "2027-01-01T12:00:00Z",
  "balanceAtConfirmation": 3900
}
```

The balance is signed from the authenticated actor's perspective: positive means owed to the actor. The server verifies membership, payer direction, positive cents, amount no larger than the outstanding balance, and the exact balance confirmed. Stale balance confirmation is rejected; retries of a committed operation remain harmless. Either participant can record immediately without another approval.

The native form prefills the full amount, accepts partial amounts, previews the remaining balance, and states that it only records payment made elsewhere. It saves locally/offline with the outbox. A rejected draft remains for review; discarding it removes only the uncommitted local record, after which the user can review the current balance and record again. Neither budget nor expense shares change. Repayments and balances carry across January.

Responses/feeds contain actual payer, recipient, actor, calendar date, audit time, minimal connection identity, and amount. There is no payment provider or movement of money. Repayment editing/deletion and overpayments are not exposed in this version.

## Verification

Common [split](shared-expense-examples.json) and [repayment](settlement-examples.json) fixtures run in Swift/Elixir. Context/website tests cover verified acceptance, immediate pending budgets, account isolation, private categories, common conflicts, reuse, partial/full repayment, duplicate operations, shared deletion, and rollback. Native migration/persistence tests cover populated V2 upgrade, exact prepared bytes, failed saves, frozen source dependencies, and stale editors. The isolated connected check exercises two accounts through the actual native transport, plus native sharing/partial-repayment UI.
