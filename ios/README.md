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

Shared and Account show their disconnected state. Authentication, passkeys, shared expenses, invitations, and network sync are not implemented. No financial seed data is added. The first interface is English with locale-formatted EUR amounts; full language/currency scope remains a release decision.

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

Both scripts select `/Applications/Xcode.app` when `DEVELOPER_DIR` is not set, without changing system developer settings. The build check uses a generic simulator; tests select an available iPhone with iOS 26.5 or later, preferring a booted device. Set `MONEYTRACK_SIMULATOR_UDID` to choose one explicitly. Signing is disabled; derived data goes to a temporary directory. Set `MONEYTRACK_DERIVED_DATA` to reuse a host-local directory and `MONEYTRACK_TEST_RESULTS` to select a new `.xcresult` path, which must not already exist.

Verified on 2026-11-01: nine unit tests and one UI test pass on iPhone 17 Pro / iOS 26.5. Tests cover shared Swift/Elixir financial examples, exact amounts/dates, disk reopening, stable queued operations, tombstones, namespace isolation, and rollback when a read-only store refuses saving. The UI test creates budgets and an expense, relaunches, edits, deletes, and verifies an overspent category with a positive total.

UI tests use the debug-only `--ui-testing` namespace, `--reset-ui-testing-data`, and `MONEYTRACK_TEST_TODAY`. Reset affects only that isolated test store. Normal local-device and account namespaces are untouched. Unit tests use temporary directories.

## Persistence and next milestone

See [local storage](../docs/local-storage.md) and [ADR 0007](../docs/adr/0007-swiftdata-local-store-and-outbox.md). The versioned store does not reset on failure. The outbox is durable local groundwork, without a network sender, server revisions, acknowledgments, or conflict UI. A future account connection needs an explicit ownership/import flow and migrations that preserve queued work.

The next milestone is username/password authentication and personal-expense sync through the Phoenix API and website. Optional passkeys and shared expenses follow. Never connect to the server SQLite file. German/English on-device NLP follows reliable form entry and synchronization.
