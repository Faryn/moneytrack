# MoneyTrack

A personal expense and budget tracker for a small user base, primarily on iPhone. The main screen answers **how much budget is left this month**, shows category budgets at a glance, and opens category details with a tap.

## Project status

The native iOS app now supports local personal expenses, flat categories, yearly budget editing, monthly totals and category breakdowns, category details, and searchable expense history. Entries can be created, edited, and deleted offline and survive relaunch. Standard SwiftUI tabs, navigation, forms, sheets, menus, and adaptive green/red amount colors lead the UX.

The first connected flow is implemented: administrator-created accounts, username/password login on iOS and web, Keychain-held native sessions, and personal-expense/category/budget sync. The website supports monthly review, yearly budget amounts, and expense creation/edit/deletion through the same owner-scoped ledger service. SwiftData preserves offline changes, exact retry payloads, revisions, conflicts, and deletions. Email ownership verification is available on iOS and web with durable local/test mail delivery. Passkeys, invitations, shared expenses, recovery, and production deployment remain unfinished. Normal stores receive no sample data.

## Agreed product direction

- Native SwiftUI with standard iOS components, targeting the latest stable iOS release selected at implementation time.
- Fast form entry with suggested categories, today's date by default, and offline saving followed by synchronization.
- Flat categories with yearly budgets, one twelfth allocated monthly, unused and overspent amounts carried forward, and a January 1 carryover reset. Editing a yearly amount recalculates the whole year.
- Category budgets are visible on Budget home. Green/red amounts distinguish available budget, overspending, and the direction of shared balances, alongside text labels and signs.
- Personal expenses first. Share a saved expense afterward with one other user through a direct email invitation.
- Splits of all, half, or none; only each participant's own share counts against their budget.
- Both participants see the shared expense and may edit or delete it, with shared change history. Categories and budgets remain private.
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

Verified on 2026-11-01: 53 server tests and 24 native tests pass, including populated V1-to-V2 migration, Keychain, disk failure recovery, and a real temporary backend. Native integration checks exercise retry, conflict resolution, deletion, session expiry/re-login, explicit on-device copying, and account restoration after relaunch. Website tests verify the same change feed and preservation of stale forms/drafts. Email checks also cover account-bound proof, durable delivery retries, rejected proof on the native API, and native code entry. The iOS Release build passes. Neither app has been deployed.

## Next implementation milestone

The personal iOS ↔ server/website flow is now verified. Email verification and exact shared split calculations are now prepared. Next: finish two-person sharing after the pending recipient-category and connection-reuse choices, and add optional passkeys once the stable HTTPS domain/relying party identity is chosen.

Remaining product assumptions stay marked in the [technical backlog](docs/technical-decisions.md). No hosting provider, domain, production account configuration, or public release has been configured.
