---
id: CAT-04
title: Tax rates
domain: catalog
milestone: M1
depends_on: [CAT-03]
---
# CAT-04 · Tax rates

> Requirements: [03-catalog](../../plans/03-catalog.md) R10

## Summary

Many service businesses must charge sales tax on some items. Let a business define named tax
rates and a default, so taxable line items are taxed correctly and documents show tax clearly.

## User stories

- As an owner, I want to set my local sales tax rate once so that quotes include it
  automatically.
- As an owner in a region with two taxes (e.g. state + county, or GST + PST), I want both to
  apply and show separately.
- As an owner whose services are not taxed, I want to turn tax off entirely.

## Acceptance criteria

- [x] Owners/Admins can create, edit, archive named tax rates (name, percentage) and mark one or
      more as the default set applied to taxable items.
- [x] A business can have no tax rates; documents then show no tax lines.
- [x] Each catalog item has a taxable flag. (The document line item's flag and the per-document
      override of the applied rate set, e.g. for a tax-exempt client, are document features:
      QTE-01 and INV-01.)
- [x] Clients can be marked tax-exempt (consumed by CLI-01/QTE-01), which defaults new documents
      to no tax.
- [x] Tax amounts follow the PLT-08 rounding convention, one amount per rate. (Showing them on
      documents is QTE-01/QTE-02 and INV-01.)
- [x] Editing or archiving a rate does not alter existing documents.
- [x] Tests cover multiple rates, exempt clients, zero-rate businesses and role access.

## Out of scope

- Automatic tax lookup by address; tax filing reports (backlog via exports).
- Tax-inclusive pricing (prices that already include tax) — see open question.

## Open questions

- ~~Is tax-inclusive pricing needed at launch (common outside the US)?~~ Resolved: the math
  supports it (PLT-08, `prices_include_tax:`); the business setting is exposed later.

## Implementation notes

- #289: with no tax rate, the builders hide the line's "Taxed" box (its value is kept) and Totals
  says there's no sales tax, linking to the rates for those who manage settings.
