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

- [ ] Owners/Admins can create, edit, archive named tax rates (name, percentage) and mark one or
      more as the default set applied to taxable items.
- [ ] A business can have no tax rates; documents then show no tax lines.
- [ ] Each catalog item and document line item has a taxable flag; documents can override the
      applied rate set per document (e.g. tax-exempt client).
- [ ] Clients can be marked tax-exempt (consumed by CLI-01/QTE-01), which defaults new documents
      to no tax.
- [ ] Tax amounts follow the PLT-08 rounding convention and display per rate on documents.
- [ ] Editing or archiving a rate does not alter existing documents.
- [ ] Tests cover multiple rates, exempt clients, zero-rate businesses and role access.

## Out of scope

- Automatic tax lookup by address; tax filing reports (backlog via exports).
- Tax-inclusive pricing (prices that already include tax) — see open question.

## Open questions

- Is tax-inclusive pricing needed at launch (common outside the US)? Recommend support in the
  math (PLT-08) but expose the setting later.
