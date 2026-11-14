# 0013. Exact money, per-rate tax, UTC times and per-business document numbers

- **Status:** Accepted
- **Date:** 2026-11-14
- **Specs:** PLT-08; used by QTE-*, INV-*, PAY-*, SCH-*

## Context

Quotes, invoices and payments must add up to the cent and match what the client was shown.
Schedules must land at the right local time in every business's zone, through daylight-saving
changes. If each feature makes these choices itself, quotes and invoices drift apart. No feature
stores a price or a date yet, so this is the cheapest moment to settle them.

## Options considered

1. **The `money`/`money-rails` gems.** Mature, with many currencies and exchange rates. But a
   large API surface we would mostly not use, global configuration, and its own rounding
   defaults that we'd have to override anyway.
2. **Decimal columns (`decimal(12,2)`).** Exact, but every query and form has to agree on the
   scale, and nothing stops a Float creeping in.
3. **Integer minor units plus a small in-house `Money` value object**, with one pricing
   calculator shared by quotes and invoices.

## Decision

- **Money:** stored as integer minor units (`*_cents` columns) and handled as `Money` (amount
  plus currency). Floats are rejected at every entry point. A business has one currency; the
  launch currencies are USD, CAD, GBP, EUR and AUD. Display uses English number formatting with
  each currency's symbol (`$1,250.00`, `CA$12.00`, `€4.10`).
- **Rounding:** half-up (away from zero) to the cent, applied at each step that produces an
  amount: line amount, each discount, each tax rate.
- **Tax:** calculated **once per rate on the sum of the lines that carry it**, then rounded. Not
  per line, which would make totals depend on how lines are split. Rates on one line apply side
  by side, never compounded. Tax-inclusive pricing extracts the tax from each group of lines
  sharing the same rates and keeps the total the client saw.
- **Discounts:** a line discount (percent or fixed) comes off its line. A document discount comes
  off the subtotal and is spread across lines in proportion to their amounts, cent-exact, so each
  rate's base is right. Discounts never take a line below zero.
- **Time:** stored in UTC. Staff requests run in the current business's zone; jobs, mailers and
  PDFs wrap their work in `business.use_time_zone`. Date-only values (due dates, closures) are
  `date` columns and are never converted. Wall-clock times are built with `business.local_time`:
  a time skipped by spring-forward moves ahead an hour, and a repeated fall-back time takes its
  first occurrence. Zones are stored as IANA identifiers (`America/New_York`).
- **Identifiers:** client links use a random 24-character token (`HasPublicToken`), never a
  record id. Document numbers (`Q-0001`, `INV-0001`, `J-0001`) are sequential per business and
  kind, taken from a counter row with an atomic upsert: no duplicates under concurrency and no
  reuse after deletion. Gaps are allowed.

## Consequences

- `Money`, `HasMoney`, `Pricing::DocumentTotals`, `DocumentNumber` and `HasPublicToken` are the
  only way features do these things. Reviewers should reject floats, `Date.today` and ad-hoc
  totals.
- Multi-currency within one business, exchange rates and automatic sales-tax lookup stay out of
  scope. Adding a currency is a one-line data change.
- Locale-specific number formatting (`1.250,00 €`) is a later change to `Money#format` alone.
- **Cost:** none.
