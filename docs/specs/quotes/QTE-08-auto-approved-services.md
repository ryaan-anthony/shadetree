---
id: QTE-08
title: Services technicians send without review
domain: quotes
milestone: M6
depends_on: [QTE-07, CAT-03, BIL-03]
---
# QTE-08 · Services technicians send without review

> Requirements: [05-quotes](../../plans/05-quotes.md) R21; [03-catalog](../../plans/03-catalog.md)

## Summary

Some work is routine enough that the office doesn't need to check the quote: a standard gutter
clean at the list price. A business can mark services in Services & prices as ones technicians
may send without review. A technician's draft made only of those services, at their prices, can
be sent by the technician straight away; anything else still goes to "Ready for review" (QTE-07).

## User stories

- As an owner, I want my techs to send a quote for a standard service on the spot, so the client
  can approve it before the tech leaves the driveway.
- As an owner, I want anything unusual (a custom line, a changed price, a discount) to still come
  past the office.

## Acceptance criteria

- [ ] Each service in Services & prices has a "Technicians can send without review" switch, off by
      default, set by people who manage services; the list marks the services that have it on.
      Beside them, an optional "up to" amount for the business caps such quotes' total (blank:
      no cap). Every plan has this.
- [ ] It applies to members who quote their assigned requests but can't send their own quotes
      (QTE-07): the built-in Technician and custom roles like it. Members who can send their own
      quotes, and the office, are unaffected.
- [ ] A draft qualifies when every line is a service with the switch on, at that service's
      current price (for the quote's location, CAT-08) and taxable setting, with no line or quote
      discount, and the total within the business's cap if it has one. Quantity, name and
      description can be edited. It's checked again on send, not only when the button shows.
- [ ] On a qualifying draft the technician sees "Send quote" (sending as QTE-07 allows: to the
      client's emails on file, or the copy link) and can still choose "Ready for review".
- [ ] On a draft that doesn't qualify, they see only "Ready for review", with a short reason
      naming the first line that needs the office (for example, "Gutter clean: price changed",
      or "Over $500").
- [ ] A send counts toward the plan like any send (BIL-02) and follows BIL-03: at the limit the
      technician is told to ask the owner, and can still mark it ready for review.
- [ ] The quote's history records that it was sent without review, by whom, and why it qualified;
      the office sees "Sent by" on the quote as for any send.
- [ ] Turning a service's switch off, archiving it, or changing its price stops new sends of
      drafts using it; quotes already sent are unaffected.
- [ ] Tests cover qualifying and non-qualifying drafts (custom line, price edit, discount, mixed
      services, archived service, taxable change, the cap), the send-time recheck, roles, the
      plan limit, and tenancy.

## Out of scope

- Letting technicians revise sent quotes, or send copies of approved ones (QTE-07 keeps these
  with the office).
- Per-technician or per-role lists of services (one list per business).
- Invoices from the field (backlog).

## Decisions

- An auto-approve service at any price other than its own (higher or lower) goes to review;
  name and description edits are allowed (owner, 2026-11-22).
- A draft mixing auto-approve services with anything else goes to review as a whole: no
  partial sends or splitting (owner, 2026-11-22).
- One optional cap per business on the total of quotes sent without review; a quote over it
  goes to review with the reason "over $X" (owner, 2026-11-22).
- No new notification for the office; the send shows in the quote's history and the quote
  list (owner, 2026-11-22).
- Every plan, not a plan feature (owner, 2026-11-22).
- Changing a line's taxable setting counts as a price edit (owner, 2026-11-22).
