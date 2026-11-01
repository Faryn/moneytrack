# Phoenix server

Status: component directory reserved; no Phoenix project generated yet.

## Selected stack

- Elixir and Phoenix.
- LiveView for the online companion website.
- JSON API for native iOS authentication and synchronization.
- Ecto with the SQLite adapter and application-managed migrations.
- One application deployment with persistent host-local storage.

Both LiveViews and API controllers call the same application contexts for authorization, financial validation, writes, and sync tracking. A website edit must enter the same change feed consumed by iOS.

## Setup requirements

When generating the application, explicitly choose SQLite, pin supported Elixir/Erlang and Phoenix dependencies, and preserve this README's project-specific notes. Do not accept PostgreSQL generator defaults. Record verified setup, migration, test, and server-start commands here after generation.

This repository is inside OneDrive. Configure all live SQLite database paths outside the checkout, including development/test paths; keep the database directory writable for WAL/SHM sidecars. Backups also belong outside the checkout. The `.gitignore` is an additional guard, not a substitute for a host-local runtime directory.

Authentication must meet username/password plus optional passkey requirements. Review generated authentication before adopting it; web sessions alone do not implement mobile device credentials or passkey verification. Select maintained libraries and a recovery policy during implementation.

Email delivery is needed for invitations. Use a local preview/test adapter during development, with fake recipients and no real invitation sending. Select and configure a production delivery provider later.

See [accepted architecture decisions](../docs/adr/README.md), [sync proposal](../docs/data-model-and-sync.md), and [development plan](../docs/development.md).
