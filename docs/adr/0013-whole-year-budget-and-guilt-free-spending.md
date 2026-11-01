# ADR 0013: Whole-year budget first, then category allocations

- Status: Accepted
- Date: 2026-11-01

The user changed budgeting to start with one yearly total, then allocate parts to categories. The unassigned part is guilt-free spending. They confirmed that spending in categories without allocations, including uncategorized spending, draws from one guilt-free pool. Overspending in an allocated category remains with that category and reduces the overall balance; it does not automatically consume the guilt-free pool.

## Decision

- Set one private total for each calendar year before assigning category amounts.
- Category allocations are parts of that total, not additional budget. Their sum cannot exceed it.
- Guilt-free yearly budget is total minus allocated yearly amounts. Categories without a positive allocation use this pool.
- Overall monthly remaining uses the whole budget minus all personal-share spending. Category and guilt-free remaining values explain that same total, without double-counting.
- Preserve January reset, positive/negative carryover, original expense dates, personal shares, and whole-year recalculation after changes. Repayments remain budget-neutral.
- Divide the yearly total into exact monthly cents. Allocate category and guilt-free cents jointly so monthly parts always equal that month's total and yearly parts equal their annual amounts. Stable category-ID ordering distributes remainder cents into month slots with the most remaining capacity, with earlier months breaking ties; guilt-free is last. This supersedes independent rounding when a whole-year plan exists.
- Save total and allocations as one versioned financial record. Conflicting edits require review. Native changes and outbox save atomically; use a forward migration and preserve prepared older requests.
- Preserve existing category-only budgets as a legacy plan until the user saves a whole-year plan. Prefill from their existing yearly sums; do not invent extra money or discard expense history.
- Keep category labels separate from funding. An owner-private default category supports quick uncategorized entry without a mandatory setup detour.

## UX

Yearly Plan starts with the total and shows Allocated and Guilt-free amounts, followed by category allocation navigation. Budget home leads with overall monthly remaining, shows guilt-free spending explicitly, and keeps category detail navigation. Unallocated categories show that they use the guilt-free pool rather than false zero-budget overspending.

Add Expense becomes a large bottom action above the native tab bar. Use subtle system animation and haptics; respect Reduce Motion. Standard SwiftUI forms, sheets, lists, colors, and Dynamic Type remain the design baseline.

Implementation and compatibility: [API v3](../contracts/annual-budget-v3.md), [shared calculation examples](../contracts/annual-plan-examples.json), and [local storage](../local-storage.md). This supersedes category-first setup and independent rounding in ADR 0006 for whole-year plans; earlier records retain their legacy behavior until explicitly converted.
