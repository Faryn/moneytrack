# Development plan

Status: implementation plan. It does not approve the remaining product assumptions or establish a release date.

## Repository baseline

The repository includes the agreed product specification, five accepted architecture decisions, and a draft data model/sync protocol. Application projects have not been generated. Component responsibilities are described in [ios/README.md](../ios/README.md) and [server/README.md](../server/README.md).

Use the [technical decision backlog](technical-decisions.md) to distinguish accepted choices from recommendations. The [product specification](../SPEC.md) remains the source for required behavior; the [sync proposal](data-model-and-sync.md) is an implementation draft.

## 1. Establish application foundations

- Select supported toolchain and dependency versions and record them in the repository.
- Generate one Phoenix application in `server/` with LiveView, Ecto, and SQLite.
- Create the native SwiftUI Xcode project in `ios/` and shared schemes for reproducible builds.
- Configure persistent host-local database paths outside this OneDrive checkout.
- Add actual component build/test instructions and independent server/iOS checks once runnable code exists.

Done when both applications build, the server applies a migration to the intended SQLite location, and the iOS app runs in the simulator. No deployment or production account setup is needed for this milestone.

## 2. Define the common contract and local persistence

- Prototype durable local saving of an expense and its pending operation. Evaluate SwiftData against save, migration, and queue requirements.
- Finalize the minimum API contract for a personal expense, stable IDs, revisions, retries, deletion, and a per-user change cursor.
- Add synthetic, language-neutral financial examples and run the applicable cases in Swift and Elixir.
- Verify that failed/expired authentication cannot lose or mix local account data.

Done when a local expense survives app termination and its pending sync work survives restart.

## 3. Prove the first complete flow

- Implement username/password authentication with browser sessions and revocable native device credentials.
- Create a personal expense offline on iOS, reconnect, and show it on the website.
- Edit it on the website and receive the revision on iOS.
- Repeat a sync request after a simulated lost response without creating a duplicate.
- Exercise edit/delete conflicts and user isolation before calling the flow complete.

Done when the flow works through real application storage and API boundaries. This milestone is not the whole MVP: shared expenses, full budget views, and passkeys follow.

## 4. Complete budgets and sharing

- Add category/year budgets, monthly carryover, January reset, and the home budget summary.
- Resolve the marked budget and invitation assumptions before implementing affected behavior.
- Add email invitation onboarding and verified recipient acceptance using fake/test mail during development.
- Show one shared expense to both participants, with private category assignments and personal-share budget calculations.
- Implement shared edit/delete history and agreed repayment behavior.
- Verify the financial and authorization examples across both users, the website, and offline iOS devices.

## 5. Finish authentication and prepare a release

- Choose the stable HTTPS domain/relying party identity and account recovery policy.
- Add optional passkey enrollment, sign-in, and credential management on iOS and the website before MVP release.
- Select hosting, invitation delivery, and iOS distribution.
- Verify migrations, backups/restoration, pending-data recovery, exports, and API compatibility with an installed client.
- Add operational instructions and verified release checks based on the actual implementation.

## Source data and credentials

Use synthetic expenses and identities in fixtures. Keep personal financial exports, credentials, live databases, backups, and signing material out of Git. Keep local dependency/build output ignored, while committing dependency lockfiles and shared project configuration when generated.
