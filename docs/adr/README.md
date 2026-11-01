# Architecture decision records

Accepted decisions describe agreed architecture. Proposed technical choices remain in the [technical decision backlog](../technical-decisions.md) until agreed and recorded.

| ADR | Status | Decision |
| --- | --- | --- |
| [0001](0001-single-repository-and-combined-server.md) | Accepted | Single repository; native iOS client; combined website and API server |
| [0002](0002-own-authentication-and-sqlite-backend.md) | Accepted | Application-owned authentication and storage backend using SQLite |
| [0003](0003-phoenix-server.md) | Accepted | Phoenix/Elixir server, LiveView website, JSON API, and Ecto with SQLite |
| [0004](0004-password-login-and-passkeys.md) | Accepted | Username/password login with optional passkeys on iOS and web |
| [0005](0005-shared-expenses-and-email-invitations.md) | Accepted | Email-invited shared expenses with edit/delete access and history for both users; private categories; no contact list |
| [0006](0006-calendar-year-budget-calculation.md) | Accepted | Positive and negative carryover within a year; yearly amount edits recalculate the whole year; exact-cent monthly allocation |
| [0007](0007-swiftdata-local-store-and-outbox.md) | Accepted | Versioned SwiftData local store; domain mutations and pending changes saved together; no CloudKit |
| [0008](0008-connected-accounts-and-transport.md) | Accepted | Administrator-created accounts, HTTPS, server-readable storage, hashed/revocable sessions, and isolated native credentials |
| [0009](0009-personal-sync-contract.md) | Accepted for personal expenses | Versioned per-operation sync, stable retries, revision conflicts, private cursors, explicit local import, and SwiftData V2 migration |
| [0010](0010-pending-share-budget-treatment.md) | Accepted | Apply the creator's proposed personal share to budgets immediately, including while an invitation is pending |
| [0011](0011-record-only-settle-up.md) | Accepted | Settle Up asks for a full/partial repayment amount and records it against shared balances; no in-app payments or budget impact |
| [0012](0012-sharing-defaults-and-connected-flow.md) | Accepted | Private Uncategorized fallback, reuse accepted connections, and immediate repayment recording by either participant; connected shared flow |
