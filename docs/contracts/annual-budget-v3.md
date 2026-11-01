# Whole-year budget sync, API v3

Implements [ADR 0013](../adr/0013-whole-year-budget-and-guilt-free-spending.md). Extends the [personal v1](personal-sync-v1.md) and [shared v2](shared-sync-v2.md) contracts without changing their operation payloads or authorization.

## Version and ownership

Current native clients use authenticated `POST/GET /api/v3/sync` for all ledger records. Session and email endpoints remain v1. The six-field operation envelope, account-scoped deduplication, immutable prepared requests, revision checks, private cursors, and atomic feed application remain unchanged. Whole-year plans appear only in their owner's feed, never a sharing partner's bootstrap records or history.

V1/V2 sync returns 426 when an account has a whole-year plan or attempts to submit one. An old client must preserve local work and upgrade. Existing prepared personal/shared operations can be sent unchanged through v3. A legacy `year_budget` write for a year already governed by a whole plan returns a validation issue; the updated client requires explicit review/discard, rather than silently changing its bytes or overriding the plan. Legacy records for other years remain writable through their existing contract.

## Plan operation

`budget_plan` supports `upsert`, not deletion. Example payload:

```json
{
  "id": "10000000-0000-4000-8000-000000000001",
  "year": 2026,
  "total": 120000,
  "freeCategoryID": "20000000-0000-4000-8000-000000000001",
  "allocations": [
    {"categoryID": "20000000-0000-4000-8000-000000000002", "amount": 60000}
  ]
}
```

All money is integer EUR cents. Total can be zero and cannot exceed 99,999,999,999 cents. Year is 1900–9999 and immutable. Each allocation is positive, unique by category, and references an owner-private category other than `freeCategoryID`. Their sum cannot exceed the total. Zero allocation is represented by absence. The free category is an owner-private default for uncategorized entry, not an allocation and not a second budget. The response sorts allocations by category UUID.

There is one plan per owner/year. Total, free category, and allocations share one revision and commit with their change event and operation result in one transaction. Stale edits return the full current private plan for review. Concurrent creation for the same year returns the canonical record, including its potentially different UUID. Choosing Keep My Plan explicitly submits a new operation against that displayed canonical revision; a later conflict requires another review.

## Calculation

Annual guilt-free amount equals total minus allocated amounts. All expenses whose private category lacks a positive allocation draw from that single pool. Only personal shares count, using original calendar dates. Allocated-category overspending stays with that category and reduces overall remaining; it does not consume guilt-free budget. Repayments remain budget-neutral.

For each month, calculate allocation plus prior remaining minus spending, separately for total, allocated categories, and the guilt-free pool. Carry both signs within the year; January has zero carryover. Editing a plan recalculates its whole calendar year. The category remaining amounts plus the guilt-free remaining equal overall remaining. Unallocated category rows display pool membership and their own spending; do not add independent zero-budget deficits for them.

Monthly rounding is joint:

1. Divide total cents by twelve, giving one extra cent to each of the first remainder months.
2. Divide each category's annual amount and the guilt-free amount by twelve for their base monthly amounts. Subtract the sum of these bases from each month's total to obtain available cent capacity.
3. Visit categories in UUID order, then guilt-free last. For a part's remainder, choose that many distinct months with the most remaining capacity; break ties by earlier month. Add a cent in each chosen month and reduce capacity.

This preserves annual amounts, gives each part either its base or base plus one cent per month, and makes every month's parts exactly match its total. Always choosing the earliest available month fails for 24 cents split into three 8-cent parts. Shared [examples](annual-plan-examples.json) exercise that case along with carryover, allocated overspending, pooled categories, personal shares, future expenses, and January reset in both Swift and Elixir.

## Migration and local saving

SwiftData V4 adds annual plan records, leaving V1/V2/V3 models frozen. Populated migration tests preserve expenses, legacy budgets, pending IDs/payloads, and exact prepared bytes. No store-open failure clears local data.

An existing category-only year remains on the legacy calculation until the user explicitly saves a whole-year plan. Setup prefills its existing annual sum and category allocations; it does not invent extra spending money. Subsequent whole-plan calculations ignore legacy budgets for that year. If Uncategorized already has an allocation, conversion chooses a distinct private default category for guilt-free entry.

Native domain changes, newly needed categories, and outbox operations save together or roll back together. Expense entry without a category uses the private default, keeping the expense's concrete category reference compatible with older payloads. A one-time copy into an empty account remaps plan/default/allocation references and preserves the original store. Acknowledging an unchanged locally displayed plan may advance its editor's base revision; a different peer payload never silently rebases the edit.
