# ADR 0001: One repository with a native iOS client and combined web/API server

- Status: Accepted
- Date: 2026-10-31

## Context

MoneyTrack is a personal expense and budget tracker for fewer than ten users. Its primary client is a SwiftUI iOS app that supports offline changes and later synchronization. A companion website provides similar functionality.

Expense, budget, and synchronization changes frequently affect both clients and the server. At this scale, minimizing coordination and operational overhead matters more than independent team ownership.

## Decision

Keep the product in a single repository with these top-level responsibilities:

```text
MoneyTrack/
├── SPEC.md
├── ios/       Native SwiftUI app, local storage, and sync client
├── server/    One application serving the website and sync API
└── docs/      Architecture decisions, API contracts, and product documentation
```

The server owns authentication, authorization, server-side validation, and database access. Its website and API use the same application/domain services and database. The iOS client accesses server data through an authenticated API, never by connecting directly to the database.

Organize the server into internal modules as needed. The website and sync API are part of the same deployable application. The iOS app has its own build and release process.

Keep API contracts and language-neutral financial examples in the repository so coordinated changes can be reviewed together. Repository co-location does not require sharing implementation code between Swift and the server language.

Released iOS clients can remain installed after a server deployment, so API compatibility and database migration policy must be designed explicitly even though the code shares a repository.

## Consequences

### Benefits

- One change can update iOS, server, API documentation, and verification together.
- The website and API share business rules, authentication infrastructure, and storage.
- Fewer repositories, deployments, and integration boundaries to maintain.
- Build and release workflows can target only the components they need.

### Tradeoffs

- The repository contains multiple toolchains and requires separate iOS and server checks.
- Website and API deployments are coupled.
- Access permissions apply to the repository as a whole.
- Offline iOS budget calculations still need an implementation consistent with the server; a monorepo alone does not guarantee this.

## Alternatives considered

- **Separate iOS, web, and backend repositories:** adds cross-repository coordination without a current ownership or release requirement that justifies it.
- **One repository with independently deployed web and API applications:** possible later, but adds deployment and authentication boundaries that the initial product does not require.
- **A single cross-platform client:** does not align with the preference for native SwiftUI and standard iOS components.

## Not decided here

Server framework, databases, local persistence, sync protocol, authentication method, hosting, and application distribution require separate decisions. See [technical decision backlog](../technical-decisions.md).

## Revisit when

Consider splitting components if separate teams need different access controls, release independence becomes necessary, or the combined server creates a demonstrated deployment constraint.
