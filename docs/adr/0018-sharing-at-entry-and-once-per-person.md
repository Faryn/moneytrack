# ADR 0018: Accept a person once and share during entry

- Status: Accepted
- Date: 2026-11-04

## Decision

The first email invitation establishes a two-account sharing connection when accepted by the verified recipient. Acceptance covers current pending expenses between those accounts as well as future shared expenses. No additional expense-by-expense acceptance is required. Pending expenses in both directions are released only when the corresponding recipient address belongs to the connected account; deleted expenses remain deleted. Both participants retain the existing shared edit/delete permissions and history, with private categories.

Once connected, a person can be selected by name in expense entry. Quick Entry recognizes a suffix such as `5€ rewe shared with saskia` or `5€ rewe geteilt mit Saskia`. Match only accepted local connections, case/diacritic-insensitively. An unambiguous first name or exact full display name is sufficient. Unknown, missing, or ambiguous names block quick save; they must never silently turn a sharing request into a personal expense. Initial sharing with an unknown person still uses their email through a saved expense's Share action.

The compact preview identifies the selected person and personal budget share. The default is an equal split with the entering user as payer. The full form allows changing payer and the supported all/half/none split. EUR conversion happens before splitting, and the payer owns any odd cent.

## Implementation

Native entry saves the personal source, optional fallback category, common shared draft and both outbox operations in one SwiftData transaction. The existing immutable source-acknowledgment dependency connects the sharing request to the exact uploaded source revision. Reopening and retrying retain the original operations. A failed save leaves neither a partial personal expense nor a partial sharing request.

Website creation routes both operations through one ledger context transaction and uses a stable derived sharing operation ID for harmless retries. Notifications follow the outer commit. The backend authorizes recipient account IDs against accepted connections; names are a client convenience, not authorization credentials or a global account search.

Acceptance updates all eligible pending common records, histories, private receiver assignments and both feeds atomically. A stale acceptance of a record already accepted through the same connection is harmless. No pending financial fields become visible before acceptance.

This extends [ADR 0012](0012-sharing-defaults-and-connected-flow.md) and supersedes the personal-creation-only restriction in [ADR 0005](0005-shared-expenses-and-email-invitations.md). Personal remains the default. No contact manager, groups, arbitrary splits or payment handling are introduced.
