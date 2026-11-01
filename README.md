# MoneyTrack

A personal expense and budget tracker for a small user base, primarily on iPhone. The main screen answers **how much budget is left this month**, with category details one level deeper.

## Project status

Repository foundation and product planning. The specification, accepted architecture decisions, and draft data/sync design are included. Application code, database migrations, dependency versions, and build workflows have not been generated yet.

## Agreed product direction

- Native SwiftUI with standard iOS components, targeting the latest stable iOS release selected at implementation time.
- Fast form entry with suggested categories, today's date by default, and offline saving followed by synchronization.
- Flat categories with yearly budgets, one twelfth allocated monthly, unused amounts carried forward, and a January 1 carryover reset.
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
├── ios/                 Native SwiftUI client and local persistence
├── server/              Phoenix application: LiveView website and JSON API
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
- [iOS component](ios/README.md) and [server component](server/README.md).

## First implementation milestone

Prove one complete flow: sign in, create an expense offline on iOS, reconnect, see it on the website, edit it there, and receive the update on iOS without duplication or silent loss.

There are no runnable app setup commands yet. Pin the actual toolchains and dependencies when scaffolding, then add verified build/test instructions for each component. No hosting provider, domain, or public release has been configured.
