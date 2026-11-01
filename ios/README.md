# iOS client

Native SwiftUI application with a shared `MoneyTrack` scheme and a standard navigation/empty-budget screen. There are no financial records, account screens, local persistence, or sync calls yet.

## Toolchain and project

- Xcode 27.2, recorded in [`.xcode-version`](../.xcode-version), with iOS SDK 27.2.
- Swift 6 language mode with complete concurrency checking.
- iPhone deployment target: iOS 26.5. This uses the available modern simulator runtime while building with the installed SDK. No older-device compatibility work is included.
- No external Swift packages or CloudKit configuration.
- `local.moneytrack.ios` is a provisional development bundle identifier; choose the final identifier, development team, and associated domain before device distribution and passkey setup.
- The app icon catalog is a placeholder; release branding is not included.

Open `MoneyTrack.xcodeproj` in Xcode, select the shared `MoneyTrack` scheme and an iPhone simulator, and run. Complete Xcode's license/first-run setup and install an appropriate simulator runtime first.

## Build check

From the repository root:

```sh
scripts/check-ios
```

The script uses `/Applications/Xcode.app` when `DEVELOPER_DIR` is not already set, without changing system developer settings. It builds for a generic iOS simulator, disables signing, and places derived data in a temporary directory. Set `MONEYTRACK_DERIVED_DATA` to reuse a chosen build directory outside the checkout.

The build was verified and the app was installed and launched on an iPhone 17 Pro simulator running iOS 26.5. The initial screen was visually checked. There is no iOS test target yet because no domain logic has been implemented; shared financial and persistence tests belong with that implementation.

## Next implementation

Prototype durable saving of an expense and its pending sync operation; SwiftData remains a candidate rather than an accepted persistence choice. Preserve pending work through restarts/session expiry and isolate stores by account.

The client will use the Phoenix API for username/password login, optional passkeys, expenses, budgets, shared history, and synchronization. Never connect to the server's SQLite file. On-device German/English parsing follows form-based entry and must not require cloud AI.

See [product specification](../SPEC.md), [sync proposal](../docs/data-model-and-sync.md), and [development plan](../docs/development.md).
