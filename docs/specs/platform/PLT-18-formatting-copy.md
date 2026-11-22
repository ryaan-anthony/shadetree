---
id: PLT-18
title: "Design system: one format per data type, and the remaining copy fixes"
domain: platform
milestone: M6
depends_on: [PLT-08]
---
# PLT-18 · Design system: one format per data type, and the remaining copy fixes

> Requirements: [01-platform](../../plans/01-platform.md) R27

## Summary

The admin audit (#314, items 7 and 8) found money, dates, phones and quantities formatted in
several ways. #298 fixed phones on contact cards, internal codes, trade placeholders and "Nobody
yet". #280 fixed "0 of 0" and the plan's "(not included)". Some gaps remain:
- The Clients list shows phones as typed ("555.380.3141" beside "(555) 380-1200").
- A zero is "—" in the Jobs and Invoices lists but "$0.00" on Home and the client page.
- One date column mixes "Updated 5 minutes ago" with "Nov 22, 2026".
- Quantities are written three ways.
- Stripe payment IDs show on the job page and the client timeline.
Use one formatter per data type, everywhere. Triage: [#314 triage](../../audits/314-triage.md).

## User stories

- As an owner, I want the same thing written the same way on every page, so the app reads as
  finished and I can compare numbers at a glance.

## Acceptance criteria

- [ ] **Money:** every amount on staff pages goes through the money formatter (PLT-08). A real
      zero is "$0.00" everywhere, including the Jobs list's Value and the Invoices list's
      Balance. A dash means only "no amount yet" (an unpriced line in a builder). Amounts in
      tables are right-aligned with tabular figures.
- [ ] **Dates:** table columns show absolute dates, following #274's year rule. Relative times
      ("5 minutes ago") appear only in activity feeds: timelines, History, Notifications and
      Home's lists. The full weekday form ("Monday, Nov 23") appears only on Schedule, My day
      and visit pages. The relative time's exact date stays available on hover and to
      assistive technology, as today.
- [ ] **Phones:** every phone number on staff pages uses the phone formatter, including the
      Clients list, pickers, the request list and settings. Non-North-American numbers show as
      typed (the existing rule).
- [ ] **Quantities:** one style everywhere a line shows quantity and unit, in one text tone
      (see Open questions).
- [ ] **Internal identifiers** stay off owner-facing summaries. Stripe payment IDs show only in
      the invoice's Payments card, as a labelled reference for reconciliation. They don't
      appear on the job page or in the client timeline, as #298 did for request references.
- [ ] **Copy:**
  - The visit form's arrival note says "Times in Eastern Time (US & Canada)", not "In Eastern
    Time (US & Canada) time."
  - Pagination's "Showing 1–6 of 6" is one weight.
  - Menus size to their longest item, so "Duplicate for another client" doesn't wrap.
  - Joined strings ("Paid in all: $178.70", "Couldn't send (…)", "Emailed to … by …") keep
    their spaces in the accessibility tree as well as on screen, with a test that reads them.
- [ ] A test renders the Clients, Quotes, Jobs and Invoices lists and the client, job and
      invoice pages from the dev seeds. It fails on an unformatted phone, on "—" where an amount
      is zero, or on a relative time in a table column.

## Out of scope

- Currencies other than the business's own, and phone formats for other countries.
- Client-facing pages, PDFs and emails, which already use the same formatters.
- Rewording beyond the items listed (a general copy review is #289's, closed).

## Open questions

- The quantity style. **Recommendation:** "1 × $240.00" under the line name, as invoices show
  today. The quote document's Qty column stays as it is (it's the client's document), and
  "$45.00 / visit" in the services list keeps its unit in the same tone as the price.
- Clients list "Last activity": absolute or relative? **Recommendation:** absolute ("Nov 22")
  like other table columns, with the relative time on hover.
- A job with no items: "$0.00" or "No items"? **Recommendation:** "$0.00", the same as a zero
  anywhere else. The job page already says "No items yet".
