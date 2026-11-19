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

- [x] For any catalog item, Owners/Admins can set a price override per location. Items with no
      override use the business default price.
- [x] Each location can have its own default tax rate set (from the business's tax rates, CAT-04).
- [x] Adding catalog items to a quote or invoice uses the document's location price and tax
      defaults. Changing the location on a draft offers to re-price the lines.
- [x] The catalog shows, at a glance, which items have overrides at which locations.
- [x] Changing overrides never alters existing documents.
- [x] With a single location, none of this UI appears.
- [x] Tests cover price resolution, tax defaults, re-pricing a draft and tenancy.

## Out of scope

- Time-based or seasonal pricing, price lists by client type (backlog).

## Decisions

- **Overrides cover price only** (recommendation accepted), not descriptions or units.
- The main location always uses the business prices and the Taxes tab defaults; other locations
  use those too until given their own.
- Re-pricing is offered, never automatic, and only for what wasn't changed by hand: a catalog
  line still at the price of the location it was priced for, whose item has an override at the
  old or new location, and default taxes the draft still has. Each change is listed; staff use
  the new prices or keep theirs. Jobs and request quotes use location prices when lines are
  added; they don't offer re-pricing.

## Implementation notes

- `LocationPrice` (location, catalog item, `unit_price_cents`), `CatalogItem#price_at(location)`
  and `LocationPrice.cents_at` (batch). `locations.tax_rate_ids` (NULL: business defaults);
  `Location#default_tax_rates`; `TaxRate.for_new_document(client:, location:)`.
- The catalog picker sends the form's location (`catalog_items#search?location=`); quotes from
  requests take the location's prices. The item form has "Prices by location"; the list shows a
  badge per override; the location form has "Default taxes".
- `LocationRepricing` (quotes, invoices) with `priced_for_location_id`: while it differs from the
  location, the builder shows the offer (`admin/locations/_reprice`, buttons for a form outside
  the builder that save pending edits first). `PATCH reprice` (lock_version checked; `keep=1`
  keeps the prices) records a "repriced" event. Duplicates keep their pricing location, so a copy
  from an archived location is offered its new prices; duplicated catalog items keep overrides.
- Dev seeds: North yard charges $55 for lawn mowing and applies only the state tax.

## Open questions

- None.
