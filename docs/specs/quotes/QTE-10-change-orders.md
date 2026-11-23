---
id: QTE-10
title: Change orders
domain: quotes
milestone: M6
depends_on: [QTE-06, JOB-09]
---
# QTE-10 · Change orders

> Requirements: [05-quotes](../../plans/05-quotes.md) R12, R16, R23

## Summary

Work changes once it starts: the client wants two more trees, the fence needs less paint. Let
staff change an approved quote during the work (quantities, prices, discounts, new lines). A
change that raises the total goes to the client to approve again before it applies; a reduction
or a new discount applies at once, and the client is told. This replaces "an approved quote
can't be revised" for work in progress (QTE-06).

## User stories

- As an owner, I want the client to approve two extra trees from their phone before we cut them.
- As an owner, I want to drop the price when the job turned out smaller, and let the client know.

## Acceptance criteria

- [ ] **Change quote** on an approved quote that isn't closed opens the builder on a new version:
      change quantities, prices and discounts, and add lines. A line can't go below what's
      claimed, done or billed on it (JOB-09, PAY-06); dropping work is QTE-09's Not going ahead.
- [ ] A change that raises the approved total is a **change order**: sent to the client like a
      quote (QTE-04), approved or declined on the same page (QTE-05: typed name, terms, evidence
      and a snapshot of exactly what was approved). Until approved the previous version applies;
      declined, it lapses and the previous one stays.
- [ ] A change that doesn't raise the total (a reduction, a new discount) applies at once and
      emails the client "Your quote was updated", showing the old and new total.
- [ ] Each version is kept (QTE-06): staff see what changed, by whom, and each approval. The
      client page shows the latest approved version and a short list of changes ("Dec 4: 2 trees
      added, +$240.00, approved by Pat Lee").
- [ ] Lines keep their identity across versions, so claims, jobs and bills stay with them; an
      added line becomes to do (JOB-09). Changed prices reach jobs as question 4 settles.
- [ ] PAY-08's discount share uses the latest approved version's subtotal and discount.
- [ ] The quote list shows "Change order sent" while one waits for the client.
- [ ] As an alternative, staff or a technician (QTE-07) can draft a new quote for the rest:
      "Quote the rest" starts a draft for the client with the shortfall's lines.
- [ ] Office access makes and sends change orders; technicians can't (tested). Another
      business's quotes are not found. Works at 360 px.
- [ ] Tests: raise, reduce, mixed changes judged by total, approval, decline, the email on a
      reduction, limits below claimed or billed, versions, discount shares, roles, tenancy.

## Out of scope

- Changes to recurring series (JOB-10 uses a new quote). Change orders on closed quotes.

## Decisions

- An approved quote can be changed during the work: quantities, discounts, prices, added lines.
  A change that raises the total needs the client's approval again before it applies;
  reductions and new discounts apply straight away, and the client is told (owner, 2026-11-22).
- This replaces QTE-06's "approved quotes can't be revised" for work in progress.
  Alternatively, the tech can draft a new quote for the rest (owner, 2026-11-22).

## Open questions

1. Does a change order count toward plan usage (BIL-02)? Recommend no: it's the same quote.
2. Can a technician propose a change order from the field, for the office to send (as QTE-07's
   Ready for review)? Recommend a later spec; "Quote the rest" covers the field for now.
3. Does a change order expire? Recommend the quote's usual validity from when it's sent.
4. Do changed prices reach jobs already made? Recommend to-do work and open jobs take the new
   price (staff see which jobs changed); completed jobs keep theirs.
