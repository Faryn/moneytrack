# ADR 0014: Compact expense action and consistent currency fields

- Status: Accepted
- Date: 2026-11-02

The user refined the entry flow: replace the large add button with a compact floating plus, visible only on Expenses. They also requested currency identification, aligned amounts, correct decimal places, and explicit split/repayment verification. The conveniently located keyboard action should save an expense rather than merely dismissing the keyboard.

## Decision

- Expenses has a trailing circular plus above the tab bar, with an accessible Add Expense label. Budget and Shared have no add action. Retain native animation/haptics and Reduce Motion support.
- Keep the standard top Save button and make the keyboard action Save Expense, calling the same validation and save method. Saving never requires dismissing the keyboard first.
- Use a common native currency field for personal/shared expense amounts, annual totals, category allocations, and repayments. Show EUR, align the editable amount to the trailing edge, use the decimal keyboard, and normalize valid input to exactly two decimal places when focus leaves. Invalid or overprecise input stays visible for correction; never silently round it.
- The website uses the same currency identification, trailing numeric alignment, decimal entry, and two-place normalization after editing. Keep exact string/integer parsing; do not introduce binary floating-point calculations.
- Currency display uses two fractional digits. Locale controls separators and currency presentation; the current implementation remains EUR.
- Verify split conservation, payer-owned odd cents, opposite participant balances, partial/full repayment in both directions, budget neutrality, invalid amounts, overpayments, stale confirmations, and duplicate-safe retries in Swift and Elixir tests.

This supersedes only the large all-tab expense action in [ADR 0013](0013-whole-year-budget-and-guilt-free-spending.md). Whole-year budget and guilt-free pool rules remain unchanged. Splitting and record-only settlement retain [ADR 0012](0012-sharing-defaults-and-connected-flow.md).

[ADR 0017](0017-expense-currency-conversion.md) extends currency entry beyond EUR, retaining euro reporting and exact minor-unit storage.

On 2026-11-04, the user refined Quick Entry to a small popover anchored to the Expenses plus, containing the language-entry field, a recognized-expense preview, direct Save, and one Details hint. Details opens the full form with parsed values preserved. Standard full-form and edit flows remain available.

A later polish replaces the written Details hint with an accessible sliders symbol beside Save, simplifies the entry styling, and shows amount/category without repeating the typed description.

The preview category is selectable from a native menu. Explicit choices, including Guilt-free spending, override automatic recognition and remain effective in Details; clearing the entry restores automatic suggestions.

The user subsequently chose inline currency controls and combined number/letter access. Quick Entry retains the standard system letter keyboard and adds a full-width input accessory row with digits 1–9, 0 and the regional decimal separator (comma or dot). Use a plain keyboard-style input view with ordinary key buttons, avoiding floating toolbar pills. Currency symbol shortcuts move into a compact menu beside the entry text. All shortcuts preserve UIKit caret/selection insertion. The single on-device language-entry field, recognized preview, category overrides, Details handoff and saving behavior remain intact. This replaces the symbols-only keyboard accessory described in [ADR 0017](0017-expense-currency-conversion.md).

The inline currency control uses a standard SwiftUI Menu beside the text field, rather than a manually sized UIKit left view. Category selection uses a standard Menu and Picker for native selection checkmarks, with a wrapping text label instead of manually drawn chevrons. The menu wrapper preserves the full label at accessibility sizes, where the standalone menu-style Picker clips its selected value. Quick Entry has a Dynamic Type-scaled ideal width instead of a fixed width; the system fits its presentation to the available space. Accessibility text sizes stack the heading/actions and amount/category and use a scrollable system sheet so controls remain reachable. Number-row legends retain keyboard-sized type rather than outgrowing their keycaps. UIKit remains only for the text insertion bridge and attached number row.

On 2026-11-05, the user requested a calmer appearance and stable recognition while correcting typing mistakes. The amount/category preview is always present; incomplete edits retain the last recognized preview in a muted style with a brief correction status. The preview is not a saveable draft: both Save and the Details handoff require the current successful parse, and clearing the field clears the retained result. Parsing and financial validation remain strict. The compact presentation uses a quieter Details symbol, consistent input spacing and a separate currency shortcut inset.
