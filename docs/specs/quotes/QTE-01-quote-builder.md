---
id: QTE-01
title: Quote builder
domain: quotes
milestone: M2
depends_on: [CLI-01, CAT-03, CAT-04, PLT-08]
---
# QTE-01 · Quote builder

> Requirements: [05-quotes](../../plans/05-quotes.md) R1–R6

## Summary

The core screen of the product. An owner or admin builds a professional, accurate quote for a
client in under three minutes — on a phone in a driveway or at a desk — picking items from the
catalog, adjusting quantities and prices, and seeing totals update live.

## User stories

- As an owner standing at a client's house, I want to build a quote on my phone in a couple of
  minutes so that I can send it before I leave.
- As an admin, I want to add a one-off custom line item without adding it to the catalog.
- As an owner, I want to offer a discount and see exactly what the client will pay.

## Acceptance criteria

- [x] Owners/Admins create a draft quote for a client (picker or inline create) and optionally a
      property; the quote gets the next sequential number for the business.
- [x] Line items can be added from the catalog (copying name, description, unit, price, taxable)
      or as custom items; quantity, unit price and description are editable; items can be
      reordered and removed.
- [x] Discounts per line and/or on the whole quote, fixed or percentage.
- [x] Taxes apply per CAT-04 (default rates, per-line taxable flag, client exemption, per-quote
      override). Subtotal, discount, tax per rate, and total update live and use the shared
      PLT-08 calculation.
- [x] Quote fields: title, message to client, internal notes (never client-visible), terms
      (defaulted from settings, editable), expiry date (defaulted from settings), attachments
      (photos/PDFs, limited count/size).
- [x] Draft work is never lost on mobile (autosave or equivalent); drafts can be deleted.
- [x] A "preview as client" action is available (consumed by QTE-03 once built).
- [x] The builder is fast and usable at 360 px; adding an item is ≤ 3 taps from the builder.
- [x] Technicians cannot create or view quotes (pending the backlog toggle).
- [x] Tests cover totals math integration, numbering under concurrency, roles and tenancy.

## Out of scope

- Sending (QTE-04), PDF (QTE-02), client page (QTE-03), lifecycle/list (QTE-06).
- Optional/alternative items, templates, deposits (backlog).

## Open questions

- ~~Show per-line totals including or excluding tax?~~ Resolved: excluding; tax is summarized
  per rate below the lines.
- ~~Should a quote be able to cover multiple properties?~~ Resolved: no; one property per quote.

## Decisions

- #289, 2026-11-22: the quote and invoice builders save one way, as you go. "Save draft" only
  shows if autosave isn't running. Leaving within the app waits for the save, and asks first if
  it can't be saved; failures show in red by the header and by "Changes save as you go", worded
  by cause (errors to fix, signed out, retrying). "Send quote" / "Send invoice" match the send page.