# iOS client

Working native SwiftUI personal ledger with offline storage. iOS leads the UX using standard tabs, navigation, lists, forms, sheets, menus, search, and date/category pickers.

## Current functionality

- Budget home: month selection, whole remaining budget, unallocated amount and unbudgeted spending details, allocation, positive/negative carryover, personal spending, and category budgets at a glance.
- Category detail: remaining amount, budget breakdown, matching expenses, and yearly amount editing.
- Yearly Plan: set the annual total first, then assign the full amount to flat categories. Spendie shows how much remains to assign. Allocations cannot exceed the total. Edits recalculate the calendar year after confirmation; January resets carryover. Legacy category budgets remain intact until explicit conversion.
- A compact floating plus appears above the native tab bar on Expenses only, with a subtle symbol animation, haptics, and an accessible Add Expense label. The plus opens a compact Quick Entry popover with a recognized-expense preview and direct Save. A compact sliders symbol opens the full form with parsed values prefilled; that form has amount first, optional description, and editable local-history category suggestions or No category. The full form shows date, currency and category creation directly; the date defaults to today. Comma/dot decimal amounts are exact, without thousands separators or silent rounding.
- Optional on-device Quick Entry recognizes a single amount and optional currency code, a description, and an existing category at the end in German or English. The popover previews recognized values before saving and can pass them into the full form; entry text stays on device. Invalid, ambiguous, and unsupported currencies must be corrected.
- Quick Entry keeps the system letter keyboard and docks a full-width row of digits plus the regional decimal separator above it. Currency symbol shortcuts (€, $, £) live beside the entry in a compact menu. Shortcut keys insert at the caret or replace selected text.
- Money entry uses aligned currency fields and decimal keyboards. EUR uses two decimal places; supported foreign currencies use their permitted precision. The expense keyboard offers Save Expense using the same validation as the top Save button.
- Expense history: monthly spending, chronological rows, search, detail, edit, and confirmed deletion.
- Durable SwiftData saves with deletion tombstones and pending changes committed together. No connection is needed.
- Adaptive green/red amounts with labels/signs, system light/dark appearance, and vertically stacked layouts at accessibility sizes.

Account now supports username/password sign-in, explicit copying of unbound on-device entries into an empty account, manual sync, reauthentication, and sign-out. Credentials are held in Keychain; passwords are not saved. Conflicting records stay local until reviewed. Account → Email for Sharing verifies mailbox ownership through an expiring code; this does not change username login or enable recovery. See the [verification contract](../docs/contracts/email-verification-v1.md). Shared supports verified invitations, pending proposals, accepted people/balances, common edit/delete history, private categories, and recorded repayments. Settle Up prefills the balance and supports partial recording without budget changes. Passkeys are not implemented. Normal stores receive no seed data. The interface supports English and German with locale-formatted EUR amounts; foreign-currency entry retains original values and dated ECB rates while reporting in EUR.

## Toolchain and run

- Xcode 27.2, recorded in [`.xcode-version`](../.xcode-version), with iOS SDK 27.2.
- Swift 6 with complete concurrency checking; minimum iOS 27.0 using the installed modern simulator runtime.
- No external Swift packages or CloudKit configuration.
- The app bundle identifier is `pg.spendie.ios`. Keep it aligned with App Store Connect; associated-domain setup for passkeys remains separate.
- App icon: the approved pine, sage and ivory wallet-and-coin artwork, packaged as an opaque 1024×1024 universal iOS asset. Original artwork and generation notes are in [design](../docs/design/app-icon.md).

Open `MoneyTrack.xcodeproj`, select the shared `MoneyTrack` scheme and an iPhone or iPad simulator, and run. Complete Xcode's license/first-run setup and install a supported runtime first. Budget setup guidance appears until you create categories and amounts.

Spendie uses the same app target and bundle ID on iPhone and iPad. Wide iPad windows use native split navigation in Budget, Expenses, and Shared. Narrow windows collapse the list and detail into a single column. iPad supports portrait and landscape, with Quick Entry anchored to the Expenses list and a sheet at accessibility text sizes.

## Build and tests

From the repository root:

```sh
scripts/check-ios
scripts/test-ios
```

Both scripts select `/Applications/Xcode.app` when `DEVELOPER_DIR` is not set, without changing system developer settings. The build check uses an unsigned generic simulator. Tests select an available iPhone with iOS matching the app deployment target or later, preferring a booted device, and use local ad-hoc signing so Keychain works; no paid developer account is needed for these simulator checks. Set `MONEYTRACK_SIMULATOR_UDID` to choose a device. Derived data defaults to a temporary directory; `MONEYTRACK_DERIVED_DATA` can reuse a host-local directory and `MONEYTRACK_TEST_RESULTS` selects a new `.xcresult` path.

Verified on 2026-11-02: 40 unit/API tests and three simulator UI tests pass in the isolated connected check. Coverage includes whole-year plans, budget allocation, exact monthly cents, populated V1/V2/V3 migration, frozen requests, rollback, namespace/copy/Keychain behavior, stale editors and source proposals, two-account sharing/private categories, repayments, conflicts, and deletion. UI checks exercise total-first setup, the Expenses-only floating plus, keyboard Save Expense, two-decimal currency fields, expense persistence, connection reuse, and partial repayment without budget changes. The regular `scripts/test-ios` run skips five real-server checks without the isolated backend. Release also builds successfully.

