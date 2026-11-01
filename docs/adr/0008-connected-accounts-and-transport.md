# ADR 0008: Connected accounts and transport

- Status: Accepted
- Date: 2026-11-01

## Context and user decisions

The user confirmed ordinary server-side storage with transport security, without requiring end-to-end encryption, and administrator-created accounts for the first connected version. Username/password with optional passkeys remains the product requirement from ADR 0004.

## Implementation decisions

- Create accounts through the administrator command, with no public registration route. Invitation onboarding, verified email, recovery, password changes, and passkeys follow separately.
- Normalize usernames by trimming and lowercasing. Accept 3–32 ASCII letters/numbers/period/underscore/hyphen, starting with a letter or number. Username is not replaced by email.
- Hash passwords using maintained `bcrypt_elixir`, using the production default cost. Accept 12–72 bytes and reject longer inputs before hashing or verification to avoid bcrypt truncation. Tests alone use a lower cost.
- Issue 32-byte cryptographically random credentials through the standard Erlang crypto API. Store only SHA-256 token hashes, with a 30-day expiry. Browser and native device sessions are distinct and revocable.
- Browser sessions use renewed, encrypted/signed HttpOnly cookies, SameSite=Lax, secure in production, and CSRF protection. Check authorization again when LiveView mounts; close an expired/revoked connected browser session.
- Native credentials live in Keychain with device-only accessibility after first unlock. Passwords are not saved by the app. An expired session preserves local access and pending work, requiring sign-in only to resume sync.
- Rate-limit login by IP and normalized username with maintained Hammer on the single application host. Use generic credential failure responses and comparable password verification for missing accounts.
- Require HTTPS in production. iOS uses normal certificate validation and rejects API redirects. Debug builds allow loopback HTTP for development only. Configure the final trusted TLS proxy/domain before deployment; the backend port must not be exposed with untrusted forwarding headers.
- Suppress request parameter and SQL parameter logging so credentials and financial descriptions do not enter routine logs.

## Boundaries

This is the first connected development slice, not a production account service. Optional passkeys remain required before the MVP release. Recovery policy, administrative password reset, session management UI, the stable domain/relying party identity, deployment, backups, and distribution setup remain open. Offline sign-out clears the native credential and retains the account cache; server revocation is best effort when a network connection is unavailable.

## References

- [Phoenix API authentication](https://hexdocs.pm/phoenix/api_authentication.html)
- [bcrypt_elixir](https://hexdocs.pm/bcrypt_elixir/Bcrypt.html)
- [Hammer](https://hexdocs.pm/hammer/readme.html)
