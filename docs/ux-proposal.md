# App UX proposal

Status: iOS-led UX direction with the first personal-expense slice implemented natively. Confirmed: category budgets directly on Budget home, detail navigation, green/red amounts, the category-list variant, and Apple HIG with standard components. Sharing/account flows below remain design proposals; they do not approve outstanding invitation or repayment behavior.

## Main structure

Use three persistent native tabs, each with its own navigation stack:

1. **Budget**: selected month, prominent total remaining, and category budget breakdown directly below it. Each category shows spending, available monthly budget including carryover, and the amount left or overspent. Tap a category to open its details and expense list.
2. **Expenses**: a chronological, searchable log of personal and shared expenses, with the user's own-share spending total for the selected month. Tapping an expense opens its details and actions.
3. **Shared**: balances with accepted sharing partners, pending invitations where needed, and navigation to each person's shared expenses and repayments. Do not net amounts owed by different people into the spendable budget.

Provide Add Expense as a consistent toolbar action, not a navigation tab. Put account, passkeys, security, and sync status under a profile button. Keep Yearly Plan accessible from Budget home rather than burying it in account settings.

## Budget home

Lead with remaining budget and a compact explanation: monthly allocation + carryover − personal spending. Display a native category list underneath with disclosure navigation. This selected variant supports standard iOS behavior, longer names, and larger text settings.

Keep the total and each category's status independent: total remaining may be positive while one category is overspent. The overspent category must be visibly red and explicitly labeled. Use small progress indicators as supporting information; numbers and labels carry the meaning.

A category detail shows its allocation, carryover, spending, remaining amount, and matching expenses. The yearly plan edits flat category/year amounts and shows the resulting monthly allocations. Both unused and overspent balances carry within the year; yearly amount edits recalculate all twelve months with confirmation, as confirmed in ADR 0006.

Recent expenses are optional on Budget home once category budgets are present. Recommend leaving the full log in Expenses to keep the home screen focused.

## Quick entry

Open a native sheet with amount first, optional description, and a suggested editable category. Default the date to today with an additional date control for older entries. Saving returns immediately to the previous screen with updated balances and native success feedback. A View action remains an optional refinement; no mandatory sharing step.

Category suggestions should be easy to accept and override. Do not interpret a description such as Theodor as a person. Future on-device German/English parsing fills this same editable form rather than adding a separate chat interface.

## Sharing and expense detail

Expense detail distinguishes total purchase, user's personal budget impact, payer, private category, date, and sharing status. Shared rows must distinguish the personal share from the total purchase, without making users infer which number they are seeing.

The expense menu contains Share, Edit, and Delete. Share asks for email, payer, and All/Half/None for the current user's share, with a preview of personal spending and the resulting obligation before confirmation. Both participants can edit common fields and see shared history. Category assignments stay private.

Show a person's balance and activity in Shared, with a repayment action there. A repayment changes the interpersonal balance without changing budget spending. Pending-invitation effects and repayment confirmation remain the proposals already listed in the technical backlog.

## Amount colors

| Meaning | Color | Text/sign accompanies the color |
| --- | --- | --- |
| Budget remaining above zero | Green | Left / Remaining |
| Budget below zero | Red | Over budget and an explicit amount/sign |
| Expense outflow | Red | Expense context and an outflow sign where appropriate |
| Another person owes the user | Green | Owes you |
| User owes another person | Red | You owe |
| Planned allocation, totals without a direction, or zero balance | Neutral | Budget / Total / Settled up |

Use native semantic colors with sufficient contrast in light and dark appearance. Do not rely only on green/red, assign random colors to every category, or color a repayment as new income. Navigation/actions can retain the platform's accent color.

## Setup and exceptional states

Recommend short account setup followed by category/yearly-budget setup, with passkey enrollment optional. Let users start capturing expenses before completing their full yearly plan; the exact uncategorized fallback remains an open proposal. Before a budget exists, show setup guidance rather than a misleading zero-remaining success state.

Offline saves should be immediate. Show pending sync state unobtrusively and avoid blocking entry on network availability. A financial conflict should preserve both versions and ask for resolution, rather than silently changing a number. Use a confirmation for shared deletion that explains the effect on both budgets and the debt; personal deletion can offer Undo where feasible.

Use standard SwiftUI navigation, lists, forms, sheets, menus, search, and accessibility behavior. A web companion can use the same three conceptual destinations with layouts adapted to wider screens.

## First native implementation

Budget, Expenses, and Shared use system tabs and independent navigation stacks. Personal expenses support creation, detail, editing, deletion, and local persistence. Yearly Plan uses a native sheet and category editor; budget edits confirm year-wide recalculation. Entry offers exact comma/dot decimal amounts, visible validation, editable local-history suggestions, and an expandable native date picker. The initial interface is English with locale-formatted EUR amounts.

Shared currently has an honest empty state. Account now provides sign-in, explicit optional copying, sync/pending state, review, reauthentication, and sign-out. Login and personal sync use the real server; passkeys, sharing actions, and invitations remain unimplemented. Accessibility sizes stack category balances and expense amounts vertically; green/red colors adapt to light/dark appearance and retain text/signs.

Follow Apple's guidance on [tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars), [lists](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables), [sheets](https://developer.apple.com/design/human-interface-guidelines/sheets), [data entry](https://developer.apple.com/design/human-interface-guidelines/entering-data), and [color](https://developer.apple.com/design/human-interface-guidelines/color). Use system materials and controls. Cancel/Save belong on opposite sides of entry sheets; read-only root sheets have Close actions.
