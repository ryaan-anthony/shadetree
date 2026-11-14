---
id: CAT-08
title: Location pricing & taxes
domain: catalog
milestone: M5
depends_on: [CAT-07, CAT-04, QTE-01]
---
# CAT-08 · Location pricing & taxes

> Requirements: [03-catalog](../../plans/03-catalog.md) R18

## Summary

Branches often charge different prices and fall under different sales tax rules. Let a business
override catalog prices and default tax rates per location, so quotes and invoices pick up the
right numbers automatically.

## User stories

- As an owner, I want my city branch to charge more for the same service than my suburban one.
- As an admin, I want quotes from the county branch to apply the county's tax rate.

## Acceptance criteria

- [ ] For any catalog item, Owners/Admins can set a price override per location. Items with no
      override use the business default price.
- [ ] Each location can have its own default tax rate set (from the business's tax rates, CAT-04).
- [ ] Adding catalog items to a quote or invoice uses the document's location price and tax
      defaults. Changing the location on a draft offers to re-price the lines.
- [ ] The catalog shows, at a glance, which items have overrides at which locations.
- [ ] Changing overrides never alters existing documents.
- [ ] With a single location, none of this UI appears.
- [ ] Tests cover price resolution, tax defaults, re-pricing a draft and tenancy.

## Out of scope

- Time-based or seasonal pricing, price lists by client type (backlog).

## Open questions

- Should overrides also cover descriptions and units, or only price? Recommend price only.
