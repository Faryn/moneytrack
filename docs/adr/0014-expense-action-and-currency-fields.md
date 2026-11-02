# ADR 0014: Compact expense action and consistent currency fields

- Status: Accepted
- Date: 2026-11-02

The user refined the entry flow: replace the large add button with a compact floating plus, visible only on Expenses. They also requested currency identification, aligned amounts, correct decimal places, and explicit split/repayment verification. The conveniently located keyboard action should save an expense rather than merely dismissing the keyboard.

## Decision

- Expenses has a trailing circular plus above the tab bar, with an accessible Add Expense label. Budget and Shared have no add action. Retain native animation/haptics and Reduce Motion support.
- Keep the standard top Save button and make the keyboard action Save Expense, calling the same validation and save method. Saving never requires dismissing the keyboard first.
- Use a common native currency field for personal/shared expense amounts, annual totals, category allocations, and repayments. Show EUR, align the editable amount to the trailing edge, use the decimal keyboard, and normalize valid input to exactly two decimal places when focus leaves. Invalid or overprecise input stays visible for correction; never silently round it.
- The website uses the same currency identification, trailing numeric alignment, decimal entry, and two-place normalization after editing. Keep exact string/integer parsing; do not introduce binary floating-point calculations.
- Currency display uses two fractional digits. Locale controls separators and currency presentation; the current implementation remains EUR.
- Verify split conservation, payer-owned odd cents, opposite participant balances, partial/full repayment in both directions, budget neutrality, invalid amounts, overpayments, stale confirmations, and duplicate-safe retries in Swift and Elixir tests.

This supersedes only the large all-tab expense action in [ADR 0013](0013-whole-year-budget-and-guilt-free-spending.md). Whole-year budget and guilt-free pool rules remain unchanged. Splitting and record-only settlement retain [ADR 0012](0012-sharing-defaults-and-connected-flow.md).
