---
id: QTE-08
title: Services technicians send without review
domain: quotes
milestone: M6
depends_on: [QTE-07, CAT-03, BIL-03]
---
# QTE-08 · Services technicians send without review

> Requirements: [05-quotes](../../plans/05-quotes.md) R21; [03-catalog](../../plans/03-catalog.md) R7, R9, R10, R18

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

- [x] Each service in Services & prices has a "Technicians can send without review" switch, off by
      default, set by people who manage services; the list marks the services that have it on.
      Beside them, an optional "up to" amount for the business caps such quotes' total (blank:
      no cap). Every plan has this.
- [x] It applies to members with "Quote assigned requests" and without "Send their own quotes"
      (QTE-07), and only to a draft's first version (revision 1), as QTE-07's own sends. This
      reaches the built-in Technician once it has "Quote assigned requests" by default (owner,
      2026-11-22; a separate change). The office and members who send their own are unaffected.
- [x] A draft qualifies only when all of these hold:
      - every line is a service with the switch on, keeping that service's unit, current price
        and taxable setting, with no line discount; quantity, name and description may change;
      - no quote discount, and the total, tax included, is within the cap if there is one;
      - the quote is at its request's location, so its prices are that location's (CAT-08);
      - its tax rates and "prices include tax" are the defaults for that location or business.
      Only these are locked: terms, valid-until, attachments and the email's subject and message
      may be edited. A $0.00 total qualifies like any other, after the usual $0 confirmation.
- [x] It's checked when the button shows, and again inside the send's transaction (as the plan
      allowance is claimed, BIL-03), so a late autosave can't slip a change through.
- [x] On a qualifying draft the technician sees "Send quote" (sending as QTE-07 allows: to the
      client's emails on file, or the copy link) and can still choose "Ready for review".
- [x] On a draft that doesn't qualify, they see only "Ready for review", with a short reason
      naming the first thing that needs the office ("Gutter clean: price changed", "Over $500",
      "Tax changed"). A line whose service price changed after it was added reads "Gutter clean:
      the price list changed"; removing and adding it again picks up the new price and clears it.
- [x] A send counts toward the plan like any send (BIL-02) and follows BIL-03, with no grace
      send: once the period's quotes are used, it's blocked, the technician is told to ask the
      owner, and can still mark it ready for review. Without a confirmed email they see the
      office's notice (ACC-01) and can still mark it ready for review.
- [x] The quote's history records that it was sent without review, by whom, and why it qualified;
      the office sees "Sent by" on the quote as for any send.
- [x] Turning a service's switch off, archiving it, or changing its price stops new sends of
      drafts using it; quotes already sent are unaffected.
- [x] The switch, the cap and the reasons work at 360 px.
- [x] Tests cover qualifying and non-qualifying drafts (custom line, price edit, changed price
      list, discount, mixed services, archived service, taxable change, changed unit, changed tax
      rates or "prices include tax", another location, the cap with tax, $0.00, edited terms and
      email, a revision), no grace send, an unconfirmed email, the recheck inside
      the send, roles, the plan limit, and tenancy.

## Implementation notes

- SendWithoutReview lists every reason (the first is shown); the send re-checks it with the quote
  row locked and records why it qualified. A service without a list price never qualifies. Seeds:
  Lawn mowing, Leaf cleanup, a $500 cap; Marcus (tech@example.com) has a mowing visit to quote.

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
- No grace send, for anyone: once used reaches the limit, sends are blocked (owner,
  2026-11-22; changes BIL-03, built in #328).
- A $0.00 total qualifies like any other; the usual $0 confirmation applies (owner, 2026-11-22).
- Terms, valid-until, attachments and the email's subject and message may be edited; only
  lines, prices, units, tax and location are locked (owner, 2026-11-22).
- The cap is measured after tax (owner, 2026-11-22).
- Without a confirmed email, the office's notice, with "Ready for review" still available
  (coordinator, follows existing behaviour).
