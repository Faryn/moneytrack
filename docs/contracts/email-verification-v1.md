# Email ownership verification, v1

Implemented preparation for the email invitations in ADR 0005. Shared records and invitation acceptance are now implemented in the [v2 contract](shared-sync-v2.md). Verification does not enable public signup, email login, password recovery, or passkeys. Accounts remain administrator-created under ADR 0008. The creator's proposed share applies immediately under ADR 0010; recipient categorization and connection reuse are accepted in ADR 0012.

## User flow

On iOS, open Account → Email for Sharing. On the website, open Account. Enter an email address, request a code, then enter the eight-digit code delivered to that mailbox. A valid code binds that address to the currently authenticated account. Merely knowing an address or forwarding a future invitation does not provide this proof.

An account can initially verify one address, and an address can belong to only one account. Changing/removing a verified address is not implemented; its effect on pending invitations and recovery needs a later policy. Mailbox verification does not change how the account signs in.

Addresses are trimmed and case-normalized, with a restricted ASCII mailbox syntax; display names, quoted local parts, and internationalized local parts are unsupported. Codes expire after 30 minutes, allow five failed attempts, and are superseded when a new code is requested. Requests are limited to three per account per hour; verification calls are limited to 20 per account per minute, including invalid identifiers. Failed attempt counters persist across restarts.

## Authenticated API

The following endpoints require a device bearer session, never a browser cookie:

- `GET /api/v1/account/email`: current account's verification state.
- `POST /api/v1/account/email`: `{"email":"person@example.org","requestID":"<client UUID>"}`. Retries with the same UUID and address reuse the existing challenge and mail job. A successful response reports current state, including delivery progress; start a new UUID for an intentional new code.
- `POST /api/v1/account/email/verify`: `{"verificationID":"<challenge UUID>","code":"<eight digits>"}`. The challenge is bound to both the authenticated account and its address. Successful verification consumes the challenge; a lost success response is recovered with `GET`, which reports the verified address.

State includes `verifiedEmail`, `pendingEmail`, `verificationID`, `expiresAt`, and `deliveryStatus`, using null when absent. `expiresAt` is an ISO 8601 UTC instant. `deliveryStatus` is queued/sending/sent/failed; it describes delivery, not mailbox ownership. Invalid or expired proof returns 422; exhausted request limits 429; unavailable production delivery 503. A conflicting request UUID or address binding returns 409. Responses do not expose another account's email or challenge.

The website calls the same verification context behind its authenticated, CSRF-protected LiveView session. Username/password and private personal sync are unchanged.

## Durable delivery and secrets

A verification challenge and its mail job commit in one SQLite transaction. Codes are generated with OTP's secure random source and hashed with maintained bcrypt. The durable queue holds a Phoenix-encrypted payload rather than a plaintext code. Payloads are cleared after successful delivery, cancellation, expiry, or terminal failure. Keep `SECRET_KEY_BASE` stable and protected; queue decryption depends on it.

The single Phoenix application polls a bounded batch. A lease recovers interrupted delivery; transient failures receive up to five attempts. Message IDs and codes remain stable across retries. Email transport is at least once: a provider accepting mail before the process crashes can result in a repeated email. Financial operation deduplication is a separate guarantee.

Failed provider responses are neither logged nor persisted because they can contain a complete message. API/LiveView parameters and SQL values remain filtered from logs. No credential appears in an emailed URL.

Development uses Swoosh Local and the preview at `/dev/mailbox`; tests use Swoosh Test, with polling disabled. Production verification delivery and polling are disabled. Before enabling them, select/configure the real Swoosh adapter, a valid sender/domain, credentials, `email_delivery_enabled: true`, and `mail_delivery_polling: true`. The `.invalid` development sender is not a production configuration. No external mail provider is configured or exercised by repository checks.

## Checks

Server tests exercise account binding, unique verified addresses, code expiry/replay, persisted attempt limits, request deduplication and quotas, atomic queue rollback, superseded codes, worker lease recovery, provider failure retries, and payload removal. Browser and JSON API tests verify the same ownership flow. The isolated native integration check exercises authenticated state, request/retry, rejected proof, and the native code-entry form. Exact shared split math uses [common Swift/Elixir examples](shared-expense-examples.json), including odd cents assigned to the payer; it is now connected to the shared-expense UI and ledger.
