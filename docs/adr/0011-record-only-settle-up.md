# ADR 0011: Record-only Settle Up

- Status: Accepted
- Date: 2026-11-01

## Context

Shared expenses need a way to reduce or clear the amount owed between two people. The user requested a Splitwise-style Settle Up action that asks for the amount to record, with no payment inside MoneyTrack.

## Decision

- Include Settle Up in the shared-person balance screen.
- Ask for the repayment amount; allow recording a partial repayment or the full outstanding amount. Prefill the current outstanding amount as an editable suggestion.
- Clearly show who paid whom before the user records the repayment. A received repayment and an outgoing repayment must have opposite balance effects.
- Record a repayment separately from expenses. It changes the balance between those two people only; it does not create spending, income, or budget allocation and does not change expense shares.
- Show the recorded repayment in the pair's shared activity, so the balance can be explained by expenses and repayments.
- MoneyTrack only records a payment made outside the app. Do not initiate payments, collect payment credentials, or integrate a payment provider.
- Keep exact cents, calendar repayment dates, UTC audit times, offline persistence, safe retries, and account-scoped access consistent with the existing ledger requirements. Repayments and outstanding balances do not reset on January 1.

For example, someone owes you €39. Recording €15 received leaves €24 owed to you; recording the remaining €24 clears the balance. Your expense spending and remaining budget are unchanged throughout.

## Implementation boundary and open policies

This decision confirms repayment recording and its financial meaning. It does not automatically accept all repayment recommendations in the draft data model. In particular, whether the other participant must acknowledge a record, who may edit/delete a repayment, and handling amounts above the outstanding balance remain open. Expense deletion's effect on separately recorded repayments is also still a draft policy.

The shared persistence/API and real person screens are not implemented yet. The [common Swift/Elixir calculation contract](../contracts/settlement-calculations.md) now covers full/partial repayments in both directions and their separation from expense spending. Implement the real recording action with the shared ledger, including atomic history/feed updates, preserved offline records, conflict handling, and duplicate-safe synchronization. Do not expose a save action that only appears to record a repayment.
