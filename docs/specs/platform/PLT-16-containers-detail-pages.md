---
id: PLT-16
title: "Design system: two layout containers, and each fact once on detail pages"
domain: platform
milestone: M6
depends_on: [PLT-05, PLT-15]
---
# PLT-16 · Design system: two layout containers, and each fact once on detail pages

> Requirements: [01-platform](../../plans/01-platform.md) R25

## Summary

The admin audit (#314, items 4 and 5) found page widths changing by page type. Forms are narrow
columns next to empty space, and detail pages state the same fact two or three times. #301
rebuilt Home to fill the screen, and #303 gave three long forms a summary beside them. The rest
still uses about seven different ad-hoc widths. The quote page shows status, sent date, expiry and total in
its summary strip and again in the document card. The invoice page shows the balance in its
strip and its Payments card, and the client page shows an invoice in Work, Timeline and Balance.
Define two containers, and give each fact one home per page.
Triage: [#314 triage](../../audits/314-triage.md).

## User stories

- As an owner on a wide screen, I want pages to use the space for my work, not grey margins.
- As an owner, I want a detail page to tell me each thing once, so it's short and I trust it.

## Acceptance criteria

- [ ] Two named containers, shown on the style guide. **Wide** (lists, detail pages, Home,
      Schedule) is the full content width the app uses today. **Form** is the form column #303
      uses, with an optional summary or help aside beside it on wide screens that stacks on
      phones. No other page-level widths remain.
- [ ] Every staff form page uses the Form container: new and edit for clients, quotes,
      jobs, services, locations, roles and automations, settings forms, and help.
      Forms with an obvious summary (the quote and client a job is for, the plan for
      Plan) show it in the aside. The others are left-aligned with no blank rail.
- [ ] Detail pages state each fact once. The summary strip is the single home for status, key
      dates and the headline amount:
  - Quote page: the document card shows only what the strip doesn't (lines, totals, message,
    terms, files). "Prepared for", "Property", "Sent on", "Valid until" and "Status" aren't
    repeated, and the client's response is said once.
  - Invoice page: the balance is shown in the strip. The Payments card lists payments and their
    total, not the balance again.
  - Client page: Timeline shows events, and Balance shows money owed and paid. An invoice's
    total appears in Work only.
- [ ] Rails and cards on detail pages don't break a date over two lines ("Nov 22, / 2026") and
      don't cut text mid-word. Long values wrap at word boundaries, or the card gives them room.
- [ ] "View as client" still shows the full client document, with every field the client sees.
- [ ] A test renders the quote, invoice, job and client pages from the dev seeds and fails if
      the strip's status, sent date, expiry or balance appears twice on one page.
- [ ] Desktop (1280 and 1920) and phone (390) screenshots of each detail page and two forms.

## Out of scope

- My day's layout (see Open questions). Home already has its two-column layout (#301).
- Changing what the client sees on their quote or invoice page, the PDF or emails.
- The calendar grid's own layout.

## Open questions

- Should the Form container be centred or left-aligned? **Recommendation:** left-aligned, on
  the same left edge as list pages, so moving between pages doesn't shift the heading. The
  aside sits to the right.
- My day at desktop width: the audit asks for a two-column Wide layout. **Recommendation:**
  keep it as one column. It's the technician's phone page, and office staff reach it from
  Home's "Your day" (#301, owner-approved). Wide is for office pages.
- On the staff quote page, should the document card keep the client's view of the meta block,
  since it's "what the client sees"? **Recommendation:** no. Drop the repeats on the staff
  page, and let "View as client" show the client's exact version.
