# ADR 0020: Archive unused categories

- Status: Accepted implementation for the requested ledger cleanup
- Date: 2026-11-08

The owner requested removing categories unused by the retained transactions. Categories can leave active lists once all live bookings and budget references have been cleared. Keep their IDs and labels for synchronized deletion history. The plan’s default category remains available to record spending from the unallocated pool.

The category upsert accepts an optional `archived` Boolean. Omission preserves existing state, including when a client retries a legacy operation. Archiving follows normal ownership, revision and replay checks. The server rejects new references to archived categories and requires unique names among active categories. The category feed includes `archived: true` for archived records. Clients that understand the flag hide archived categories from budget and entry lists and retain their cached records for pending edits and history. Existing category storage and prepared operations keep their original format.

This extends [ADR 0009](0009-personal-sync-contract.md) and follows the private default rule in [ADR 0013](0013-whole-year-budget-and-guilt-free-spending.md).
