# ADR 0006: Calendar-year budget calculation

- Status: Accepted
- Date: 2026-11-01

## Context

The user confirmed both previously proposed rules: overspending reduces the following month's available budget, and editing a yearly budget recalculates that entire calendar year. iOS and the website must produce identical balances, including rounding.

## Decision

- Store yearly category amounts and expense shares in integer cents.
- Divide a yearly amount by twelve using integer division. Allocate one extra cent to each of the first remainder months, starting in January. The twelve allocations sum exactly to the yearly amount.
- A month's available budget is its allocation plus the previous month's remaining balance. Subtract personal-share spending dated in that month to calculate remaining budget.
- Carry both positive and negative remaining balances into subsequent months of the same year.
- January starts with zero carryover. Prior-year expenses and interpersonal debts remain recorded; debts do not reset.
- Editing a yearly amount recalculates every month of that calendar year. The UI confirms this effect before saving an existing amount change. Recorded expenses remain unchanged.
- Backdated edits, deletions, and category changes recalculate balances from the underlying records. Future-month expenses do not reduce an earlier month's remaining budget.
- Use a calendar expense date independent of audit timestamps and timezone conversions.

## Consequences

For a €1,200 yearly budget, January allocates €100. Spending €150 leaves −€50, so February starts with €50 available. Changing the yearly amount to €2,400 makes January's allocation €200 and February's available budget €250, with the same €150 expense.

Use the same [synthetic examples](../contracts/budget-examples.json) in Swift and Elixir tests. The fixture covers carryover, overspending, personal shares, January reset, exact-cent rounding, future expenses, and yearly edits. It is a calculation contract, not a sync API.

## Subsequent decision

[ADR 0013](0013-whole-year-budget-and-guilt-free-spending.md) changes setup to a whole-year total followed by category allocations and guilt-free spending. It supersedes independent rounding for whole-year plans with joint allocation so the monthly parts equal the total. Carryover, calendar-year recalculation, and January reset remain. Legacy category-only records retain the calculation above until explicit conversion.
