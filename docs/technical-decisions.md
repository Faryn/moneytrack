# Technical decision backlog

Status: open decisions and proposed recommendations, with accepted choices identified below. Product behavior remains defined by [SPEC.md](../SPEC.md). The repository and server boundaries are accepted in [ADR 0001](adr/0001-single-repository-and-combined-server.md); application-owned authentication and server SQLite are accepted in [ADR 0002](adr/0002-own-authentication-and-sqlite-backend.md); Phoenix is accepted in [ADR 0003](adr/0003-phoenix-server.md).

Username/password with optional passkeys is accepted in [ADR 0004](adr/0004-password-login-and-passkeys.md). Shared visibility, email invitations, mutual expense edit/delete access, and private categories are accepted in [ADR 0005](adr/0005-shared-expenses-and-email-invitations.md).

Negative carryover and whole-year recalculation after budget edits are confirmed in [ADR 0006](adr/0006-calendar-year-budget-calculation.md). SwiftData is selected after the local prototype in [ADR 0007](adr/0007-swiftdata-local-store-and-outbox.md). iOS leads the UX using Apple HIG and standard SwiftUI components.

Administrator-created accounts and ordinary server-readable storage with HTTPS are now confirmed in [ADR 0008](adr/0008-connected-accounts-and-transport.md). The first personal sync implementation is selected in [ADR 0009](adr/0009-personal-sync-contract.md); the shared subset is now implemented in ADR 0012 and the v2 contract.

Settle Up is confirmed in [ADR 0011](adr/0011-record-only-settle-up.md): ask for an editable full/partial amount and record a repayment without moving money or changing budgets. ADR 0010 already confirms immediate application of a proposed personal share while an invitation is pending.

The three sharing defaults are now accepted in [ADR 0012](adr/0012-sharing-defaults-and-connected-flow.md): incoming private Uncategorized, accepted-connection reuse, and immediate repayment recording by either participant. The [shared v2 contract](contracts/shared-sync-v2.md) describes the implementation.

## Proposed MVP defaults awaiting confirmation

These recommendations were discussed but have not been explicitly accepted. Repository preparation does not promote them into requirements.

| Choice | Proposed default |
| --- | --- |
| Password recovery | Use verified email for password resets, retaining username login. |

EUR-only operation, interface languages, the exact online website scope, and removal of an accepted share also remain marked assumptions/open choices. See [implementation milestones](development.md) for the proposed build order.

## Decide before implementing persistence and sync

### 1. Data ownership and shared-expense identity

Accepted in [ADR 0005](adr/0005-shared-expenses-and-email-invitations.md): both participating users can see the common shared expense after a direct email invitation is accepted. No contact-management feature or non-account placeholder debtors. Keep personal categories and budgets private; each participant categorizes their own share. Invitation acceptance must bind the intended email identity to an authenticated account, without changing username/password login.

Accepted: either participant can edit common expense fields or delete the shared expense, with history visible to both. Only an assignment's owner can edit it, and private categories and budgets stay out of shared history. The [data model and sync proposal](data-model-and-sync.md) covers records, invitation states, history storage, and per-user change feeds. [ADR 0010](adr/0010-pending-share-budget-treatment.md) confirms immediate application of the proposed personal share to the creator's budget, including while an invitation is pending. ADR 0012 accepts connection reuse and immediate repayment recording. Cancellation/decline effects, removing sharing, and repayment corrections remain outside this version.

Email ownership verification is implemented on iOS and web with expiring account-bound codes, a durable encrypted mail queue, and local/test delivery. See the [verification contract](contracts/email-verification-v1.md). This does not decide account recovery or invitation onboarding. Pending-invitation budgeting is now confirmed in ADR 0010. ADR 0012 confirms the recipient's initial private category and reuse of accepted connections. Shared records and repayments now use the v2 sync contract.

### 2. Financial data and calendar contract

Personal budget calculation, negative rollover, yearly edits, and deterministic monthly cent allocation are defined in ADR 0006 and exercised in Swift/Elixir with the same fixture. Settle Up recording is confirmed in ADR 0011, and the [repayment examples](contracts/settlement-examples.json) exercise both directions, full/partial amounts, and unchanged expense spending in Swift/Elixir. Finalize server expense, split, repayment, and private-assignment representations, including the effect of deleting a settled shared expense.

Recommendation: integer minor currency units, explicit currency, client-generated UUIDs, and an explicit calendar expense date separate from UTC creation/modification timestamps. Travel and server timezones must not move an expense into another month. Calculate remaining budgets and debts from underlying records rather than syncing editable running totals.

Budget examples and [shared split examples](contracts/shared-expense-examples.json) now run in Swift and Elixir. The latter verify all/half/none, opposite balances, and payer-assigned odd cents. Shared deletion/repayment correction examples follow after those policies are settled. Run those same examples against Swift and server calculations to prevent differences between offline and website results.

### 3. Offline storage and sync protocol

Selected: a versioned SwiftData store explicitly saves a domain mutation and its pending operations together. Disk reopening, edit/delete tombstones, profile isolation, and rollback after a read-only store refuses a save are tested. See [local storage](local-storage.md).

