# ADR 0010: Apply proposed shares to budgets immediately

- Status: Accepted
- Date: 2026-11-01

## Context

ADR 0005 requires personal-share budgeting and recipient acceptance before shared access. The earlier draft proposed leaving an expense fully personal until acceptance. The user chose to apply the proposed split immediately instead.

## Decision

- Applying a sharing proposal immediately changes the creator's budget consumption to their proposed personal share, including while an invitation is pending.
- This follows the original expense's calendar date and the established all/half/none and odd-cent rules.
- The local budget must reflect the proposed share even before the queued invitation reaches the server.
- Acceptance still establishes the common record visible to both authenticated participants; a pending invitation does not grant the recipient access.

For example, a €78 personal expense against €500 leaves €422. Applying a half split changes the creator's remaining budget to €461 while acceptance is pending.

## Consequences and remaining questions

The pending proposal becomes relevant financial state and must be persisted and synchronized with revision checks. It cannot be represented only as an email awaiting delivery. Preserve the distinction between pending and accepted sharing in the UI.

This ADR supersedes the draft recommendation to count the full amount until acceptance. It does not choose the recipient's initial private category, reuse of an accepted connection, invitation lifetime, cancellation/decline effects, removal of accepted sharing, or repayment rules. Those remain open. In particular, do not infer an irreversible settlement or confirmed debt from mailbox verification alone.

## Subsequent decision

[ADR 0011](0011-record-only-settle-up.md) confirms record-only Settle Up and full/partial repayments. Its acknowledgment/correction policies remain open independently of pending-share budgeting.
