---
id: PLT-18
title: "Design system: one format per data type, and the remaining copy fixes"
domain: platform
milestone: M6
depends_on: [PLT-08, PLT-14]
---
# PLT-18 · Design system: one format per data type, and the remaining copy fixes

> Requirements: [01-platform](../../plans/01-platform.md) R27

## Summary

The admin audit (#314, items 7 and 8) found money, dates, phones and quantities formatted in
several ways. #298 and #280 fixed most of the copy. What's left:
- The Clients list shows phones as typed ("555.380.3141" beside "(555) 380-1200").
- A zero is "—" in the Jobs and Invoices lists but "$0.00" on Home and the client page.
- One date column mixes "Updated 5 minutes ago" with "Nov 22, 2026".
- Quantities are written three ways.
- Stripe payment IDs show on the job page and the client timeline.

Use one formatter per data type, everywhere. Triage: [#314 triage](../../audits/314-triage.md).

## User stories

- As an owner, I want the same thing written the same way on every page, so I can compare at a
  glance.

## Acceptance criteria

- [x] **Money:** every amount on staff pages goes through the money formatter (PLT-08).
  - A real zero is "$0.00", including the Jobs list's Value and a paid invoice's Balance in the
    Invoices list.
  - A dash means only "no amount": a void invoice's Balance, or an unpriced line in a builder.
  - Amounts in tables are right-aligned with tabular figures. The Jobs list's "From" column (a
    document number) stays left-aligned.
- [x] **Dates:** table columns show absolute dates, following #274's year rule.
  - Relative times ("5 minutes ago") appear only in activity feeds: timelines, History,
    Notifications and Home's lists.
  - The full weekday form appears only on Schedule, My day and visit pages.
  - A relative time keeps its exact date on hover and for assistive technology.
- [x] **Phones:** every phone number on staff pages uses the phone formatter, including the
      Clients list, the pickers and the request list. Non-North-American numbers show as typed.
- [x] **Quantities:** a line shows "1 × $240.00" under its name, as invoices do. The client
      document's Qty column is unchanged. Units are in the same text tone as the number
      ("$45.00 / visit").
- [x] **Internal identifiers:** Stripe payment IDs show only in the invoice's Payments card, as
      a labelled reference. They don't appear on the job page or in the client timeline.
- [x] **Copy:**
  - The visit form's arrival note reads "Times in Eastern Time (US & Canada)".
  - Pagination's "Showing 1–6 of 6" is one weight.
  - Joined strings ("Paid in all: $178.70", "Couldn't send (…)", "Emailed to … by …") keep
    their spaces in the page's text, with a test.
- [x] Integration tests render the Clients, Quotes, Jobs and Invoices lists and the client, job
      and invoice pages from fixtures. They fail on:
  - an unformatted phone;
  - "—" where an amount is zero;
  - a relative time in a table column;
  - a Stripe ID outside the Payments card.
- [ ] Desktop (1280) and phone (390) screenshots of the four lists and the client page.

## Out of scope

- Other currencies and other countries' phone formats.
- Client-facing pages, PDFs and emails, which already use the same formatters.
- Menus whose items wrap (PLT-19).

## Implementation notes

- Part 1: `money` everywhere a zero showed "—" (a void invoice's Balance keeps it); `line_quantity`
  writes "1 visit × $120.00" under a line on the job, invoice and visit pages (the quantity
  alone where prices are hidden from technicians); Stripe's reference is
  "Stripe reference: pi_…" in the invoice's Payments card only (the job's payment list and the
  history text keep a recorded payment's own reference, like a check number). Checks
  `zero_is_money` and `stripe_ids_only_in_payments` run on every staff page; copy guards are in
  `test/integration/admin/formatting_test.rb`.
- Part 2: `contact_value` formats a client's phone in the Clients list, the picker (search JSON
  and the chosen client), duplicate matches and the import preview. `local_date_ago` shows an
  absolute date with "3 days ago" on hover, for tables and lists outside activity feeds;
  `local_time_ago` (feeds only) adds the exact time for screen readers. Requests, Help, Team,
  the client page's Requests and Emails cards and a few notes moved to absolute dates; the
  request and revision pages and the job's Visits card lost the full weekday. Checks
  `phones_formatted`, `absolute_dates_in_tables` and `full_weekday_only_where_planned`.
- Not changed: the quote revision page keeps Qty and Price (it is the document as sent); a draft
  invoice's Balance is its amount (only void has none); the operator console and the account
  page's sign-in list are out of scope.
- Dev seeds: Grace Chen (phone typed "555.380.3141") has a paid and a void invoice.

## Decisions

- Quantities: "1 × $240.00" under the line name; the client document's Qty column stays; units
  in the same tone (owner, 2026-11-22).
- Clients "Last activity" shows an absolute date, with the relative time on hover (owner,
  2026-11-22).
- A job with no items shows "$0.00", like any zero (owner, 2026-11-22).
- A void invoice's balance stays "—", as there's nothing to pay (review of #332).
- A draft invoice's Balance shows its amount, not "—" (owner, 2026-11-23).