Implemented: SwiftData V2 migration, immutable prepared requests, acknowledgments, private cursors, cached revisions, conflict review, and explicit one-time copying into an empty account. V1 records and pending bytes survive migration. Account/server namespaces and Keychain prevent cross-account submission. SwiftData V3 adds shared records and tests populated V2 migration while retaining prepared bytes. Merging two populated ledgers remains separate work.

Use the custom backend as the shared sync service. The [draft protocol](data-model-and-sync.md) proposes client-generated operation IDs for safe retries, server-issued record revisions, per-user resumable change cursors, deletion/access-removal markers, and a full resync path that preserves pending local work. An offline device that returns after deletion-marker cleanup must not recreate deleted records. Shared writes must update both participants' feeds while exposing private assignments only to their owner.

Check the record's expected revision before accepting an edit. Retain both versions on a conflict and let the user resolve it; avoid automatically combining an expense amount from one edit with a split from another. The detailed conflict UI and handling of repeated local edits must be specified.

Start synchronization on app launch/foreground, local changes, and manual refresh. Background refresh is an optimization; do not make successful delivery depend on it. Expired authentication must preserve queued changes, and local stores must remain isolated when switching users.

### 4. Server stack and database

Accepted: Phoenix/Elixir for the combined website and JSON sync API, Phoenix LiveView for the website, and Ecto with the SQLite adapter for server persistence. The application operates its own accounts and storage backend. Deploy on one host with a persistent local database directory, short write transactions, consistent backups, and no direct client access to the database file. CloudKit is not selected.

The personal sync endpoints and device authentication are now implemented. Shared-expense and repayment sync are now implemented in v2. Verify the Ecto SQLite transaction and connection configuration against concurrent website writes and sync requests during setup.

Keep website and API writes in the same application services so validation, versioning, and change tracking cannot diverge. Select supported framework/runtime versions during setup and record dependency versions then.

### 5. Authentication and privacy boundary

Accepted in [ADR 0004](adr/0004-password-login-and-passkeys.md): username/password login with optional passkeys as an alternative login method on both iOS and the website, using the same application-owned accounts. Passkeys are not a required second factor, and Sign in with Apple is not selected. Native Authentication Services and web WebAuthn use the same relying party identity and server-side credential verification.

Selected in ADR 0008: administrator-created accounts, ASCII/case-normalized usernames, bcrypt, Hammer, 30-day hashed/revocable sessions, native Keychain credentials, HTTPS, and ordinary server-readable storage. Still to decide: recovery and recovery email, stable domain/relying party ID, production credential management, and invitation onboarding.

Implemented: separate browser/device sessions, scoped authorization, TLS requirements, and parameter-log filtering. Production backup encryption/restoration and release account operations still need configuration. End-to-end encryption is not required by the user.

## Decide before the first usable release

### 6. API compatibility and migrations

Recommendation: a documented, versioned JSON API with additive changes where possible. Define which released iOS versions the server supports and how unsupported clients retain pending local data. Provide forward migrations for local and server storage, with migration verification using existing data.

### 7. Hosting, backup, and recovery

Choose self-hosting versus a managed service, a domain, and who operates it. Use one application deployment with SQLite on persistent host-local storage. Plan WAL mode with full commit durability, verify a patched runtime at setup, and configure foreign keys and bounded lock waits. Use SQLite-aware automated encrypted backups stored separately and a verified restore procedure. Define acceptable data loss and recovery time. Decide export format and how users recover changes that have not yet synced.

### 8. Distribution and delivery checks

Choose initial iOS distribution and the exact supported stable iOS/Xcode versions at setup. TestFlight is a candidate for early testing, but a continuing release/distribution plan must also be selected.

Run iOS checks on macOS and server checks on a suitable runner. Prioritize shared financial examples, user isolation, repeated sync requests, edit/delete conflicts, migrations, and offline recovery. Server deployment and iOS releases remain separate workflows within the repository.

## Can wait

Natural-language parsing, model selection, push-driven sync, receipt storage, shared budgets, additional currencies, and extra Apple platforms can be decided after form entry and reliable synchronization work. Initial category suggestions can use local expense history without an AI dependency.

## References

- [Apple: SwiftData](https://developer.apple.com/documentation/swiftdata/) documents local persistence and SwiftUI integration; custom-backend synchronization is a separate design responsibility.
- [HTTP Semantics, section 13.1.1](https://www.rfc-editor.org/rfc/rfc9110.html#section-13.1.1) describes conditional writes with `If-Match` to prevent lost updates. This supports revision checking but is not a complete sync protocol.
- [Phoenix installation](https://hexdocs.pm/phoenix/installation.html) documents the server toolchain and SQLite database option.
- [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view/welcome.html) documents interactive server-rendered website behavior.
- [SQLite: appropriate uses](https://www.sqlite.org/whentouse.html) describes SQLite for websites and application servers.
- [SQLite: write-ahead logging](https://www.sqlite.org/wal.html) documents concurrency, host-local storage requirements, and durability settings.
- [SQLite: online backup](https://www.sqlite.org/backup.html) documents consistent database backup facilities; recovery and backup policy still need operational decisions.