UI tests use the debug-only `--ui-testing` namespace, `--reset-ui-testing-data`, `MONEYTRACK_TEST_TODAY`, and a separate Keychain service. Reset affects only that test namespace/service; normal local data and credentials are untouched. The real-server cases are enabled by `scripts/check-connected`, which uses a temporary database and synthetic accounts on loopback port 4004. The unit-test host skips normal app profile startup; each case opens its own temporary store. Never point these fixtures at a real backend.

## Persistence and next milestone

See [local storage](../docs/local-storage.md), [account/transport ADR](../docs/adr/0008-connected-accounts-and-transport.md), and [personal sync ADR](../docs/adr/0009-personal-sync-contract.md). SwiftData V2 retains V1 data and adds immutable prepared requests, server snapshots/revisions, and cursor/import state. V3 preserves both earlier schemas and adds shared records plus exact source-acknowledgment dependencies. V4 adds whole-year plan records; populated V3 migration retains legacy budgets and prepared operations unchanged. Stores are isolated by server origin and account UUID. An explicit first-connection copy into an empty account preserves the original unbound store; merging independently populated ledgers is not implemented.

Run the Phoenix server and create an account using [server instructions](../server/README.md). For the simulator, a debug build can connect to `http://127.0.0.1:4000`. Physical devices and TestFlight need a reachable HTTPS server with a trusted certificate; production builds reject cleartext server addresses. Choose the final bundle identifier/team/domain before distribution and passkey enrollment. Shared synchronization and whole-year plans use API v3; optional passkeys follow; German and English Quick Entry recognition runs on device.
The [shared v2 contract](../docs/contracts/shared-sync-v2.md) describes verified acceptance, private assignment revisions, stable source transfer, record-only settlement, and old-client upgrade responses. Open shared editors retain the displayed revision, so background peer updates cannot silently rebase their writes.

## Private central server configuration

New sign-ins default to the centrally deployed instance supplied by ignored `Configuration/Local.xcconfig`. Copy `Configuration/Local.xcconfig.example` when setting up another checkout; real hostnames must stay out of Git. Both build configurations use `Configuration/App.xcconfig`. An unset default is reported in the sign-in form. Debug-only Development Server settings allow temporary local testing. UI tests exclusively use the explicit loopback test endpoint and never fall back to the central instance. Existing credentials/caches retain their original server identity. See [private deployment configuration](../deploy/README.md).

Currency conversion uses SwiftData V5 and API v4. The native client caches public ECB rates outside the checkout; saved conversions remain fixed, including through sharing and repayment. See [ADR 0017](../docs/adr/0017-expense-currency-conversion.md).

Account → Privacy is available before sign-in and works offline from the same notice served by the website at `/privacy`. The app includes its privacy manifest and system-encryption declaration. See [TestFlight preparation](../docs/testflight.md).

Verified on 2026-11-04: 95 backend tests, 48 native unit/API tests and three simulator UI tests pass, including the isolated connected checks. Release builds successfully. Conversion tests cover offline rate-cache preservation, published rate precision, V4-to-V5 migration, exact rounding before splits, retries, both participants, and budget-neutral repayment.

Sharing during entry: `5€ rewe shared with saskia` / `5€ rewe geteilt mit Saskia` selects an accepted connection, defaults to equal split with you paying, and shows your budget impact. Unknown or ambiguous names block quick save. Details offers person/payer/split controls. The source and sharing outbox records commit together. See [ADR 0018](../docs/adr/0018-sharing-at-entry-and-once-per-person.md).

The category in the Quick Entry preview opens a native menu of all categories and No category. Manual selections override recognition and carry through to Details and saving; clearing the entry restores automatic suggestions. Recognition runs once per input/category/connection change, with cached regexes and an empty-input fast path.

Quick Entry uses standard SwiftUI currency and category menus, with a Picker supplying category selection checkmarks and a wrapping menu label supporting large text. Its popover fits the available space using a Dynamic Type-scaled ideal width; accessibility sizes use a scrollable system sheet with stacked header and preview controls. Number-row legends retain keyboard-sized type. The UIKit text bridge preserves caret/selection insertion for both currency shortcuts and number-row keys.

The preview area stays present while typing. An incomplete edit such as `12.50a` keeps the last recognized amount dimmed with a short correction status, without collapsing the popover. That retained preview cannot be saved or passed to Details as a valid draft. Clearing the field clears it. Currency, category and sharing recognition remain strict, and correction immediately restores saving.

Shared presentation uses consistent grouped lists, capitalized display names, aligned monetary columns, a single prominent balance summary, and matching expense/repayment rows. Row layouts adapt to accessibility text sizes. Display capitalization does not rewrite usernames, descriptions or financial data.

Quick Entry keeps the native text keyboard and adds an attached number row (1–9, 0 and the regional decimal separator). Currency shortcuts (€, $, £) sit inline with the entry. Shortcuts insert at the caret or replace the selection. The parser recognizes € / EUR, $ / USD, £ / GBP and case-insensitive supported codes such as jpy. Conflicting currency declarations are rejected.

Maintain both languages in [Localizable.xcstrings](MoneyTrack/Localizable.xcstrings). English is the source language. Use SwiftUI localized labels or `String(localized:)` for dynamic UI copy and check the flow in both languages. The public privacy notices are bundled from the shared server resources.
