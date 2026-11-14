---
id: PLT-08
title: Money, time & identifier conventions
domain: platform
milestone: M0
depends_on: [PLT-01]
---
# PLT-08 · Money, time & identifier conventions

> Requirements: [01-platform](../../plans/01-platform.md) R11

## Summary

Quotes, invoices and schedules are only trustworthy if amounts are exact and times are right
in the business's time zone. Establish shared conventions (and the small amount of shared
behavior behind them) before any feature stores a price or a date.

## User stories

- As an owner, I want totals that always add up to the cent so that clients trust my quotes.
- As a technician, I want visit times shown in my business's local time, even when travelling.
- As a developer, I want one obvious way to store, calculate and display money and time.

## Acceptance criteria

- [ ] Money is stored and calculated exactly (never floating point), always paired with a
      currency; rounding rules (per line vs per document, half-up vs banker's) are decided and
      documented.
- [ ] Shared formatting displays money in the business's currency and locale.
- [ ] Line-item math (quantity × unit price, line and document discounts, multiple tax rates,
      inclusive vs exclusive tax) has one shared, thoroughly tested implementation that quotes
      and invoices will both use.
- [ ] Times are stored in UTC and displayed in the business's time zone in staff views, client
      pages, emails and PDFs; date-only values (due dates, closures) are handled without zone
      drift.
- [ ] Daylight-saving transitions are covered by tests for scheduling-relevant calculations.
- [ ] Client-facing identifiers are non-guessable; document numbers (Q-0001, INV-0001) are
      sequential per business and never reused, even under concurrent creation.
- [ ] Conventions are documented in the contributor/agent guide.

## Out of scope

- Multi-currency within one business; currency conversion.
- Automated sales-tax calculation.

## Open questions

- ~~Should tax be calculated per line and summed, or on the document subtotal per rate?~~
  Resolved: per rate on the sum of the lines carrying it, rounded half-up (ADR 0013).
- ~~Which currencies are supported at launch?~~ Resolved: USD, CAD, GBP, EUR, AUD.
