# Phoenix server

Phoenix application with administrator-created username/password accounts, browser/device sessions, personal categories/yearly budgets/expenses, versioned JSON sync, and a LiveView companion. Website and API mutations share the same owner-scoped transaction/revision/change-feed logic. Passkeys, invitations, shared expenses, and recovery are not implemented yet.

## Toolchain

- Erlang/OTP 29.1.2 and Elixir 1.20.4, pinned in [`.tool-versions`](../.tool-versions).
- Phoenix 1.8.16, LiveView 1.2.13, Ecto SQLite3 0.26.0, and remaining dependencies locked in `mix.lock`.
- Exqlite 0.43.0 provides the verified SQLite 3.54.1 runtime.
- Tailwind 4.3.3 and esbuild 0.25.4 are pinned in `config/config.exs`; no separate Node installation is required by this scaffold.

## Run locally

From this directory, with the pinned Elixir/Erlang toolchain installed:

```sh
mix local.hex --force
mix local.rebar --force
mix setup
mix phx.server
```

The website is at [localhost:4000](http://localhost:4000). `GET /api/health` returns `{"status":"ok"}` and is a liveness probe, not a database-readiness or authenticated sync endpoint. Set `PORT` to use a different local port.

`mix setup` downloads dependencies, applies the account/ledger and email-verification migrations, and builds assets. It creates no default account or financial seed records. After setup, run `scripts/create-user USERNAME` from the repository root, using the same database environment as the server. The helper prompts for a password without echoing it and passes it through stdin, keeping it out of command history and arguments. Usernames are 3–32 letters/numbers/._-; passwords are 12–72 bytes. Restarting the server is not required after adding an account.

## Database location

Runtime configuration keeps SQLite outside this OneDrive checkout:

- macOS default: `~/Library/Application Support/MoneyTrack/<environment>/moneytrack.sqlite3`.
- Linux default: `$XDG_DATA_HOME/moneytrack/<environment>/moneytrack.sqlite3`, falling back to `~/.local/share` for the data root.
- `MONEYTRACK_DATA_DIR`: override the host-local base directory for development and tests. Each environment gets a separate subdirectory.
- `DATABASE_PATH`: override the exact development database file; required in production.
- `MONEYTRACK_TEST_DATABASE_PATH`: optional explicit test-file override. Tests intentionally ignore `DATABASE_PATH` so a normal production/development setting is not reused accidentally.
- `MIX_TEST_PARTITION`: suffixes default test filenames for partitioned runs.

Paths must be absolute and outside the checkout. Configuration creates the containing directory. Use persistent host-local storage with permission to create the WAL/SHM sidecars; do not use OneDrive, iCloud Drive, or a network share. Defaults are WAL, full commit durability, foreign keys enabled, a single connection, and a five-second driver busy timeout. Exqlite uses a custom busy handler, so `PRAGMA busy_timeout` does not report that configured timeout.

For a disposable local run, for example:

```sh
MONEYTRACK_DATA_DIR=/private/tmp/moneytrack-dev mix setup
MONEYTRACK_DATA_DIR=/private/tmp/moneytrack-dev mix phx.server
```

## Checks

After setup, from the repository root:

```sh
scripts/check-server
```

This checks application compilation with warnings as errors, formatting, ExUnit tests, and web asset compilation. Run `mix format` in `server/` when formatting changes are needed. Dependencies may emit their own warnings independently of application compilation.

Current tests cover financial examples, owner isolation, password/session boundaries, token hashing/expiry/revocation, login throttling, exact-once retry, conflict handling, deletion, cursor pagination, website writes into the same feed, and retention of form drafts. Database tests run serially because SQLite permits one writer at a time. `scripts/check-connected` runs these checks plus a fresh temporary backend and native integration/UI tests with synthetic identities; it refuses to reuse an occupied port 4004 and stops its server afterward.

## Implementation boundaries

Both LiveViews and API controllers call `MoneyTrack.Ledger` for authorization, validation, record revisions, and change tracking. The current `/api/v1` contract is documented in [ADR 0009](../docs/adr/0009-personal-sync-contract.md) and the [API examples](../docs/contracts/personal-sync-v1.md). Personal records only are accepted; shared changes are not simulated.

Accounts use maintained bcrypt password hashing and Hammer rate limiting. Native device tokens are hashed, expiring, and revocable; encrypted/signed browser cookies are separate, with CSRF protection and secure flags in production. Request/SQL parameter logging is suppressed. HTTPS, server-readable storage, and administrator-created accounts are recorded in [ADR 0008](../docs/adr/0008-connected-accounts-and-transport.md). Password reset/recovery and passkeys remain release requirements.

Email ownership verification is implemented through one account-bound context for the authenticated website and native API. Codes expire, enforce persisted attempt limits, and use a durable encrypted delivery queue; see the [verification contract](../docs/contracts/email-verification-v1.md). Development email uses Swoosh's local preview at `/dev/mailbox`; tests use its test adapter. No invitations are sent, and no production delivery provider is configured. Production verification delivery and queue polling remain disabled until a provider and sender are configured. Development dashboard and mail preview routes are excluded from production builds.

Before deploying, configure `DATABASE_PATH`, `SECRET_KEY_BASE`, `PHX_HOST`, trusted HTTPS termination, private backend-port access, backups/restoration, and distribution. Production forces HTTPS and secure cookies. Forwarded protocol headers must come only from the trusted proxy. No production deployment, public domain, invitation provider, or release account configuration is included.

See [accepted architecture decisions](../docs/adr/README.md), [sync proposal](../docs/data-model-and-sync.md), and [development plan](../docs/development.md).
