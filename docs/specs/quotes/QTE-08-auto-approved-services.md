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
- [ ] It applies to members who quote their assigned requests but can't send their own quotes
      (QTE-07): the built-in Technician and custom roles like it. Members who can send their own
      quotes, and the office, are unaffected.
- [ ] A draft qualifies when every line is a service with the switch on, at that service's
      current price (for the quote's location, CAT-08), with no line or quote discount. Quantity
      can be anything. It's checked again when they send, not only when the button shows.
- [ ] On a qualifying draft the technician sees "Send quote" (sending as QTE-07 allows: to the
      client's emails on file, or the copy link) and can still choose "Ready for review".
- [ ] On a draft that doesn't qualify, they see only "Ready for review", with a short reason
      naming the first line that needs the office (for example, "Gutter clean: price changed").
- [ ] A send counts toward the plan like any send (BIL-02) and follows BIL-03: at the limit the
      technician is told to ask the owner, and can still mark it ready for review.
- [ ] The quote's history records that it was sent without review, by whom, and why it qualified;
      the office sees "Sent by" on the quote as for any send.
- [ ] Turning a service's switch off, archiving it, or changing its price stops new sends of
      drafts using it; quotes already sent are unaffected.
- [ ] Tests cover qualifying and non-qualifying drafts (custom line, price edit, discount, mixed
      services, archived service), the send-time recheck, roles, the plan limit, and tenancy.

## Out of scope

- Letting technicians revise sent quotes, or send copies of approved ones (QTE-07 keeps these
  with the office).
- Per-technician or per-role lists of services (one list per business).
- Invoices from the field (backlog).

## Open questions

- **(blocking)** An edited price on an auto-approve service: allowed, or review? *Recommend:
  review. Any price other than the service's price (higher or lower) sends it to the office.*
  Wording-only edits (name, description) stay allowed.
- **(blocking)** A mix of auto-approve and other services: send the qualifying lines, split, or
  review the whole quote? *Recommend: review the whole quote; no partial sends or splitting.*
- **(blocking)** A cap on the total: should a business be able to set "up to $X" for quotes sent
  without review? *Recommend: yes, one optional amount per business beside the switches (blank
  means no cap); a quote over it goes to review with the reason "over $X".*
- Should the office be told when a technician sends without review? *Recommend: no new
  notification; it shows in the quote's history and the quote list, like any send.*
- Is this a plan feature? *Recommend: every plan; the built-in Technician is the main user, and
  custom roles are already Pro.*
- Taxes: does a changed taxable setting on a line count as a price edit? *Recommend: yes.*
