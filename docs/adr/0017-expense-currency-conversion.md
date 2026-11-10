# ADR 0017: Save foreign expenses as fixed euro amounts

- Status: Accepted product behavior and implementation choice
- Date: 2026-11-04

## Decision

EUR is the reporting and budget currency. Enter foreign amounts through expense Details or a supported ISO currency code in Quick Entry. Preserve the original amount in that currency's minor units, its code, the decimal rate, rate date and ECB source with the resulting EUR cents. Ordinary totals, budgets, shared balances and repayments display EUR; original values appear in expense details.

Use the latest available ECB reference rate when entering a new amount. Rates quote foreign major units per EUR, so divide by the rate. Convert using exact decimal/integer arithmetic and round once to EUR cents, half up. Split that EUR amount with the existing payer-owned odd-cent rule. Both participants receive the same conversion in one common revision. Repayment recording remains in EUR and budget-neutral.

The supported currencies are the ECB feed currencies selected in the client/server lists; ISK, JPY and KRW have zero fractional digits, the other selected currencies have two. Unsupported or ambiguous currencies require correction, never reinterpretation as EUR. ECB values are reference estimates and may differ from a card issuer's actual charge; the app records expenses and debts, not payments.

## Rates and offline behavior

The native client fetches ECB's daily XML feed and caches the dated public rates in host-local app preferences. A failed refresh preserves the last valid snapshot and shows a saved-rate message and date. If no rate exists for the chosen currency, saving is disabled until a rate is downloaded. Ordinary EUR entry continues offline. No expense text or financial information is sent to ECB.

The online web companion fetches the same feed with a short in-process cache. Editing an unchanged original amount retains its saved rate, even when today's rate differs. Changing the original amount uses the latest available snapshot. Past expenses never reprice merely because rates update.

## Persistence and synchronization

SwiftData V5 adds a separate conversion record; V1–V4 model fields remain frozen. Save the expense, its conversion and outbox entry together. Preserve conversion metadata through reopen, copy/import, conflict resolution and sharing. SQLite adds nullable conversion maps to personal/shared expenses. Both website and API mutations use the same contexts and validate that the conversion equals the submitted EUR amount.

API v4 adds optional `conversion` to personal and shared payloads. It contains `originalAmount`, `originalCurrency`, `rate`, `rateDate`, and `source` (`ECB`). Old EUR-only pending payloads remain valid without changing their prepared bytes. Clients on v1–v3 receive 426 if their account contains a converted personal/shared record, preventing loss of provenance during edits. Existing conflict, authorization, retry, private-category and atomic history/feed rules remain in effect.

This extends [ADR 0009](0009-personal-sync-contract.md), [ADR 0012](0012-sharing-defaults-and-connected-flow.md), and [ADR 0014](0014-expense-action-and-currency-fields.md). It replaces the earlier EUR-only entry limitation; budget allocation and repayment rules are unchanged.

## Verification

Both implementations exercise USD/JPY/KRW/ISK examples, half-cent rounding, conversion before splitting, and payer-owned odd cents. Persistence and server tests exercise original-value preservation, immutable retries, rejection of inconsistent amounts, sharing with both accounts, and partial repayment without another expense. Connected checks verify the native v4 transport against the backend.

Source: [ECB euro foreign exchange reference rates](https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/index.en.html).

## Quick Entry symbol shortcuts

The user subsequently requested a symbols-only native keyboard accessory: €, $, £ and the region’s decimal separator. Bare $ means USD, £ means GBP and € means EUR; currency codes such as usd, gbp and jpy remain case-insensitive. Mixed conflicting currencies and unsupported symbols are rejected. UIKit text insertion preserves the current caret/selection. This resolves the earlier restriction on bare dollar signs.

The later combined keyboard decision in [ADR 0014](0014-expense-action-and-currency-fields.md) supersedes this accessory layout: digits and the decimal separator sit on an attached number row, while currency shortcuts sit inline with entry. Symbol meanings and conversion rules are unchanged.
