# Technical decision backlog

Status: open decisions and proposed recommendations, with accepted choices identified below. Product behavior remains defined by [SPEC.md](../SPEC.md). The repository and server boundaries are accepted in [ADR 0001](adr/0001-single-repository-and-combined-server.md); application-owned authentication and server SQLite are accepted in [ADR 0002](adr/0002-own-authentication-and-sqlite-backend.md); Phoenix is accepted in [ADR 0003](adr/0003-phoenix-server.md).

Username/password with optional passkeys is accepted in [ADR 0004](adr/0004-password-login-and-passkeys.md). Shared visibility, email invitations, mutual expense edit/delete access, and private categories are accepted in [ADR 0005](adr/0005-shared-expenses-and-email-invitations.md).

## Proposed MVP defaults awaiting confirmation

These recommendations were discussed but have not been explicitly accepted. Repository preparation does not promote them into requirements.

| Choice | Proposed default |
| --- | --- |
| Overspending | Carry negative category balances into the next month within the same year. |
| Yearly budget edits | Recalculate the whole affected year, showing the effect before saving. |
| Pending sharing | Keep the expense personal until the first invitation is accepted. |
| Subsequent sharing | Reuse an accepted sharing connection without another email invitation. |
| Incoming category | Assign the user's share to a private zero-budget Uncategorized category until they choose another. Count it immediately in total spending. |
| Repayment recording | Either participant may record full/partial repayment, with shared history and no second confirmation. |
| Password recovery | Use verified email for password resets, retaining username login. |

EUR-only operation, interface languages, the exact online website scope, and removal of an accepted share also remain marked assumptions/open choices. See [implementation milestones](development.md) for the proposed build order.

## Decide before implementing persistence and sync

### 1. Data ownership and shared-expense identity

Accepted in [ADR 0005](adr/0005-shared-expenses-and-email-invitations.md): both participating users can see the common shared expense after a direct email invitation is accepted. No contact-management feature or non-account placeholder debtors. Keep personal categories and budgets private; each participant categorizes their own share. Invitation acceptance must bind the intended email identity to an authenticated account, without changing username/password login.

Accepted: either participant can edit common expense fields or delete the shared expense, with history visible to both. Only an assignment's owner can edit it, and private categories and budgets stay out of shared history. The [data model and sync proposal](data-model-and-sync.md) covers records, invitation states, history storage, and per-user change feeds. Pending-invitation treatment, reuse of an accepted connection, removing sharing, and repayment confirmation still need review.

### 2. Financial data and calendar contract

Agree on expense, split, repayment, category, and yearly-budget representations. Decide budget edits, negative rollover, odd-cent splits, and the effect of deleting a settled shared expense.

Recommendation: integer minor currency units, explicit currency, client-generated UUIDs, and an explicit calendar expense date separate from UTC creation/modification timestamps. Travel and server timezones must not move an expense into another month. Calculate remaining budgets and debts from underlying records rather than syncing editable running totals.

Publish language-neutral JSON examples for budget rollover, splits, repayments, deletion, and rounding. Run those same examples against Swift and server calculations to prevent differences between offline and website results.

### 3. Offline storage and sync protocol

Choose local persistence and prove it can commit an expense change and its pending sync operation together.

Recommendation: evaluate SwiftData first because it fits the native SwiftUI preference. Verify explicit saving, schema migrations, and a durable pending-change queue with a small prototype before committing. SQLite with an explicit persistence layer remains an alternative if the prototype exposes a concrete limitation.

Use the custom backend as the shared sync service. The [draft protocol](data-model-and-sync.md) proposes client-generated operation IDs for safe retries, server-issued record revisions, per-user resumable change cursors, deletion/access-removal markers, and a full resync path that preserves pending local work. An offline device that returns after deletion-marker cleanup must not recreate deleted records. Shared writes must update both participants' feeds while exposing private assignments only to their owner.

Check the record's expected revision before accepting an edit. Retain both versions on a conflict and let the user resolve it; avoid automatically combining an expense amount from one edit with a split from another. The detailed conflict UI and handling of repeated local edits must be specified.

Start synchronization on app launch/foreground, local changes, and manual refresh. Background refresh is an optimization; do not make successful delivery depend on it. Expired authentication must preserve queued changes, and local stores must remain isolated when switching users.

### 4. Server stack and database

Accepted: Phoenix/Elixir for the combined website and JSON sync API, Phoenix LiveView for the website, and Ecto with the SQLite adapter for server persistence. The application operates its own accounts and storage backend. Deploy on one host with a persistent local database directory, short write transactions, consistent backups, and no direct client access to the database file. CloudKit is not selected.

The sync endpoint implementation and device authentication still need explicit design. Verify the Ecto SQLite transaction and connection configuration against concurrent website writes and sync requests during setup.

Keep website and API writes in the same application services so validation, versioning, and change tracking cannot diverge. Select supported framework/runtime versions during setup and record dependency versions then.

### 5. Authentication and privacy boundary

Accepted in [ADR 0004](adr/0004-password-login-and-passkeys.md): username/password login with optional passkeys as an alternative login method on both iOS and the website, using the same application-owned accounts. Passkeys are not a required second factor, and Sign in with Apple is not selected. Native Authentication Services and web WebAuthn use the same relying party identity and server-side credential verification.

Still to decide: account recovery, whether a recovery email is required, username normalization, domain/relying party ID, authentication libraries, session lifetimes, and how iOS device credentials are issued and revoked. Decide whether the server may read stored expense data or end-to-end encryption is required; this affects server-rendered website functionality and recovery.

Recommendation: invite-only accounts, normal browser sessions, revocable iOS credentials stored in Keychain, and user-scoped authorization on every record and sync operation. Use HTTPS and protected storage/backups. For the MVP, propose conventional server-readable storage; end-to-end encryption requires a separate design. Exclude expense descriptions and credentials from routine logs.

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
