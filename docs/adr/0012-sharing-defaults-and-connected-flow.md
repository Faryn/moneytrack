# ADR 0012: Sharing defaults and the connected flow

- Status: Accepted
- Date: 2026-11-01

The user accepted three proposed defaults:

- Incoming shares start in an owner-private Uncategorized category with an initial zero yearly budget. A user's existing budget choice is preserved.
- An accepted connection can be reused for subsequent shared expenses without another invitation or acceptance.
- Either participant can immediately record a full/partial repayment, visible to both without another approval.

These resolve the corresponding open questions in ADRs 0005, 0010, and 0011. Original creation is personal; sharing applies the creator's proposed share immediately. First acceptance requires a verified matching email. Two people share common expense edits/deletion/history, with independently owned categories. Settle Up records payments made elsewhere, with no budget effect or payment provider.

## Implementation contract

Add shared records alongside personal records; preserve existing outbox bytes and local data. Shared common facts use one revision, private assignments have separate revisions, and repayments are separate records. Website/API mutations commit history, participant feeds, and deduplication together. New clients use API v2 for shared records. V1 clients with shared activity receive an explicit upgrade response and retain pending work.

A pending invitation exposes only sender/recipient identity until accepted. Its recipient proves mailbox ownership through the existing verification flow; knowing an expense identifier or invitation link is insufficient. Accounts remain administrator-created. Invitation delivery uses the durable local/test mail queue; production delivery remains unconfigured.

The initial Settle Up form supports amounts up to the currently confirmed outstanding balance. Server validation rejects stale balance confirmations so two simultaneous records cannot silently settle the same displayed debt twice. Overpayment and repayment edit/delete flows are outside this implementation. Recorded repayments remain distinct from the underlying expense; shared deletion removes expense spending and its obligation without silently rewriting recorded payments. Its confirmation must show the resulting balance.

Pending invitation cancellation/decline and removal of accepted sharing are not introduced by this milestone. Common expense deletion remains available to its authorized participants, including the creator while pending.

## Subsequent budgeting extension

[ADR 0013](0013-whole-year-budget-and-guilt-free-spending.md) changes budgeting to whole-year totals and a guilt-free pool. Incoming Uncategorized shares draw from that pool unless the user allocates budget to the category; the legacy zero-budget bootstrap adds no money. New clients use [API v3](../contracts/annual-budget-v3.md), which retains these sharing operations unchanged.
