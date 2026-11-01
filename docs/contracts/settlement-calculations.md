# Recorded repayment calculations

This calculation contract supports the confirmed record-only Settle Up flow in [ADR 0011](../adr/0011-record-only-settle-up.md). It is not a storage schema, permission policy, or released sync API. Shared persistence and recording screens remain unimplemented.

Use [settlement-examples.json](settlement-examples.json) in both Swift and Elixir. Each case combines exact expense shares with a sequence of recorded repayments, viewed from one participant's perspective. `paidByUser` is only a relative calculation input; a persisted repayment must identify the actual payer and recipient accounts, its calendar date, audit actor/time, revision, and operation identity.

A positive balance means the other person owes the viewer; a negative balance means the viewer owes the other person:

`balance = sum(expense balances) + sum(repayments paid by viewer) - sum(repayments received by viewer)`

Paying €15 toward a €39 debt changes −€39 to −€24. Receiving €15 toward a €39 receivable changes +€39 to +€24. The opposite participant sees exactly the opposite balance. Paying/receiving the final outstanding amount produces zero.

Expense spending is calculated only from personal shares in the expenses. A repayment changes neither participant's expense spending or budget, even when the repayment occurs in another month/year. The summary has no monthly reset or date filter: the shared ledger must supply the appropriate actual records and continue outstanding balances across January.

Input amounts are positive integer cents within the existing per-record money range. Payer/recipient determines the sign; never store a negative repayment to imply direction. Accumulate exactly; reject totals outside signed 64-bit range without rounding or wrapping. Expense and repayment input order must not change the result.

Fixtures cover both repayment directions, full and partial repayment, multiple repayments, offsetting expenses, all/none personal shares, odd-cent purchases, and the final cent. They do not choose overpayment, confirmation, or edit/delete policies. Future persistence tests must separately prove authorization, atomic recording/history/change feeds, immutable retries, duplicate prevention, tombstones, and preservation of offline data.
