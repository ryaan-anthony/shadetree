---
id: PLT-20
title: "Design system: each fact once on detail pages"
domain: platform
milestone: M6
depends_on: [PLT-14, PLT-15]
---
# PLT-20 · Design system: each fact once on detail pages

> Requirements: [01-platform](../../plans/01-platform.md) R25

## Summary

The admin audit (#314, item 5 and the density notes) found detail pages stating the same fact
two or three times:
- The quote page shows status, sent date, expiry and total in its summary strip, then again in
  the document card.
- The invoice page shows the balance in its strip and in its Payments card.
- The rails are dense, with dates wrapping over two lines and text cut mid-word.

Give each fact one home per page, and let the document, not the metadata, lead.
Triage: [#314 triage](../../audits/314-triage.md).

## User stories

- As an owner, I want a detail page to tell me each thing once, so it's short and I trust it.

## Acceptance criteria

- [x] The summary strip is the single home for a record's status, key dates and headline
      amount.
- [x] **Quote page:** the document card shows only what the strip doesn't: lines, totals,
      message, terms and files. It doesn't repeat "Prepared for", "Property", "Sent on",
      "Valid until", "Status" or the title as a second large heading (PLT-15). The client's
      response is said once.
- [x] **Invoice page:** the balance is in the strip. The Payments card lists the payments and
      their total, without the balance again.
- [x] **Client page:** an invoice's total appears in Work only. Balance shows money owed and
      paid, and the Timeline records events.
- [x] Send history (the sent panel and its list of sends) and History or Activity are events,
      so their dates aren't repeats of the strip's.
- [x] Rails on detail pages:
  - don't break a date over two lines ("Nov 22, / 2026");
  - don't cut text mid-word;
  - show their metadata (who and when) one step more muted than the content it describes.
- [x] "View as client" still shows the full client document, with every field the client sees.
- [x] Integration tests render the quote, invoice and client pages from fixtures. They fail when
      the strip's status, expiry or headline amount appears again in the quote's document
      card, or when the invoice strip's balance appears again in the Payments card. A system
      test checks the rail's dates don't wrap at 1280 px.
- [ ] Desktop (1280) and phone (390) screenshots of each detail page.

## Implementation notes

- The staff quote page renders the client document with `header: false` (no kicker, title or
  meta), inside `#quote-document`, with the quote's photos and files under it. The client page,
  "View as client" and the PDF keep the header. The client's response lives in the Client
  response card; Activity records it as an event.
- The invoice's Payments card ends with "Paid" only; the balance is in `#invoice-summary`.
  History puts each event's time under its text. The client page already met its criterion;
  a check now keeps it so.
- Rails are `.rail` (quote, invoice, job, request and client pages): `.rail time` doesn't wrap,
  nothing in a rail is `truncate` or `break-all` (long addresses use `break-words`), and dates
  in a rail are `text-muted` under ink content. The quote's sent panel line moved to muted small
  text.
- Checks in `design_system_test.rb`: `quote_document_without_the_summary` (the strip's status,
  expiry and total, the meta labels, the title and the response, outside the lines and
  totals), `invoice_balance_once`, `client_invoice_totals_in_work`,
  `detail_side_column_is_a_rail`, `rail_text_isnt_cut` and `rail_metadata_is_muted`.
  `test/system/detail_rails_test.rb` measures rail dates at 1280 px on every detail page.
- Dev seeds: "Fall cleanup" (changes requested, then revised) has a photo, so its document card
  shows Photos and files.

## Out of scope

- Changing what the client sees on their quote or invoice page, the PDF or emails.
- Page widths (PLT-16) and headers (PLT-15).

## Decisions

- The staff quote page drops the repeats from its document card. "View as client" shows the
  client's exact version (owner, 2026-11-22).
- Accepted from the build (owner, 2026-11-23): the header line gives the property on one line
  and the client's company after their name; the staff quote page drops the client-facing status
  wording; History shows each time under its event; the Payments card's bold row is "Paid";
  contact details in a rail wrap rather than being cut.
- The document card's lines and totals are the document, so a line amount or the totals' Total
  matching the strip's isn't a repeat; the test checks the rest of the card.
- "One step more muted": content is ink (or subtle for notes), its who and when is muted.
