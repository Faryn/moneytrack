# Phoenix server

Runnable Phoenix foundation with a LiveView budget empty state, JSON liveness endpoint, Ecto/SQLite configuration, and local/test email adapters. Accounts, financial records, invitations, passkeys, and synchronization are not implemented yet.

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

`mix setup` downloads dependencies, initializes SQLite and its migration tracking, and builds the assets. There are no domain migrations or seed records yet. Subsequent migrations belong in `priv/repo/migrations`.

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

Current tests cover the LiveView mount, generated error responses, the database's location, and active SQLite durability/foreign-key settings. Database tests run serially because SQLite permits one writer at a time.

## Implementation boundaries

Both LiveViews and API controllers must call the same application contexts for authorization, financial validation, writes, and sync tracking. A website edit must enter the change feed consumed by iOS. No account or finance routes are exposed by this scaffold.

Authentication must meet username/password plus optional passkey requirements. Review generated authentication before adopting it; web sessions alone do not implement mobile device credentials or passkey verification. Recovery and authentication-library choices remain open.

Development email uses Swoosh's local preview at `/dev/mailbox`; tests use its test adapter. No invitations are sent, and no production delivery provider is configured. Development dashboard and mail preview routes are excluded from production builds.

Before deploying, configure `DATABASE_PATH`, `SECRET_KEY_BASE`, `PHX_HOST`, HTTPS termination, backups, and production email delivery. Deployment is outside this scaffold's scope.

See [accepted architecture decisions](../docs/adr/README.md), [sync proposal](../docs/data-model-and-sync.md), and [development plan](../docs/development.md).
