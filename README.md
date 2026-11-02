# MoneyTrack

A personal expense and budget tracker for a small user base, primarily on iPhone. The main screen answers **how much budget is left this month**, shows category budgets at a glance, and opens category details with a tap.

## Project status

The native SwiftUI app supports personal expenses and budgets offline, with exact monthly/category calculations, standard navigation/forms, and adaptive green/red amounts. The Phoenix/SQLite website and API use administrator-created username/password accounts, native Keychain sessions, and revision-based synchronization.

Shared expenses support verified email invitations, immediate proposed-share budgeting, connection reuse, private categories, common edit/delete history, and record-only Settle Up. SwiftData preserves pending requests and conflicts through forward migrations to V4. Normal stores receive no sample data.

Passkeys, password recovery, production email/hosting, and TestFlight distribution remain unfinished. Invitation mail uses local/test delivery; no production deployment or payment provider is configured.

## Agreed product direction

- Native SwiftUI with standard iOS components, targeting the latest stable iOS release selected at implementation time.
- A compact floating plus on Expenses opens fast form entry with suggested categories, today's date, and offline saving followed by synchronization. Native animation/haptics respect Reduce Motion.
- Set the whole yearly budget, then allocate parts to flat categories. The remainder is one guilt-free pool for unallocated/uncategorized spending. Exact monthly amounts carry unused and overspent balances within the year, with a January reset; yearly edits recalculate the whole year.
- Category budgets are visible on Budget home. Green/red amounts distinguish available budget, overspending, and the direction of shared balances, alongside text labels and signs.
- Personal expenses first. Share a saved expense afterward with one other user through a direct email invitation.
- Splits of all, half, or none; only each participant's own share counts against their budget.
- Both participants see the shared expense and may edit or delete it, with shared change history. Categories and budgets remain private.
- Settle Up asks for an editable amount and records full/partial repayments against shared balances. It never moves money or changes expense budgets.
- Username/password login with optional passkeys on iOS and the website.
- Future German/English quick parsing uses built-in iOS capabilities, with no cloud AI. For example: `78€, Theodor, Restaurants`, where Theodor is the restaurant description.

No bank linking, income tracking, dedicated refund workflow, or recurring expense automation in the MVP. An expense can be deleted. Natural-language parsing and shared budgets are deferred.

## Architecture

```text
MoneyTrack/
├── README.md
├── AGENTS.md
├── SPEC.md
├── ios/                 Native SwiftUI client
├── server/              Phoenix application: LiveView website and JSON API
├── scripts/             Independent server and iOS checks
└── docs/
    ├── adr/             Accepted architecture decisions
    ├── data-model-and-sync.md
    ├── technical-decisions.md
    └── development.md
```

The server uses Elixir/Phoenix, LiveView, and Ecto with SQLite. Both website and API writes use common application contexts. iOS has a local store and communicates with the server API; CloudKit is not selected.

## Start here

- [Product specification](SPEC.md): confirmed requirements, examples, and marked assumptions.
- [Architecture decision records](docs/adr/README.md): accepted architecture, budget rules, and local persistence choices.
- [Data model and sync proposal](docs/data-model-and-sync.md): proposed records, invitation lifecycle, and offline sync behavior. This is a draft, not an accepted protocol.
- [Local storage](docs/local-storage.md): saving guarantees, store isolation, and the boundary between the local outbox and future sync.
- [Technical decision backlog](docs/technical-decisions.md): remaining choices and recommended defaults awaiting confirmation.
- [Development plan](docs/development.md): component boundaries, setup expectations, and the first implementation milestones.
- [UX proposal](docs/ux-proposal.md): proposed navigation and flows, including the confirmed category overview and amount-color requirements.
- [iOS component](ios/README.md) and [server component](server/README.md).

## Run and check

Follow [server setup](server/README.md) to start the website, or open `ios/MoneyTrack.xcodeproj` and run the shared `MoneyTrack` scheme on an iPhone simulator. The server uses host-local SQLite files outside the OneDrive checkout.

After initial setup, run checks from the repository root:

```sh
scripts/check-server
scripts/check-ios
scripts/test-ios
# Optional full check with a temporary backend and synthetic accounts:
scripts/check-connected
```

Verified on 2026-11-02: 90 server tests and 42 native tests pass in the isolated connected suite. Coverage includes whole-year plans, guilt-free pooling, two-decimal currency entry, exhaustive cent-level split/repayment checks, two-account sharing, private categories, partial settlement, financial conflicts/deletion, populated V1/V2/V3 migrations, immutable retries, and native setup/sharing/settlement UI. The iOS Release build passes. The current app/test deployment target is iOS 27.0. Neither app has been deployed.

Sharing is documented in [ADR 0012](docs/adr/0012-sharing-defaults-and-connected-flow.md) and the [v2 contract](docs/contracts/shared-sync-v2.md). Whole-year plans and guilt-free spending extend it through [ADR 0013](docs/adr/0013-whole-year-budget-and-guilt-free-spending.md) and the [v3 contract](docs/contracts/annual-budget-v3.md).

## Next implementation milestone

The personal iOS ↔ server/website flow is now verified. The connected sharing and record-only settlement flow is implemented. Next: select the stable HTTPS domain, production mail/hosting, account recovery policy, and optional passkeys before preparing TestFlight. Repayment corrections, overpayments, and invitation cancellation are follow-up work.

Remaining product assumptions stay marked in the [technical backlog](docs/technical-decisions.md). No hosting provider, domain, production account configuration, or public release has been configured.
