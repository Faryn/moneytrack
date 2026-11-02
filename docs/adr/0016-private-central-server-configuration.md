# ADR 0016: Central instance through private configuration

- Status: Accepted
- Date: 2026-11-02

The user selected the deployed central instance as the normal app default. Temporary local testing remains allowed. Real hostnames must not enter the Git repository.

## Decision

- Both iOS build configurations read an ignored local xcconfig for the default server URL. Tracked source contains only the configuration key and an example. New sign-ins use the configured instance without requiring server entry.
- Keep temporary server selection behind debug-only development controls. UI tests use only their explicit test-server setting and cannot fall through to the central instance. A missing default shows a configuration error rather than inventing a server.
- Preserve saved credentials, account namespaces, and pending work on their original server. A new default never silently transfers financial data or rebinds an existing account.
- Real deployment hostnames, aliases, and addresses live in ignored JSON/local files. Tracked templates contain placeholders; a validating renderer writes private output only to an ignored directory or outside the repository.
- Add a privacy check for accidentally tracked local configuration and locally known host identifiers. Use documentation examples instead of real deployment addresses.
- Remove earlier host references from unpublished local history after making an external private repository backup. There is no configured Git remote; rewritten commit IDs replace those earlier local IDs.

This extends [ADR 0015](0015-app-host-deployment.md) without changing the running backend or its financial rules. See [configuration and deployment instructions](../../deploy/README.md).
