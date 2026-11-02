# MoneyTrack MVP specification

Status: draft based on the product discussion. Items explicitly marked as assumptions need review before implementation.

## Purpose

A small personal expense tracker for fewer than ten users. The main question is: **How much of my budget is left this month?** Recording an expense should take only a few seconds. Budgeting should remain simpler than YNAB.

Design inspiration: [MoneyControl](https://apps.apple.com/us/app/moneycontrol-budget-tracker/id634892482) for quick capture and a straightforward budget overview, and [Dime](https://apps.apple.com/us/app/dime-budget-expense-tracker/id1635280255) for a native iOS-oriented experience. These are references, not requirements to reproduce their feature sets.

The primary client is a native iOS app using SwiftUI and standard system components wherever practical. A small backend synchronizes data and serves an accompanying website. Expense creation must work offline and sync later.

## Confirmed scope

- Personal expenses are the default.
- A saved expense can be made shared through its action menu.
- Only the user's personal share counts against their budget.
- Supported splits between two people are 100/0, 50/50, and 0/100.
- Shared expenses track how much is owed between people.
- Settle Up asks for an amount and records a full or partial repayment made outside the app. Repayments affect shared balances only; MoneyTrack never initiates a payment.
- Shared expenses are visible to both participating users after accepting a direct email invitation. A separate contact list is not required.
- Either participant can edit or delete a shared expense; both can see its change history. Personal category assignments can be edited only by their owner.
- Set the whole yearly budget first, then allocate parts of it to a flat list of categories. Allocations cannot exceed the total.
- The unallocated amount is one guilt-free spending pool. Expenses in any category without a positive allocation, including uncategorized expenses, use that pool.
- Divide the yearly total and its parts into twelve monthly allocations, preserving exact cents and making the monthly parts equal the total.
- Unspent budget carries into the next month within the same calendar year.
- Overspending reduces the next month's available budget within the same year.
- Editing the yearly total or a category allocation recalculates all twelve months of that calendar year.
- Carryover resets on January 1. Historical expenses and shared balances remain.
- The Budget home screen emphasizes the total remaining monthly budget and shows category budgets broken down at a glance. Tapping a category opens its details and expenses.
- Use semantic amount colors: green for available budget and money owed to the user; red for overspending, spending outflows, and money the user owes. Pair colors with signs and clear labels.
- New expenses use a short form initially. Category suggestions assist entry.
- Natural-language entry is a later enhancement, supporting German and English using built-in iOS capabilities only. No cloud AI.
- The date defaults to today; entering a different date is a secondary action.
- No dedicated refund workflow in the MVP. Users can delete an expense.
- Recurring expenses are deferred.

## Main screens and flows

### Home

- Display the selected month's total remaining budget prominently.
- Show the monthly allocation, carryover, and personal spending as supporting figures.
- Allow moving between months.
- Keep expense creation on Expenses: use a compact trailing floating plus above the native tab bar, with an accessible Add Expense label and subtle system animation/haptics that respect Reduce Motion. Budget and Shared have no add button.
- Show the guilt-free pool's remaining amount and allow opening its spending details.
- Show category names, their monthly available budget (including carryover), personal spending, and remaining/overspent amounts directly on Budget home.
- Make each category row or tile a navigation target for its budget details and expenses.
- Keep the complete expense list in Expenses; whether to include recent expenses on Budget home remains a design choice.
- Provide access to balances owed to or by people without competing with the budget headline.

### Add expense

1. Enter an amount.
2. Enter an optional description, such as `Theodor` (the restaurant name).
3. Accept or change the suggested category.
4. Save immediately to local storage using the top Save or the reachable keyboard Save Expense action.

The date is today by default and can be changed through an additional control. An example expense is amount `78 €`, description `Theodor`, category `Restaurants`. The description must not automatically be interpreted as a participant.

All monetary fields show EUR and align editable amounts to the trailing edge. Use a decimal keyboard and exactly two fractional digits after editing; accept comma/dot decimals without rounding away extra digits. Display money with two decimal places.

Category selection is visible and editable. Suggest exact previously categorized descriptions, otherwise the most recent category when available. Users can override it, create a category, or leave the selection as Guilt-free spending. Saving without a category uses a private default category, creating it atomically with the expense and pending sync changes when necessary. Expense capture works before budget setup. Suggestions do not require cloud services. More sophisticated matching remains deferred.

### Make an expense shared

From a saved expense's action menu:

1. Select Share Expense.
2. Enter the other person's email address to invite them, or use an already accepted sharing relationship without another invitation.
3. Choose who paid; default to the current user.
4. Choose the current user's share: all, half, or none.
5. Confirm the personal budget impact and resulting debt.

An accepted shared expense is one common record visible to both participants. Only each participant's own share counts against their budget. Each user selects a private category for their own share; the other participant cannot see their categories or budgets. Incoming shares initially use a private Uncategorized category, drawing from guilt-free spending unless explicitly allocated. The legacy zero-budget bootstrap adds no money to a whole-year plan. Existing owner budget choices are preserved. Invitation acceptance and delivery need connectivity, while invitation requests and edits can be queued offline. Applying a sharing proposal immediately changes the creator's budget consumption to their proposed personal share, even while the invitation is pending or waiting for synchronization; see [ADR 0010](docs/adr/0010-pending-share-budget-treatment.md). Recipient access still requires acceptance. Cancellation/decline effects and removal of an already accepted share remain open in the [data model and sync draft](docs/data-model-and-sync.md).

Either participant can edit the common description, amount, date, payer, and split, or delete the shared expense. A history visible to both records the actor, time, and shared changes, including deletion. Private category changes are not exposed to the other participant. Financial changes update each person's budget and their shared balance consistently; concurrent changes use the conflict handling described below.

Examples for an expense of €78:

| Paid by | User's share | User's budget usage | Resulting obligation |
| --- | --- | --- | --- |
| User | 100% | €78 | None |
| User | 50% | €39 | Other person owes user €39 |
| User | 0% | €0 | Other person owes user €78 |
| Other person | 100% | €78 | User owes other person €78 |
| Other person | 50% | €39 | User owes other person €39 |
| Other person | 0% | €0 | None |

The category describes the current user's budget impact. Shared budget management and groups of more than two participants per expense are outside the MVP.

### People and repayments

Show each person's net balance and the expenses and repayments behind it. Obligations in opposite directions offset each other for that person.

Participants are MoneyTrack users connected through direct email invitations. A recipient without an account initially needs the administrator to create one; public invitation-led onboarding follows later. There is no separate contact-management feature or non-account placeholder debtor. Balance views are derived from actual sharing relationships. These choices are recorded in [ADR 0005](docs/adr/0005-shared-expenses-and-email-invitations.md).

Settle Up is confirmed in [ADR 0011](docs/adr/0011-record-only-settle-up.md). From a person's shared balance, open a native sheet with an editable amount, prefilled with the outstanding balance. Show the payer and recipient explicitly. Default the repayment date to today, with a secondary date control. Use **Record Repayment** for confirmation, with Cancel available. The app records a payment made elsewhere; it never moves money or asks for bank/payment details.

A partial repayment reduces what is owed; recording the full amount clears it. Display repayments alongside the shared expenses explaining that person's balance. Keep the current monthly budget, personal expense shares, and spending totals unchanged. Shared balances and repayment history do not reset in January.

Either participant can record a repayment immediately, visible to both without another acknowledgment, as accepted in [ADR 0012](docs/adr/0012-sharing-defaults-and-connected-flow.md). The initial flow supports full/partial amounts up to the current outstanding balance and rejects stale balance confirmations. Repayment corrections and overpayments are outside this version. Deleting a shared expense removes its spending and obligation while preserving separately recorded repayments; show the resulting balance before confirmation.

### Categories and budgets

Choose the total for a selected calendar year first. Then create or rename flat categories and allocate parts of the total to them. Show Assigned and Guilt-free amounts during setup; reject allocations above the total without changing financial data. A zero allocation means that category uses the shared guilt-free pool. Existing category-only budgets remain readable until explicitly converted by saving the prefilled whole-year plan. Categories with historical expenses can be archived without losing history.

The category breakdown shows monthly allocation, carryover, spending, and remaining budget. Opening a category shows its expenses. Provide a yearly view of budget versus personal spending.

## Budget rules

For the whole budget, each allocated category, and the guilt-free pool in each month:

`remaining = monthly allocation + carryover from previous month - personal spending`

- January starts with zero carryover.
- The next month's carryover equals the previous month's remaining budget.
- Negative balances carry forward too, so overspending reduces the next month's available budget.
- The home total uses the whole monthly allocation and all personal-share spending. It equals allocated-category remaining amounts plus the guilt-free pool. Unallocated category rows label pool spending and are not added again.
- Overspending in an allocated category remains against that category and reduces the overall total. It does not automatically consume the guilt-free pool.
- Use the expense date to assign spending to a calendar month.
- Making an expense shared adjusts budget usage in its original month, regardless of when sharing was configured.
- Editing, deleting, or recategorizing an expense recomputes affected balances through the rest of that year.
- Store money exactly in minor currency units. Divide the whole yearly amount by twelve, giving one extra cent to the first remainder months. Allocate category remainder cents jointly within those monthly totals, using the deterministic capacity rule in ADR 0013; the guilt-free pool takes the remaining capacity. Each part retains its exact annual amount, with monthly allocations differing by at most one cent. Legacy category-only budgets retain their original independent rounding.
- For an odd-cent equal split, assign the extra cent to the payer's share and show the exact amounts before confirmation.
- Changing the yearly total or a category allocation redistributes the plan across all twelve months of that year and recalculates remaining balances. The confirmation must make this effect clear.
- Resetting yearly budget carryover does not clear outstanding debts between people.

The carryover and yearly-edit rules are recorded in [ADR 0006](docs/adr/0006-calendar-year-budget-calculation.md). [ADR 0013](docs/adr/0013-whole-year-budget-and-guilt-free-spending.md) supersedes category-first setup and independent rounding for whole-year plans. Both implementations run the [whole-plan examples](docs/contracts/annual-plan-examples.json) and retain the [legacy calculation examples](docs/contracts/budget-examples.json).

## Offline operation and synchronization

- Create, view, edit, delete, categorize, and share expenses using locally stored data while offline.
- Queue changes and synchronize automatically when connectivity returns.
- Keep a clear local saved state even when synchronization is pending or fails.
- Repeating synchronization must never duplicate an expense, repayment, or sharing action.
- Synchronize deletions so an item does not reappear from another device.
- Keep an expense's payer and split consistent when syncing; budget usage and debts must derive from the same saved version.
- Preserve conflicting edits for review rather than silently discarding financial changes. Show the local draft and server version for explicit review; a whole-year plan is resolved as one record.

## Website and backend

Assumption: the website is an online companion supporting expense entry and editing, category and yearly budget management, monthly review, shared balances, and repayment entry. Offline website support is deferred.

The application operates its own backend for accounts, authenticated access, per-user data isolation, synchronization, and persistent storage. Use SQLite on the server; CloudKit is not selected. The website and sync API remain one application as recorded in [ADR 0001](docs/adr/0001-single-repository-and-combined-server.md). Application-owned authentication and server storage are recorded in [ADR 0002](docs/adr/0002-own-authentication-and-sqlite-backend.md). Hosting is the local application host VM, with nginx on proxy-host forwarding over Tailscale at app.example.invalid; see [ADR 0015](docs/adr/0015-app-host-deployment.md). Keep operations appropriate for fewer than ten users.

Implement the server in Elixir with Phoenix: LiveView for the online website, a JSON API for iOS, and Ecto with SQLite for database access and migrations. Website and API writes use the same application contexts. This stack is recorded in [ADR 0003](docs/adr/0003-phoenix-server.md).

### Login

Accounts are initially created by the administrator, with no public signup. Shared-invitation onboarding follows later. Use HTTPS for transport; ordinary server-readable storage is accepted and end-to-end encryption is not required. Each account can access only its own personal ledger.

Existing on-device data stays separate on sign-in unless the user explicitly chooses a one-time copy into an empty account. Originals remain on the device. Connected stores are isolated by server and account identity; changing accounts never submits another account's pending work.

- Sign in using a username and password on iOS or the website.
- After signing in, optionally enroll a passkey for future passwordless sign-in to the same account.
- Allow viewing and revoking enrolled passkey credentials in account settings; retain password login as an alternative.
- Passkeys are an alternative login method, not a mandatory second factor or a separate account.
- Keep saved local expenses available offline when a session expires; reconnecting sync may require reauthentication.
- Account recovery and the need for a recovery email remain undecided.
- Shared-expense invitations use email as recipient identity and must be accepted by an account that proves control of that address. This does not replace username login or settle email-based password recovery.

This authentication decision is recorded in [ADR 0004](docs/adr/0004-password-login-and-passkeys.md).

No bank connections or income tracking are required. Shared balance tracking does not imply bank transfers or payment processing.

## Platform and language

- Target the latest stable iOS version available when implementation starts; older-device support is not a priority.
- iOS leads the UX. Follow Apple's Human Interface Guidelines and prefer native SwiftUI navigation, forms, sheets, menus, lists, and accessibility behavior. The website adapts these flows to the web.
- Support standard Dynamic Type and light/dark appearance.
- Use green/red amount styling consistently in light and dark appearance, with sufficient contrast. Retain signed amounts and labels such as Left, Over budget, Owes you, and You owe so color is not the only signal.
- Assumption: EUR is the only currency in the MVP.
- Assumption: provide German and English interface text; future natural-language entry must understand both languages.
- Built-in iOS parsing must remain optional: the manual entry form always works without AI availability or connectivity.

## Acceptance examples

1. A €12,000 yearly total allocates €1,000 per month. Assigning €6,000 to a category gives it €500 per month and leaves €500 guilt-free. Spending €100 in an unallocated category leaves €400 guilt-free and €900 overall. Spending €400 in the allocated category in January leaves it €100; February starts with €600 available in that category.
2. Spending €550 against January's €500 leaves −€50. February starts with €450.
3. With a €500 allocation, saving a personal €78 expense leaves €422. Applying an equal split paid by the user changes remaining budget to €461 immediately, including while an invitation is pending. After acceptance both participants see the common expense and the other participant owes €39.
4. Settle Up suggests that €39 and allows editing the amount. Recording €15 received leaves €24 owed to the user; recording the remaining €24 clears the balance. The remaining budget stays €461 after each record, and no money is moved by the app.
5. An expense created offline appears immediately and reaches another signed-in device once synchronization completes, exactly once.
6. Deleting an expense restores its personal budget impact and removes its debt obligation. Repeated synchronization does not restore the deleted item.
7. January of the following year begins with that year's monthly allocation and no prior-year budget carryover. Outstanding debts remain visible.
8. An email recipient obtains an administrator-created account if needed, proves control of the invited address, and accepts sharing. Both participants can then view the same expense, while their category assignments and budgets remain private.
9. Either participant edits a shared expense. Both receive the updated expense and shared change history, with their own budget impact recalculated. Neither can edit or inspect the other's category assignment.

## Deferred features

- German/English natural-language entry, including strings such as `78€, Theodor, Restaurants`.
- Voice-specific entry, receipt scanning, and receipt attachments.
- Shared budgets, multi-person expense groups, arbitrary percentage splits, and multiple payers.
- Dedicated refunds, recurring expenses, bank imports, income, account balances, and reconciliation.
- Multiple currencies and offline website operation.
- Widgets, Shortcuts, and additional Apple platforms.

## Assumptions to review

The main unconfirmed choices are EUR-only operation, repayment correction policies, the website's initial scope, and interface languages. The first local iOS slice displays EUR and English interface text; it does not settle the release's currency/language scope. The remaining invitation lifecycle choices, removal of sharing, invitation onboarding and recovery, app distribution, and export/backup requirements still need decisions before release planning. Negative carryover and whole-year recalculation after a yearly budget edit are confirmed. Application-owned username/password authentication with optional passkeys, a Phoenix server, a SQLite storage backend, shared visibility through direct email invitations, and edit/delete access for both participants with shared history are accepted choices. See the [data model and sync proposal](docs/data-model-and-sync.md) for proposed implementation behavior.
