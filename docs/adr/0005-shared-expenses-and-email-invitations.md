# ADR 0005: Shared expense records and email invitations

- Status: Accepted
- Date: 2026-11-01

## Context

Shared expenses are intended to work between MoneyTrack users, rather than exist only as private debt records. The product does not need a separate contact management feature.

## Decision

- An expense is personal when created and can be shared afterward through its action menu.
- Both participating users can see the same shared expense after invitation acceptance. They do not maintain independent copies of its amount, payer, or split.
- Invite the other person directly by email. A recipient without an account can create one before accepting.
- Do not build a manual contact list or support non-account placeholder debtors in the MVP. Counterparties and balance views come from actual sharing relationships.
- Each user's budget counts only that user's share. Personal categories and budget amounts remain private; each participant categorizes their own share.
- Keep the two-person 100/0, 50/50, and 0/100 splits already specified.
- Either accepted participant may edit common expense fields or delete the shared expense. Record who changed what and when in a history visible to both participants.
- Only the owner may edit their personal category assignment. Shared history must not expose private category assignments or budgets.
- Bind invitation acceptance to an authenticated account that proves control of the invited email address. Username/password and optional passkey login remain the selected authentication methods; email invitations do not replace them.
- Queue an invitation request created offline and deliver it through the server after synchronization. This decision authorizes implementation of invitation delivery, not sending any invitations during specification work.

## Consequences

- The schema and API need participant-based access alongside private per-user data.
- A common expense revision must produce consistent budget and debt effects for both participants.
- Shared edits and deletions must update both users' financial results and shared history together. Concurrent edits still require revision checks and conflict handling.
- The server needs invitation delivery and acceptance flows, including account onboarding when necessary.
- The system must distinguish email used for invitation identity from the username used to sign in. Password recovery by email is still a separate decision.
- Contact-only tracking is outside the MVP.

## Not decided here

Removal of sharing, pending invitation budget treatment, invitation lifetime, reuse of an accepted sharing relationship, and repayment confirmation are proposed in the [data model and sync proposal](../data-model-and-sync.md). They are not accepted by this ADR. Shared edit/delete permissions and private assignment ownership are accepted above.

## Subsequent decisions

[ADR 0008](0008-connected-accounts-and-transport.md) selects administrator-created accounts for now; invitation-led account onboarding follows later. [ADR 0010](0010-pending-share-budget-treatment.md) resolves pending budget treatment: apply the creator's proposed share immediately, rather than waiting for acceptance. Other open sharing policies remain pending.

[ADR 0011](0011-record-only-settle-up.md) confirms full/partial repayment recording through Settle Up, with no payment processing or budget impact. Repayment acknowledgment and correction permissions remain open.
