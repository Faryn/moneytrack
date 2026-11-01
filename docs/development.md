# Development plan

Status: implementation plan. It does not approve the remaining product assumptions or establish a release date.

## Repository baseline

The repository includes the agreed product specification, accepted architecture decisions, a draft data model/sync protocol, and runnable Phoenix foundations plus a working local SwiftUI personal ledger. iOS leads UX implementation; the website will adapt its flows. Verified setup commands and component boundaries are described in [ios/README.md](../ios/README.md) and [server/README.md](../server/README.md).

Use the [technical decision backlog](technical-decisions.md) to distinguish accepted choices from recommendations. The [product specification](../SPEC.md) remains the source for required behavior; the [sync proposal](data-model-and-sync.md) is an implementation draft.

## 1. Establish application foundations

Completed on 2026-11-01: Phoenix 1.8.16 with LiveView/Ecto/SQLite, a SwiftUI Xcode project and shared scheme, recorded toolchains, dependency locking, host-local database configuration, and independent check scripts. At this initial foundation stage, six server tests and asset compilation passed; website/API HTTP smoke checks pass; the iOS app builds and launches on the iOS 26.5 simulator. Ecto initialized its migration tracking, but no domain migration or seed data has been introduced.

Recorded toolchain: Erlang/OTP 29.1.2, Elixir 1.20.4, Xcode 27.2, iOS SDK 27.2 with deployment target 26.5, and SQLite 3.54.1 through locked Exqlite 0.43.0. The deployment target enables launch verification using the installed simulator runtime.

- Select supported toolchain and dependency versions and record them in the repository.
- Generate one Phoenix application in `server/` with LiveView, Ecto, and SQLite.
- Create the native SwiftUI Xcode project in `ios/` and shared schemes for reproducible builds.
- Configure persistent host-local database paths outside this OneDrive checkout.
- Add actual component build/test instructions and independent server/iOS checks once runnable code exists.

Done when both applications build, the server applies a migration to the intended SQLite location, and the iOS app runs in the simulator. No deployment or production account setup is needed for this milestone.

## 2. Define the common contract and local persistence

Completed locally on 2026-11-01: versioned SwiftData storage, atomic domain/outbox saves, disk reopening, deletion tombstones, namespace isolation, and real failed-save rollback. Eight budget examples run in Swift and Elixir. Nine native unit tests and one simulator UI test pass; the server has 15 tests. See [ADR 0007](adr/0007-swiftdata-local-store-and-outbox.md).

- Preserve the tested domain/outbox guarantees while extending the implemented personal protocol to shared records.
- Before the first schema change, test forward migration with populated V1 records, tombstones, and pending work.
- Finalize the minimum API contract for a personal expense, stable IDs, revisions, retries, deletion, and a per-user change cursor.
- Verify that failed/expired authentication cannot lose or mix local account data.

Completed for personal records: the versioned API, explicit account bootstrap/copy, V1-to-V2 migration, stable retries, acknowledgments, cursors, and session-expiry recovery are now implemented and exercised against a real temporary backend. Shared-record synchronization remains draft.

## 3. Prove the first complete flow

Completed for personal records on 2026-11-01: administrator-created username/password accounts, isolated native stores/Keychain sessions, offline personal entry, explicit account copy, website/API writes through one ledger service, retry deduplication, conflict review, synchronized deletion, and expired-session re-login. The connected check verifies the real native API and simulator account/relaunch flow; server tests verify website changes enter that same feed. No production deployment is included.

- Implement username/password authentication with browser sessions and revocable native device credentials.
- Create a personal expense offline on iOS, reconnect, and show it on the website.
- Edit it on the website and receive the revision on iOS.
- Repeat a sync request after a simulated lost response without creating a duplicate.
- Exercise edit/delete conflicts and user isolation before calling the flow complete.

Done when the flow works through real application storage and API boundaries. This milestone is not the whole MVP: shared expenses, full budget views, and passkeys follow.

## 4. Complete budgets and sharing

The local iOS budget flow is implemented: yearly category amounts, positive/negative carryover, January reset, whole-year recalculation after budget edits, total remaining, category breakdown, detail navigation, and native expense forms/history. Entry uses local history suggestions; no NLP is included.

Sharing preparation on 2026-11-01 adds exact split math with common Swift/Elixir fixtures and account-bound email verification on iOS/web. Verification mail survives restarts and retries in an encrypted SQLite queue; development/test mail stays local. Shared records, invitations, and the pending recipient-category and connection-reuse choices remain unimplemented. See the [verification contract](contracts/email-verification-v1.md).

- Connect the tested budget calculation and editing flows to authenticated server storage and the website.
- Resolve remaining invitation and repayment assumptions before implementing affected behavior. Budget rules are confirmed in [ADR 0006](adr/0006-calendar-year-budget-calculation.md).
- Add email invitation onboarding and verified recipient acceptance using fake/test mail during development.
- Show one shared expense to both participants, with private category assignments and personal-share budget calculations.
- Implement shared edit/delete history and the record-only Settle Up flow in ADR 0011, asking for an editable amount. Resolve acknowledgment/correction policies before connecting its save action.
- Verify the financial and authorization examples across both users, the website, and offline iOS devices.

Record-only Settle Up is now a confirmed requirement (ADR 0011). Full/partial repayment calculations run against the same fixtures in Swift and Elixir, including both directions, unchanged expense spending, exact cents, and aggregate overflow. Recording screens, shared persistence, and synchronization are still pending.

## 5. Finish authentication and prepare a release

- Choose the stable HTTPS domain/relying party identity and account recovery policy.
- Add optional passkey enrollment, sign-in, and credential management on iOS and the website before MVP release.
- Select hosting, invitation delivery, and iOS distribution.
- Verify migrations, backups/restoration, pending-data recovery, exports, and API compatibility with an installed client.
- Add operational instructions and verified release checks based on the actual implementation.

## Source data and credentials

Use synthetic expenses and identities in fixtures. Keep personal financial exports, credentials, live databases, backups, and signing material out of Git. Keep local dependency/build output ignored, while committing dependency lockfiles and shared project configuration when generated.
