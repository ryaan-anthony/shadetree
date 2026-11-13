---
id: QTE-03
title: Client quote page
domain: quotes
milestone: M2
depends_on: [QTE-01, PLT-12, CAT-02]
---
# QTE-03 · Client quote page

> Requirements: [05-quotes](../../plans/05-quotes.md) R10, R14; vision principle 2

## Summary

"Ridiculously fast public quote view" is a stated differentiator. When a client opens their
link, they see a clean, branded, mobile-first page with everything they need to say yes — no
account, no clutter, instant load.

## User stories

- As a homeowner, I want to open the quote from my email on my phone and immediately understand
  what I'm paying for.
- As a client, I want to download the PDF and see the business's contact details.
- As an owner, I want to see exactly what my client sees before I send.

## Acceptance criteria

- [ ] Opening a valid quote client link shows: business identity (logo, name, contact), quote
      title and number, message, property, line items with descriptions, discounts, taxes,
      total, terms, attachments (images viewable inline), expiry date, and PDF download.
- [ ] The page has a prominent primary action area reserved for approval (QTE-05) and shows the
      quote's state (awaiting response, approved, declined, expired, superseded).
- [ ] The page always shows the latest sent revision; older links resolve to the latest.
- [ ] Expired quotes are viewable with a clear notice and a "request an updated quote" action
      that notifies the business.
- [ ] First client view and subsequent views are recorded (PLT-12); staff "preview as client"
      opens the same page in preview mode without recording a view.
- [ ] Draft quotes are never reachable by clients.
- [ ] Loads in under 1 s on a mid-range phone on 4G; ≥ 90 mobile Lighthouse; WCAG 2.1 AA.
- [ ] Tests cover states, preview mode, expiry and link isolation.

## Out of scope

- Approve/decline actions (QTE-05). Sending (QTE-04).

## Open questions

- Should the client see the business's other contact options (call/text buttons)? Recommend
  yes — reduces friction for questions.
