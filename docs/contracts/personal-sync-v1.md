# Personal sync API v1

Base URL: the server origin, using HTTPS in production. Responses use JSON and `Cache-Control: no-store`. This contract supports private personal records only; EUR amounts are integer cents. It does not implement shared expenses or invitations.

## Sessions

`POST /api/v1/sessions`:

```json
{"username":"example","password":"<password>","deviceName":"iPhone"}
```

The response includes `user: {id, username}`, `token`, and `expiresAt`. Keep the token in Keychain. Send `Authorization: Bearer <token>` for subsequent calls. `GET /api/v1/session` checks the identity; `DELETE /api/v1/session` revokes that device session. Browser cookies are separate credentials and cannot authorize these routes. Accounts are created administratively, not through this API.

## Push one operation

`POST /api/v1/sync`, for example:

```json
{
  "operationID":"10000000-0000-4000-8000-000000000001",
  "entity":"category",
  "entityID":"20000000-0000-4000-8000-000000000001",
  "action":"upsert",
  "expectedRevision":0,
  "payload":{"id":"20000000-0000-4000-8000-000000000001","name":"Restaurants"}
}
```

All six envelope fields are required. Reject unknown fields, including actor/owner IDs. `payload.id` must match `entityID`. A new record uses revision zero; an edit/delete uses its last acknowledged revision. Prepare and persist the entire request before sending, then retry the same operation and content after a timeout. Do not regenerate its operation UUID or silently rebase it. Deduplication is scoped to the account and survives session renewal.

Allowed payloads:

| Entity/action | Payload |
| --- | --- |
| `category` / `upsert` | `id`, `name` (1–100 characters) |
| `year_budget` / `upsert` | `id`, `categoryID`, `year` (1900–9999), `amount` (nonnegative cents) |
| `expense` / `upsert` | `id`, `categoryID`, `amount` (positive cents), `personalShare` (equal to amount in this slice), `description` (up to 500 characters), `day: {year, month, day}`, `createdAt` (ISO 8601 UTC) |
| `expense` / `delete` | `id`, `deletedAt` (client timestamp; the server records its own deletion time) |

The maximum money value is 99,999,999,999 cents. All category references must belong to the authenticated account. A yearly budget's category/year and an expense's client creation timestamp do not change on editing. Client timestamps are canonicalized to seconds; server audit timestamps are recorded separately. Expense calendar days never derive from timestamp timezones.

A successful response is `{"record": <record>}`. Every record has:

```json
{
  "entity":"category",
  "entityID":"20000000-0000-4000-8000-000000000001",
  "revision":1,
  "deleted":false,
  "payload":{"id":"20000000-0000-4000-8000-000000000001","name":"Restaurants"}
}
```

Deletion returns a tombstoned expense with its existing payload and a newer revision. It cannot be resurrected by an update. Explicitly keeping an edited item deleted elsewhere creates a new expense ID.

## Pull

`GET /api/v1/sync` starts catch-up; later requests add `?cursor=<opaque cursor>`. A response has `changes` (record envelopes), `cursor`, and `hasMore`. Pages contain up to 100 owner-visible changes. Apply a page and its cursor in one local save. Replay is harmless. Pending local edits remain visible and are not overwritten.

Cursors are signed, account-bound, and based on a private per-user sequence. Pagination freezes its upper boundary; later writes appear in the next catch-up cycle. Keep deletion and operation history for this MVP. An invalid cursor restarts catch-up without clearing local data or pending requests. Never use a client clock as a cursor.

## Errors and review

- `401`: credential invalid/expired. Preserve the local store and queue; sign in again.
- `409 revision_conflict`: `current` contains the server record. Preserve both versions and ask the user to choose. Concurrent creation of the same category/year can return the canonical budget with a different ID; resolve to that record rather than creating two budgets.
- `409 operation_reused`: the operation UUID was reused with different content; do not retry modified content under that UUID.
- `404`: an item or category is unavailable to this account. No foreign payload is returned.
- `422`: invalid fields/constraints. Preserve the change for correction and explicit retry; duplicate category names can be renamed.
- `400 invalid_cursor`: restart the retained feed, preserving local work.
- `429`: login throttling; respect `Retry-After`.

Server errors and transport failures leave the exact prepared request pending. A lost success response may have committed; retrying must return its original result without a second financial effect. Future API migrations must preserve and route existing prepared v1 requests rather than treating them as a new protocol.

## Subsequent API versions

[API v2](shared-sync-v2.md) adds shared records; [API v3](annual-budget-v3.md) adds whole-year budgets and guilt-free spending. Current native clients use v3. V1/V2 sync returns 426 when an account has a whole-year plan, preserving pending work for upgrade. The original personal payloads remain accepted through v3 subject to the new per-year legacy-budget guard.

## Personal income extension

[ADR 0019](../adr/0019-personal-income-bookings.md) adds `/api/v5/sync` with the existing operation envelope and optional `kind` on personal expense payloads. Values are `expense` or `income`; absent means expense. Income retains positive exact cents and personalShare equal to amount, but consumes no budget. Income is private and cannot be shared. Updates to existing income require explicit kind. V1–v4 return 426 for accounts with any income history or income submissions. Existing prepared expense operations remain accepted unchanged by v5.
