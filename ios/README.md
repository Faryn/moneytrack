# iOS client

Status: component directory reserved; no Xcode project generated yet.

## Agreed responsibilities

- Native SwiftUI navigation, forms, lists, menus, and system accessibility behavior.
- Personal expense entry, monthly remaining budget, and category drill-down.
- Local saving and offline operation, with pending changes synchronized through the Phoenix JSON API.
- Username/password login and optional native passkeys for the same server account.
- Shared expenses and change history, with private category assignment for the current user's share.
- On-device German/English parsing later; the initial form does not depend on AI.

## Before scaffolding

Select the actual stable Xcode/iOS target and record it here. Prototype local storage with an expense plus durable pending-operation save; SwiftData is the current candidate, not a settled storage decision. Keep account stores isolated and preserve pending work through authentication expiry.

The API and server database are separate from iOS persistence. Do not connect to the server's SQLite file or enable automatic CloudKit synchronization.

Add verified simulator build/test instructions and shared schemes when the Xcode project exists. Configure the app's associated domain after the production passkey relying party domain is chosen.

See [product specification](../SPEC.md), [sync proposal](../docs/data-model-and-sync.md), and [development plan](../docs/development.md).
