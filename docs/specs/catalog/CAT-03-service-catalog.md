---
id: CAT-03
title: Service catalog
domain: catalog
milestone: M1
depends_on: [ACC-04, PLT-08]
---
# CAT-03 · Service catalog

> Requirements: [03-catalog](../../plans/03-catalog.md) R7, R8, R9, R11

## Summary

A business lists what it sells — services, products and common fees — with default prices,
so quotes and invoices can be built by picking items instead of typing them. Keep it simple: no
per-location pricing, bundles or pricing rules.

## User stories

- As an owner, I want to add my standard services with prices once so that quoting takes
  seconds.
- As an admin, I want to archive a service we no longer offer without breaking old quotes.
- As an owner, I want a trip fee to be just another item I can add.

## Acceptance criteria

- [ ] Owners/Admins can create, edit, duplicate, reorder, archive and restore catalog items.
- [ ] An item has: name, client-facing description, unit (from a short list such as each, hour,
      visit, sq ft, linear ft, plus custom), default unit price (may be blank = price on quote),
      taxable flag, optional estimated duration, optional category.
- [ ] Categories are a single optional level used for grouping in lists and pickers.
- [ ] Archived items are hidden from pickers but remain on existing documents unchanged.
- [ ] The catalog list is searchable and groups by category; it works on mobile.
- [ ] A reusable item picker (search, recent, by category) is available for quotes, invoices,
      jobs and the public request form.
- [ ] Price changes never alter existing documents (documents copy values when items are added).
- [ ] Technicians cannot view or edit the catalog.
- [ ] Tests cover validations, archive behavior, role access and tenancy.

## Out of scope

- Taxes (CAT-04). Presets (CAT-05). Options/add-ons, price lists, bundles (backlog).

## Open questions

- Should items have an internal cost to compute margin? Recommend backlog.
- Should the request form show all active services or only ones flagged "show on request form"?
  Recommend a per-item flag, default on.
