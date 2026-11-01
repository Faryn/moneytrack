# iOS client

Working native SwiftUI personal ledger with offline storage. iOS leads the UX using standard tabs, navigation, lists, forms, sheets, menus, search, and date/category pickers.

## Current functionality

- Budget home: month selection, total remaining, allocation, positive/negative carryover, personal spending, and category budgets at a glance.
- Category detail: remaining amount, budget breakdown, matching expenses, and yearly amount editing.
- Yearly Plan: create/rename flat categories and enter yearly budgets. Edits recalculate the whole calendar year after confirmation; January resets carryover.
- Expense form: amount first, optional description, editable local-history category suggestions, today's date, and a secondary date picker. Comma/dot decimal amounts are exact, without thousands separators or silent rounding.
- Expense history: monthly spending, chronological rows, search, detail, edit, and confirmed deletion.
- Durable SwiftData saves with deletion tombstones and pending changes committed together. No connection is needed.
- Adaptive green/red amounts with labels/signs, system light/dark appearance, and vertically stacked layouts at accessibility sizes.

Account now supports username/password sign-in, explicit copying of unbound on-device entries into an empty account, manual sync, reauthentication, and sign-out. Credentials are held in Keychain; passwords are not saved. Conflicting records stay local until reviewed. Shared remains an honest empty state. Passkeys, invitations, and shared expenses are not implemented. Normal stores receive no seed data. The first interface is English with locale-formatted EUR amounts; full language/currency scope remains a release decision.

## Toolchain and run

- Xcode 27.2, recorded in [`.xcode-version`](../.xcode-version), with iOS SDK 27.2.
- Swift 6 with complete concurrency checking; minimum iOS 26.5 using the installed modern simulator runtime.
- No external Swift packages or CloudKit configuration.
- `local.moneytrack.ios` is a provisional bundle identifier. Choose the final identifier, team, and associated domain before device distribution and passkey setup.
- App icons are placeholders; release branding is not included.

Open `MoneyTrack.xcodeproj`, select the shared `MoneyTrack` scheme and an iPhone simulator, and run. Complete Xcode's license/first-run setup and install a supported runtime first. Budget setup guidance appears until you create categories and amounts.

## Build and tests

From the repository root:

```sh
scripts/check-ios
scripts/test-ios
```

Both scripts select `/Applications/Xcode.app` when `DEVELOPER_DIR` is not set, without changing system developer settings. The build check uses an unsigned generic simulator. Tests select an available iPhone with iOS 26.5 or later, preferring a booted device, and use local ad-hoc signing so Keychain works; no paid developer account is needed for these simulator checks. Set `MONEYTRACK_SIMULATOR_UDID` to choose a device. Derived data defaults to a temporary directory; `MONEYTRACK_DERIVED_DATA` can reuse a host-local directory and `MONEYTRACK_TEST_RESULTS` selects a new `.xcresult` path.

Verified on 2026-11-01: 19 unit/API tests and two simulator UI tests pass in the connected check. Coverage includes common financial examples, populated V1 migration, Keychain, stable retries, atomic pull, failed acknowledgment rollback, account/server isolation, explicit copying, revision conflicts, remote deletion, session expiry and re-login, and account restoration after relaunch. The regular `scripts/test-ios` run skips the two real-server checks when no isolated backend is configured.

UI tests use the debug-only `--ui-testing` namespace, `--reset-ui-testing-data`, `MONEYTRACK_TEST_TODAY`, and a separate Keychain service. Reset affects only that test namespace/service; normal local data and credentials are untouched. The real-server cases are enabled by `scripts/check-connected`, which uses a temporary database and synthetic accounts on loopback port 4004. The unit-test host skips normal app profile startup; each case opens its own temporary store. Never point these fixtures at a real backend.

## Persistence and next milestone

See [local storage](../docs/local-storage.md), [account/transport ADR](../docs/adr/0008-connected-accounts-and-transport.md), and [personal sync ADR](../docs/adr/0009-personal-sync-contract.md). SwiftData V2 retains V1 data and adds immutable prepared requests, server snapshots/revisions, and cursor/import state. Stores are isolated by server origin and account UUID. An explicit first-connection copy into an empty account preserves the original unbound store; merging independently populated ledgers is not implemented.

Run the Phoenix server and create an account using [server instructions](../server/README.md). For the simulator, a debug build can connect to `http://127.0.0.1:4000`. Physical devices and TestFlight need a reachable HTTPS server with a trusted certificate; production builds reject cleartext server addresses. Choose the final bundle identifier/team/domain before distribution and passkey enrollment. Optional passkeys and shared expenses follow; German/English NLP remains on-device and deferred.