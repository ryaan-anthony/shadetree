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

- [ ] The summary strip is the single home for a record's status, key dates and headline
      amount.
- [ ] **Quote page:** the document card shows only what the strip doesn't: lines, totals,
      message, terms and files. It doesn't repeat "Prepared for", "Property", "Sent on",
      "Valid until", "Status" or the title as a second large heading (PLT-15). The client's
      response is said once.
- [ ] **Invoice page:** the balance is in the strip. The Payments card lists the payments and
      their total, without the balance again.
- [ ] **Client page:** an invoice's total appears in Work only. Balance shows money owed and
      paid, and the Timeline records events.
- [ ] Send history (the sent panel and its list of sends) and History or Activity are events,
      so their dates aren't repeats of the strip's.
- [ ] Rails on detail pages:
  - don't break a date over two lines ("Nov 22, / 2026");
  - don't cut text mid-word;
  - show their metadata (who and when) one step more muted than the content it describes.
- [ ] "View as client" still shows the full client document, with every field the client sees.
- [ ] Integration tests render the quote, invoice and client pages from fixtures. They fail when
      the strip's status, expiry or headline amount appears again in the quote's document
      card, or when the invoice strip's balance appears again in the Payments card. A system
      test checks the rail's dates don't wrap at 1280 px.
- [ ] Desktop (1280) and phone (390) screenshots of each detail page.

## Out of scope

- Changing what the client sees on their quote or invoice page, the PDF or emails.
- Page widths (PLT-16) and headers (PLT-15).

## Decisions

- The staff quote page drops the repeats from its document card. "View as client" shows the
  client's exact version (owner, 2026-11-22).
