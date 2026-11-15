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
      *Everything but the PDF download is in place; the link arrives with QTE-02.*
- [ ] The page has a prominent primary action area reserved for approval (QTE-05) and shows the
      quote's state (awaiting response, approved, declined, expired, superseded).
      *All but superseded, which needs revisions (QTE-06).*
- [ ] The page always shows the latest sent revision; older links resolve to the latest.
      *Revisions arrive with QTE-06.*
- [x] Expired quotes are viewable with a clear notice and a "request an updated quote" action
      that notifies the business. *The request is recorded on the link's history and flagged
      in the quotes list; an email to the business follows once NTF-01 lands.*
- [x] First client view and subsequent views are recorded (PLT-12); staff "preview as client"
      opens the same page in preview mode without recording a view.
- [x] Draft quotes are never reachable by clients.
- [ ] Loads in under 1 s on a mid-range phone on 4G; ≥ 90 mobile Lighthouse; WCAG 2.1 AA.
      *Lighthouse mobile in development: accessibility 100, best practices 100, performance 88
      (uncompressed dev assets). Re-check on staging once PLT-09 is up.*
- [x] Tests cover states, preview mode, expiry and link isolation.

## Decisions

- A quote's client link expires 30 days after the quote does (end of its last day in the
  business's time zone), and never sooner than the default 90 days (PLT-12).
- Photos and files on the page are served through the link and redirect to five-minute storage
  URLs, so revoking the link cuts them off too.
- An update request is recorded once per quote; the business answers it with a revision
  (QTE-06).

## Out of scope

- Approve/decline actions (QTE-05). Sending (QTE-04).

## Open questions

- ~~Should the client see the business's other contact options (call/text buttons)?~~
  Resolved: yes. The action area always shows the business's call and email buttons.
