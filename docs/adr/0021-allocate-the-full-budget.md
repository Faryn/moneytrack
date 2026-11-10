# ADR 0021: Allocate the full budget

- Status: Accepted
- Date: 2026-11-08

The user wants Spendie to help allocate the whole yearly budget. Yearly Plan shows the amount available to assign and marks a fully allocated plan. Partial plans can be saved during setup. Budget home links directly to allocation while money remains unallocated.

Unallocated equals the yearly total less category allocations. It never funds spending. The overall monthly balance uses only assigned monthly amounts and subtracts all personal-share spending. Spending without a category allocation is shown separately. It reduces the overall balance and never reduces the unallocated amount or another category’s balance. Category and overall carryover reset in January.

Keep the joint exact-cent schedule from [ADR 0013](0013-whole-year-budget-and-guilt-free-spending.md), treating the unallocated schedule as a rounding reserve. Keep the existing `freeCategoryID` field for the private Uncategorized category. Existing plans, category IDs, and queued wire operations use the same format. Both clients display a reserved fallback as Uncategorized.

This supersedes the spending pool in ADR 0013. The [annual plan examples](../contracts/annual-plan-examples.json) cover rounding, carryover, spending without a budget, and a fully allocated plan in both implementations.
