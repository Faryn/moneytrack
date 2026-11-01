# ADR 0004: Username/password login with optional passkeys

- Status: Accepted
- Date: 2026-11-01

## Context

MoneyTrack operates its own accounts and SQLite storage backend in Phoenix. Both the native iOS app and the website need access to the same account. The login method left open in ADRs 0002 and 0003 is now selected.

## Decision

- Support username and password as the baseline login method on iOS and the website.
- Support optional passkeys as an alternative way to sign in to the same account without entering its password. Passkeys are not a mandatory second factor.
- Users can enroll passkeys after authenticating to their existing account. Enrollment must not create a separate account or duplicate financial records.
- Provide account settings to view and revoke enrolled passkey credentials and add another credential where supported by the authenticator.
- Keep username/password available for users who do not enroll a passkey or cannot use one on their current device.
- Use native Authentication Services for iOS passkeys and WebAuthn for the website, backed by the same Phoenix account and credential records.
- Sign in with Apple is not part of this authentication decision. Passkeys do not require adopting CloudKit for expense storage.

Use a username as the agreed login identifier. Whether accounts additionally require a recovery email address remains open; do not silently replace username login with email-only login.

## Implementation requirements

- Use maintained password hashing and WebAuthn verification libraries; select dependencies during implementation. Phoenix's generated browser authentication must be adapted and reviewed against these requirements rather than assumed to satisfy them unchanged.
- Store password hashes and passkey public-key credential data on the server. Passkey private keys stay with the user's credential provider.
- Require recent authentication for enrolling or removing credentials and changing passwords.
- Issue short-lived, single-use server challenges, bind them to the intended ceremony, and validate the relying party, allowed origins, signatures, and required user verification through the selected library. A successful credential ceremony alone must not bypass account authorization.
- Choose a stable HTTPS domain and relying party ID before enrolling production passkeys. Configure the iOS `webcredentials` associated domain and the domain's `apple-app-site-association` file so native and web access use the intended service identity.
- Establish normal application sessions after either login method. Use protected browser cookies and revocable iOS device credentials stored in Keychain; keep their issuance and revocation in the same account system.
- Rate-limit password attempts and authentication challenge endpoints. Avoid revealing whether a username exists through authentication error messages.
- Preserve local expenses and pending sync work if a session expires. Existing offline access does not require a new server login; reauthentication is required to resume authenticated synchronization.

## Consequences

- Users have a familiar baseline login plus an optional passwordless login experience.
- Both methods access the same data and authorization rules.
- The application must implement credential management and consistent web/native passkey configuration.
- Password recovery remains necessary. The recovery method and its effect on active sessions and registered passkeys must be specified before release.
- Domain changes require deliberate planning because passkeys are tied to the relying party identity.

## Still to decide

Account creation/invitation policy, username normalization, recovery method, final domain/relying party ID, authentication libraries, and session lifetimes.

## References

- [Apple: supporting passkeys](https://developer.apple.com/documentation/authenticationservices/supporting-passkeys)
- [Apple: connecting to a service with passkeys](https://developer.apple.com/documentation/authenticationservices/connecting-to-a-service-with-passkeys)
- [W3C WebAuthn](https://www.w3.org/TR/webauthn-3/)
