# ADR 0002: Application-owned authentication and SQLite backend

- Status: Accepted
- Date: 2026-11-01

## Context

MoneyTrack needs authenticated access from a native iOS app and a companion website, with offline iOS changes synchronized later. The expected user base is fewer than ten people.

CloudKit was considered as an alternative to an application-operated backend. The decision is to operate our own account system and storage backend. PostgreSQL adds a separate database service that is unnecessary for the anticipated workload.

## Decision

- Keep the combined website and API server established in [ADR 0001](0001-single-repository-and-combined-server.md).
- The application owns accounts, authorization, and sessions.
- Use SQLite for the server's persistent database, with application-managed migrations.
- iOS and browser clients access data through the server; they never access or synchronize the database file directly.
- Implement offline synchronization between the iOS local store and the server API. CloudKit is not the product's storage or sync service.
- The choice of server SQLite does not determine the iOS persistence framework.

The precise sign-in method remains open. Email/password is a working assumption, not an accepted requirement. Sign in with Apple is not mandated by this decision and may be considered separately; it would still authenticate against application-owned accounts if added.

Subsequent decision: [ADR 0004](0004-password-login-and-passkeys.md) resolves the login method as username/password with optional passkeys. [ADR 0003](0003-phoenix-server.md) resolves the server framework as Phoenix.

## Deployment and data integrity

- Run the initial application on one server host with a persistent local database directory. Multiple application processes, if used, must access that same host-local storage.
- Keep the live database outside source control, cloud-synchronized folders such as OneDrive or iCloud Drive, and shared network filesystems.
- Use short database transactions and atomic writes for an expense, its split, record revision, and sync change tracking.
- Enforce foreign keys on every connection. Configure a bounded busy timeout and handle contention explicitly.
- Plan to use WAL mode with full commit durability, using a patched SQLite runtime verified during setup. SQLite still serializes writes; this is appropriate for the expected workload.
- Create consistent backups using SQLite's backup facilities, store encrypted copies separately, and verify restoration. Copying only a live main database file is not the backup procedure.
- Use the selected framework's established credential and session facilities. Application-owned authentication does not mean implementing password hashing or token cryptography from scratch.

## Consequences

### Benefits

- No separately operated database service.
- One backend serves both clients with a common authorization and validation model.
- Account access does not depend on an iCloud account.
- SQLite provides transactional storage appropriate for the anticipated small workload.

### Tradeoffs

- We operate authentication, recovery, synchronization, backups, and server availability.
- Only one writer can commit at a time, so long write transactions and uncontrolled concurrent writes must be avoided.
- Deployment requires persistent host-local storage; a stateless multi-host deployment is not the initial architecture.
- The account owner and server operator can access server-stored data under the conventional storage model. End-to-end encryption remains a separate, unresolved decision.

## Alternatives considered

- **CloudKit:** viable for an Apple-focused product, but not selected because the product will use its own account and storage backend.
- **PostgreSQL:** capable, but the separate service and administration are not justified by the initial workload.

## Still to decide

Server framework, exact sign-in and recovery methods, local iOS persistence, sync protocol, hosting, backup retention, and app distribution. Invite-only account creation remains a recommendation until agreed.

## Revisit when

Reconsider the database if measured write contention, multi-host availability requirements, or operational needs make a client/server database useful.

## References

- [SQLite: appropriate uses](https://www.sqlite.org/whentouse.html)
- [SQLite: write-ahead logging](https://www.sqlite.org/wal.html)
- [SQLite: online backup](https://www.sqlite.org/backup.html)
