# Spendie MVP specification

Status: draft based on the product discussion. Items explicitly marked as assumptions need review before implementation.

## Purpose

A small personal expense tracker for fewer than ten users. The main question is: **How much of my budget is left this month?** Recording an expense should take only a few seconds. Budgeting should remain simpler than YNAB.

Design inspiration: [MoneyControl](https://apps.apple.com/us/app/moneycontrol-budget-tracker/id634892482) for quick capture and a straightforward budget overview, and [Dime](https://apps.apple.com/us/app/dime-budget-expense-tracker/id1635280255) for a native iOS-oriented experience. These are references, not requirements to reproduce their feature sets.

The primary client is a universal iPhone and iPad app using SwiftUI and standard system components wherever practical. On iPad, wide windows show the Budget, Expenses, or Shared list beside its detail. Narrow windows collapse that navigation into a single column. A small backend synchronizes data and serves an accompanying website. Expense creation must work offline and sync later.

## Confirmed scope

- Personal expenses are the default. Personal income is also supported as a separate booking type; it does not consume budgets or automatically change yearly plans. See [ADR 0019](docs/adr/0019-personal-income-bookings.md).
- A saved expense can be made shared through its action menu. Once connected, a person can also be selected during entry or named in Quick Entry.
- Only the user's personal share counts against their budget.
- Supported splits between two people are 100/0, 50/50, and 0/100.
- Shared expenses track how much is owed between people.
- Settle Up asks for an amount and records a full or partial repayment made outside the app. Repayments affect shared balances only; Spendie never initiates a payment.
- Shared expenses are visible to both participating users after accepting a direct email invitation. A separate contact list is not required.
- Either participant can edit or delete a shared expense; both can see its change history. Personal category assignments can be edited only by their owner.
- Set the whole yearly budget first, then assign the full amount to a flat list of categories. Allocations cannot exceed the total. Partially allocated plans can be saved while the user finishes setup.
- The unallocated amount is available to assign to categories. Expenses without a category budget are shown as unbudgeted spending and reduce the overall balance.
- Divide the yearly total and its parts into twelve monthly allocations, preserving exact cents and making the monthly parts equal the total.
- Unspent budget carries into the next month within the same calendar year.
- Overspending reduces the next month's available budget within the same year.
- Editing the yearly total or a category allocation recalculates all twelve months of that calendar year.
- Carryover resets on January 1. Historical expenses and shared balances remain.
- The Budget home screen emphasizes the total remaining monthly budget and shows category budgets broken down at a glance. Tapping a category opens its details and expenses.
- Use semantic amount colors: green for available budget and money owed to the user; red for overspending, spending outflows, and money the user owes. Pair colors with signs and clear labels.
- New expenses use a short form initially. Category suggestions assist entry.
- Optional natural-language entry supports German and English on device without cloud AI. Users review the filled form before saving.
- The date defaults to today; entering a different date is a secondary action.
- No dedicated refund workflow in the MVP. Users can delete an expense.
- Recurring expenses are deferred.

## Main screens and flows

### Home

- Display the selected month's total remaining budget prominently.
- Show the monthly allocation, carryover, and personal spending as supporting figures.
- Allow moving between months with the existing heading and previous/next arrows. Tapping the heading opens the native month-and-year wheel picker at the displayed month, with Done to apply and Cancel to keep the current selection. Budget and Expenses share the selected month.
- Keep expense creation on Expenses. Place a compact floating plus at the trailing bottom edge, above the iPhone tab bar or within the iPad list column. Give it an accessible Add Expense label and subtle system animation and haptics that respect Reduce Motion. Budget and Shared have no add button.
- Show money still unallocated for the year with direct access to Yearly Plan. Show unbudgeted spending separately with access to its expenses.
- Show category names, their monthly available budget (including carryover), personal spending, and remaining/overspent amounts directly on Budget home.
- Make each category row or tile a navigation target for its budget details and expenses.
- Keep the complete expense list in Expenses; whether to include recent expenses on Budget home remains a design choice.
- Provide access to balances owed to or by people without competing with the budget headline.

### Add expense

1. Tap the floating plus on Expenses to open a compact popover.
2. Type an amount, optional description and category in the Quick Entry field.
3. Review the recognized amount/category preview and save directly.
4. Use the compact Details symbol button to open the full form for date, currency, category changes or other settings. Parsed values carry into the form; manual entry remains available when parsing is incomplete.

Quick Entry uses standard SwiftUI menus and a category picker with native selection checkmarks and adaptive sizing. At accessibility text sizes, it uses a scrollable system sheet with stacked controls and wrapping category text so actions remain reachable; normal text retains the compact popover.

The amount/category preview remains visible from the start so ordinary typing does not resize the popover. During incomplete or invalid edits, retain the last recognized preview in a muted style with a short correction status; it is display-only and cannot be saved. Clearing the field clears that preview. Details and saving use only a valid parse of the current text, never the retained preview.

The date is today by default. The full form opened from the popover’s Details button shows date and currency settings directly, leaving room for future options. An example expense is amount `78 €`, description `Theodor`, category `Restaurants`. The description must not automatically be interpreted as a participant.

Report amounts in EUR and align editable amounts to the trailing edge. Expense entry identifies the selected currency and respects its fractional precision; EUR uses exactly two decimal places. Use a decimal keyboard and accept comma/dot decimals without rounding away extra digits.

Category selection is visible and editable. Suggest exact previously categorized descriptions, otherwise the most recent category when available. Users can override it, create a category, or choose No category. Saving without a category uses a private default category, creating it atomically with the expense and pending sync changes when necessary. Expense capture works before budget setup. Suggestions do not require cloud services. More sophisticated matching remains deferred.

Quick Entry accepts a single amount (EUR by default) with optional description and an existing category at the end, such as `78€, Theodor, Restaurants` or `78 euros at Theodor for Restaurants`. The compact popover previews the recognized EUR amount and category before saving. Tap the category to pick from the full flat list or choose No category. A manual choice overrides recognition and survives further typing and the Details handoff; clearing the entry resets that override. Invalid or ambiguous input cannot be saved; unrecognized category text remains in the description. Details opens the ordinary editable form with parsed values prefilled. Relative dates use Details. Supported currency codes such as USD, GBP and JPY are recognized case-insensitively. Signs map explicitly: € to EUR, $ to USD and £ to GBP. Conflicting currencies and unsupported symbols require correction. The standard letter keyboard has an attached full-width row of digits 1–9, 0 and the current region’s decimal separator, allowing amount and text entry without switching keyboards. An inline currency menu beside the entry offers €, $ and £ shortcuts. All shortcuts insert at the caret or replace selected text; currency symbols retain their explicit parser meanings.

Quick Entry can name an accepted person, for example `5€ rewe shared with saskia` or `5€ rewe geteilt mit Saskia`. Names resolve only against accepted connections, never a global directory. Unknown, missing or ambiguous names block saving. The preview shows the person, equal split and personal share; default payer is the entering user. The full form can change the person, payer and supported split. Native creation saves the source expense and sharing draft/outbox together. The website supports the same connected-person selection. See [ADR 0018](docs/adr/0018-sharing-at-entry-and-once-per-person.md).

### Make an expense shared

From a saved expense's action menu:

1. Select Share Expense.
2. Enter the other person's email address to invite them, or use an already accepted sharing relationship without another invitation.
3. Choose who paid; default to the current user.
4. Choose the current user's share: all, half, or none.
5. Confirm the personal budget impact and resulting debt.

The first acceptance establishes a reusable connection and accepts eligible current pending expenses between the two accounts. Further sharing needs no new acceptance. An accepted shared expense is one common record visible to both participants. Only each participant's own share counts against their budget. Each user selects a private category for their own share; the other participant cannot see their categories or budgets. Incoming shares initially use a private Uncategorized category. Count their personal shares as unbudgeted spending when the category has no allocation. The legacy zero-budget bootstrap adds no money to a whole-year plan. Existing owner budget choices are preserved. Invitation acceptance and delivery need connectivity, while invitation requests and edits can be queued offline. Applying a sharing proposal immediately changes the creator's budget consumption to their proposed personal share, even while the invitation is pending or waiting for synchronization; see [ADR 0010](docs/adr/0010-pending-share-budget-treatment.md). Recipient access still requires acceptance. Cancellation/decline effects and removal of an already accepted share remain open in the [data model and sync draft](docs/data-model-and-sync.md).

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

Shared uses consistent native grouped lists: body-sized names/titles, secondary date/status text, and trailing semibold monospaced amounts. A person’s detail screen emphasizes the net balance, followed by aligned expense and repayment rows. Green/red amounts retain direction labels and signs. Lowercase names and expense titles receive display-only capitalization; stored identifiers and entered text stay unchanged. Accessibility sizes stack row content rather than compressing it.

Participants are Spendie users connected through direct email invitations. A recipient without an account initially needs the administrator to create one; public invitation-led onboarding follows later. There is no separate contact-management feature or non-account placeholder debtor. Balance views are derived from actual sharing relationships. These choices are recorded in [ADR 0005](docs/adr/0005-shared-expenses-and-email-invitations.md).

Settle Up is confirmed in [ADR 0011](docs/adr/0011-record-only-settle-up.md). From a person's shared balance, open a native sheet with an editable amount, prefilled with the outstanding balance. Show the payer and recipient explicitly. Default the repayment date to today, with a secondary date control. Use **Record Repayment** for confirmation, with Cancel available. The app records a payment made elsewhere; it never moves money or asks for bank/payment details.

A partial repayment reduces what is owed; recording the full amount clears it. Display repayments alongside the shared expenses explaining that person's balance. Keep the current monthly budget, personal expense shares, and spending totals unchanged. Shared balances and repayment history do not reset in January.

Either participant can record a repayment immediately, visible to both without another acknowledgment, as accepted in [ADR 0012](docs/adr/0012-sharing-defaults-and-connected-flow.md). The initial flow supports full/partial amounts up to the current outstanding balance and rejects stale balance confirmations. Repayment corrections and overpayments are outside this version. Deleting a shared expense removes its spending and obligation while preserving separately recorded repayments; show the resulting balance before confirmation.

### Categories and budgets

Choose the total for a selected calendar year first. Then create or rename flat categories and allocate parts of the total to them. Show Assigned and Unallocated amounts during setup and mark the plan Fully allocated when the amounts match. Reject allocations above the total without changing financial data. A zero allocation removes the category budget. Existing category-only budgets remain readable until explicitly converted by saving the prefilled whole-year plan. Categories with historical expenses can be archived without losing history.

On iOS, yearly budget and category allocation inputs use the same body-sized currency presentation as adjacent values and show locale-appropriate thousands separators during entry. Grouping does not change the exact stored amount or silently round invalid input.

The category breakdown shows monthly allocation, carryover, spending, and remaining budget. Opening a category shows its expenses. Provide a yearly view of budget versus personal spending.

## Budget rules

For the overall budget and each allocated category in each month:

`remaining = monthly allocation + carryover from previous month - personal spending`

- January starts with zero carryover.
- The next month's carryover equals the previous month's remaining budget.
- Negative balances carry forward too, so overspending reduces the next month's available budget.
- The home total uses the sum of assigned monthly amounts and all personal-share spending. It equals the sum of category balances less cumulative unbudgeted spending. The unallocated annual amount stays available to assign.
- Overspending in an allocated category remains against that category and reduces the overall total.
- Use the expense date to assign spending to a calendar month.
- Making an expense shared adjusts budget usage in its original month, regardless of when sharing was configured.
- Editing, deleting, or recategorizing an expense recomputes affected balances through the rest of that year.
- Store money exactly in minor currency units. Divide the whole yearly amount by twelve, giving one extra cent to the first remainder months. Allocate category remainder cents jointly within those monthly totals, using the deterministic capacity rule in ADR 0013. Reserve the unallocated share for rounding only. Each part retains its exact annual amount, with monthly allocations differing by at most one cent. Legacy category-only budgets retain their original independent rounding.
- For an odd-cent equal split, assign the extra cent to the payer's share and show the exact amounts before confirmation.
- Changing the yearly total or a category allocation redistributes the plan across all twelve months of that year and recalculates remaining balances. The confirmation must make this effect clear.
- Resetting yearly budget carryover does not clear outstanding debts between people.

The carryover and yearly-edit rules are recorded in [ADR 0006](docs/adr/0006-calendar-year-budget-calculation.md). [ADR 0013](docs/adr/0013-whole-year-budget-and-guilt-free-spending.md) supersedes category-first setup and independent rounding for whole-year plans. [ADR 0021](docs/adr/0021-allocate-the-full-budget.md) separates money to assign from spending without a budget. Both implementations run the [whole-plan examples](docs/contracts/annual-plan-examples.json) and retain the [legacy calculation examples](docs/contracts/budget-examples.json).

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
- Provide an offline Privacy page in Account, including before sign-in, and a public website version. Explain local and server storage, shared visibility, on-device parsing, exchange-rate requests, beta diagnostics, and deletion/backup retention without claiming end-to-end encryption.
- Account recovery and the need for a recovery email remain undecided.
- Shared-expense invitations use email as recipient identity and must be accepted by an account that proves control of that address. This does not replace username login or settle email-based password recovery.

This authentication decision is recorded in [ADR 0004](docs/adr/0004-password-login-and-passkeys.md).

No bank connections or income tracking are required. Shared balance tracking does not imply bank transfers or payment processing.

## Platform and language

- Target the latest stable iOS version available when implementation starts; older-device support is not a priority.
- iOS leads the UX. Follow Apple's Human Interface Guidelines and prefer native SwiftUI navigation, forms, sheets, menus, lists, and accessibility behavior. The website adapts these flows to the web.
- Support standard Dynamic Type and light/dark appearance.
- Use green/red amount styling consistently in light and dark appearance, with sufficient contrast. Retain signed amounts and labels such as Left, Over budget, Owes you, and You owe so color is not the only signal.
- EUR is the default and reporting currency. Foreign-currency expenses use the latest available exchange rate at entry; retain the original amount and currency in the expense details and show the converted EUR amount elsewhere. Use the same saved EUR amount for budgets and shared balances. ECB reference rates provide conversions. The native app caches dated rates for offline entry; without a cached rate, foreign entry requires connectivity. See [ADR 0017](docs/adr/0017-expense-currency-conversion.md).
- Convert once when saving a foreign-currency expense and retain its original amount, currency, rate and rate date with the resulting exact EUR cents. Changes to published rates must not silently change past spending or debts. The saved EUR amount is the shared financial amount: calculate personal shares, odd cents and repayments in EUR, consistently for both participants. Preserve the original currency's permitted fractional precision; conversion must use exact decimal arithmetic with an explicit rounding rule.
- Provide complete English and German interfaces on iPhone, iPad, and the web, including accessibility, validation, and privacy text. iOS follows the app language and the website follows the browser language, with English as the fallback. Natural-language entry understands the documented patterns in both languages.
- Built-in iOS parsing must remain optional: the manual entry form always works without AI availability or connectivity.

## Acceptance examples

1. With a €12,000 yearly total and €6,000 assigned to a category, €6,000 remains unallocated for the year. The category gets €500 per month. Spending €100 without a category budget leaves €400 overall in January. Spending another €400 in the allocated category leaves it €100 and brings the overall balance to zero. February starts with €600 in that category and €500 overall.
2. Spending €550 against January's €500 leaves −€50. February starts with €450.
3. With a €500 allocation, saving a personal €78 expense leaves €422. Applying an equal split paid by the user changes remaining budget to €461 immediately, including while an invitation is pending. After acceptance both participants see the common expense and the other participant owes €39.
4. Settle Up suggests that €39 and allows editing the amount. Recording €15 received leaves €24 owed to the user; recording the remaining €24 clears the balance. The remaining budget stays €461 after each record, and no money is moved by the app.
5. An expense created offline appears immediately and reaches another signed-in device once synchronization completes, exactly once.
6. Deleting an expense restores its personal budget impact and removes its debt obligation. Repeated synchronization does not restore the deleted item.
7. January of the following year begins with that year's monthly allocation and no prior-year budget carryover. Outstanding debts remain visible.
8. An email recipient obtains an administrator-created account if needed, proves control of the invited address, and accepts sharing. Both participants can then view the same expense, while their category assignments and budgets remain private.
9. Either participant edits a shared expense. Both receive the updated expense and shared change history, with their own budget impact recalculated. Neither can edit or inspect the other's category assignment.

## Deferred features

- Voice-specific entry, receipt scanning, and receipt attachments.
- Shared budgets, multi-person expense groups, arbitrary percentage splits, and multiple payers.
- Dedicated refunds, recurring expenses, bank imports, account balances, and reconciliation.
- Offline website operation.
- Widgets, Shortcuts, and additional Apple platforms.

## Assumptions to review

The main unconfirmed choices include repayment correction policies and the website's initial scope. The remaining invitation lifecycle choices, removal of sharing, invitation onboarding and recovery, app distribution, and export/backup requirements still need decisions before release planning. Negative carryover and whole-year recalculation after a yearly budget edit are confirmed. Application-owned username/password authentication with optional passkeys, a Phoenix server, a SQLite storage backend, shared visibility through direct email invitations, and edit/delete access for both participants with shared history are accepted choices. See the [data model and sync proposal](docs/data-model-and-sync.md) for proposed implementation behavior.
