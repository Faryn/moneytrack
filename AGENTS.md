# MoneyTrack contributor guidance

## Read before changing behavior

- Read `SPEC.md`, `docs/adr/README.md`, and the relevant accepted ADRs.
- `docs/data-model-and-sync.md` is a draft. Recommendations and marked assumptions are not automatically accepted decisions.
- Keep documentation consistent when user decisions change requirements. Preserve accepted ADR history and link later decisions that resolve or supersede earlier open questions.
- Ship all user-facing text in English and German in the same change. This includes iPhone, iPad, web, accessibility labels, errors, emails, and privacy notices. Use the iOS string catalog and Phoenix Gettext for interface text, and verify both languages for every changed flow. Add server errors displayed by both clients to both catalogs. Keep user-entered text, stored identifiers, and API codes unchanged.

## Architecture and product constraints

- One repository: native SwiftUI in `ios/`, one Phoenix website/API application in `server/`, supporting material in `docs/`.
- Use Ecto with server-side SQLite. Do not introduce PostgreSQL, CloudKit, a separate frontend application, or additional services without a requirement that justifies a new decision.
- iOS leads the UX. Follow Apple's Human Interface Guidelines and prefer standard SwiftUI navigation, lists, forms, sheets, menus, and accessibility behavior; adapt the web companion to the native flows. Form-based expense entry precedes natural-language parsing; any later parsing stays on-device and supports German and English.
- Budget home must show category budgets at a glance, with direct category-detail navigation. Use accessible green/red amount semantics with labels/signs; do not hide all category budgets behind another overview screen.
- Accounts are administrator-created for now. Use HTTPS in production and ordinary server-readable storage with owner-scoped access; end-to-end encryption is not required. Login is username/password with optional passkeys. Do not silently replace username login with email-only or magic-link-only authentication.
- Shared expenses have two participating accounts, email invitations, shared edit/delete access and history, and private per-user category assignments. No contact management feature.

## Financial correctness and synchronization

- Store money exactly in minor currency units, never binary floating point. Keep expense calendar dates separate from UTC audit timestamps.
- Only personal shares consume budget. Repayments, if implemented, clear obligations without creating another expense.
- Carry both unused and overspent category budgets forward within the calendar year. Editing a yearly amount recalculates that whole year; January starts with zero carryover. Set the yearly total first and aim to assign it all to categories. Unallocated money is available to assign. Spending without a category budget reduces the overall balance. Allocations cannot exceed the total. See ADR 0021 for these rules, ADR 0013 for joint exact-cent rounding, and ADR 0006 for legacy rules.
- Use the versioned SwiftData store for iOS. Save domain mutations and their outbox entries together; never reset the store on an open/migration failure. The personal sync contract is in ADR 0009; keep prepared operation bytes immutable until acknowledged or explicitly resolved.
- Shared amount, payer, participants, and split must remain consistent as one revision.
- Route website and API writes through common contexts. Record mutations, revisions, shared history, and sync events atomically.
- Preserve local pending changes, make sync retries harmless, synchronize deletions, and surface conflicting financial edits. Do not use silent last-write-wins for conflicts.
- Authorize every operation. Shared expense access must never expose another user's categories, budgets, credentials, or private change feed.
- Verify shared financial examples against both Swift and Elixir implementations. Prioritize meaningful tests for financial rules, permissions, migrations, and sync failure/retry paths as code is added.

## Local development and operational data

- This checkout is inside OneDrive. Keep active SQLite databases, WAL files, backups, credentials, and real financial data outside the checkout in a host-local application-data directory.
- Keep real deployment hostnames, SSH aliases, and addresses in ignored local configuration only. iOS uses `ios/Configuration/Local.xcconfig`; deployment templates render from `deploy/local.json` into ignored `deploy/local/`. Run `python3 scripts/check-private-config` before committing related changes.
- Do not commit `.env` secrets, signing credentials, personal data, generated dependencies, or build output. Keep dependency lockfiles and shared Xcode project configuration under version control once generated.
- Use maintained authentication and WebAuthn libraries rather than implementing cryptography.
- Choose and record supported toolchain versions during scaffolding; do not invent build/test commands for code that does not exist.
- Run checks appropriate to actual changes. Documentation-only updates need link and consistency review, not placeholder application tests.
