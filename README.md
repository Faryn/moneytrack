# MoneyTrack

A personal expense and budget tracker for a small user base, primarily on iPhone. The main screen answers **how much budget is left this month**, shows category budgets at a glance, and opens category details with a tap.

## Project status

Runnable application foundations are in place: a native SwiftUI iPhone app, Phoenix LiveView website, JSON liveness endpoint, and Ecto/SQLite configuration. Toolchain versions are recorded, server dependencies are locked, and independent build/check scripts are included. The specification, accepted architecture decisions, and draft data/sync design remain included.

Both apps currently show a budget empty state. Authentication, financial records, local persistence, invitations, and actual sync are the next implementation stages; no domain tables or seed data have been added yet.

## Agreed product direction

- Native SwiftUI with standard iOS components, targeting the latest stable iOS release selected at implementation time.
- Fast form entry with suggested categories, today's date by default, and offline saving followed by synchronization.
- Flat categories with yearly budgets, one twelfth allocated monthly, unused amounts carried forward, and a January 1 carryover reset.
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
- [Architecture decision records](docs/adr/README.md): the five accepted decisions.
- [Data model and sync proposal](docs/data-model-and-sync.md): proposed records, invitation lifecycle, and offline sync behavior. This is a draft, not an accepted protocol.
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
```

Verified on 2026-11-01: six server tests pass, assets compile, the website and JSON endpoint return HTTP 200, and the SwiftUI app builds and launches on an iOS 26.5 simulator using Xcode 27.2. Neither app has been deployed.

## Next implementation milestone

Prove one complete flow: sign in, create an expense offline on iOS, reconnect, see it on the website, edit it there, and receive the update on iOS without duplication or silent loss.

Remaining product assumptions stay marked in the [technical backlog](docs/technical-decisions.md). No hosting provider, domain, production account configuration, or public release has been configured.
