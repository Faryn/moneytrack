# ADR 0003: Phoenix for the website and sync API

- Status: Accepted
- Date: 2026-11-01

## Context

The product uses one repository, a native SwiftUI iOS app, and a combined website/API server. Application-owned accounts and server-side SQLite are already accepted decisions.

The server must serve a small interactive website, authenticate requests, apply financial rules, and synchronize offline iOS changes. Django, Rails, Phoenix, and Vapor were considered. Phoenix is the selected framework.

## Decision

- Implement `server/` as one Elixir/Phoenix application.
- Use Phoenix LiveView for the online companion website, with conventional controllers where appropriate.
- Expose a JSON API for the native iOS client, including authentication and synchronization endpoints.
- Use Ecto with the SQLite adapter for persistence and database migrations.
- Put authorization, financial validation, and writes in shared application contexts called by both LiveViews and API controllers.
- Commit domain changes and their sync bookkeeping together so website changes are visible to the iOS sync API.
- Keep the iOS client native SwiftUI. It communicates through the API and does not depend on LiveView or an active WebSocket connection.

Select supported Elixir, Erlang/OTP, Phoenix, LiveView, Ecto, and SQLite adapter versions when scaffolding. Record the toolchain and lock dependencies then.

## Consequences

### Benefits

- LiveView supports interactive server-rendered screens within the same application as the API.
- Website and API operations share authorization, calculations, persistence, and change tracking.
- SQLite remains the server database; selecting Phoenix does not introduce PostgreSQL.
- The application can be deployed as one server release on the single host established in ADR 0002.

### Tradeoffs

- The project uses Swift for iOS and Elixir for the server, so financial rules need matching implementations verified against shared examples.
- Elixir/Erlang adds a separate build and runtime toolchain.
- LiveView interaction relies on connectivity; offline website operation remains deferred.
- Phoenix does not supply the product's offline iOS sync protocol. Retry handling, revisions, deletion tracking, and conflict resolution still require implementation.

## Authentication boundary

Use Phoenix's established authentication facilities as a starting point once the login flow is chosen. Choosing Phoenix does not settle email/password versus another login method. Browser sessions and revocable iOS device credentials need separate integration; generated browser authentication alone is not a complete mobile authentication design.

Subsequent decision: [ADR 0004](0004-password-login-and-passkeys.md) selects username/password with optional passkeys for both iOS and the website.

## Alternatives considered

- **Django:** provides an integrated conventional website stack; not selected following the preference for Phoenix.
- **Rails:** provides an integrated website framework and SQLite support; not selected.
- **Vapor:** could share pure Swift types and calculations with iOS, but would require assembling more website and account functionality.

## Still to decide

Exact login and recovery flows, shared-record ownership, iOS local persistence, sync contract, hosting, and app distribution remain open. See the [technical decision backlog](../technical-decisions.md).

## References

- [Phoenix installation and database options](https://hexdocs.pm/phoenix/installation.html)
- [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view/welcome.html)
