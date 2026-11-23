---
id: QTE-10
title: Change orders
domain: quotes
milestone: M6
depends_on: [QTE-06, JOB-09, QTE-09, PAY-06]
---
# QTE-10 · Change orders

> Requirements: [05-quotes](../../plans/05-quotes.md) R12, R16, R23

## Summary

Work changes once it starts: the client wants two more trees, the fence needs less paint. Let
staff change an approved quote during the work (quantities, prices, discounts, new lines). Any
addition or increase goes to the client to approve first; a pure reduction applies at once, and
the client is told. Overrun work already done is offered to the client the same way. This
replaces "an approved quote can't be revised" for work in progress (QTE-06).

## User stories

- As an owner, I want the client to approve two extra trees from their phone before we cut them.
- As an owner, I want to drop the price when the job turned out smaller, and let the client know.

## Acceptance criteria

- [ ] **Change quote** on an approved quote that isn't closed opens the builder on a proposed
      change: quantities, prices, discounts, added lines. A line can't go below what's claimed,
      done or billed on it (JOB-09, PAY-06); dropping work is QTE-09's Not going ahead.
- [ ] A change with any added line, or any raised quantity or price, is a **change order**: sent
      like a quote (QTE-04), approved or declined on the same page (QTE-05: typed name, terms,
      evidence and a snapshot). Until approved the current version applies; declined or expired,
      it lapses. One change order waits at a time.
- [ ] A pure reduction (lower quantities or prices, a new or larger discount, nothing raised)
      applies at once and emails the client "Your quote was updated", with the old and new total.
- [ ] **Overrun work already done** (more done than quoted, JOB-09; capped hours, JOB-11): when
      it's logged, a change order for the extra is drafted for the office to send. Once the
      client approves, the extra is added as done work to the job that did it if that job is
      still unbilled; otherwise it's billed on its own invoice, linked to that job (PAY-06).
      Declined, nothing is billed for it.
- [ ] Applying a change takes the quote's lock, then its open jobs' by id, then the lines. Lines
      keep their identity, so claims, jobs and bills stay with them; an added line becomes to do.
      New prices reach to-do work and open jobs; completed and billed quantities keep theirs.
- [ ] Each version is kept (QTE-06): staff see what changed, by whom, and each approval. The
      client page shows the latest approved version and its changes ("Dec 4: 2 trees added,
      +$240.00, approved by Pat Lee"). The quote list shows "Change order sent" while one waits.
- [ ] PAY-08's discount base and QTE-09's Approved total use completed or billed quantity at the
      price it was kept at, and the rest at the current price.
- [ ] "Quote the rest" starts a new draft for the client with the shortfall's lines: the office,
      or a technician with QTE-07's "Quote assigned requests" for a job they're on (QTE-07's
      review rules apply).
- [ ] Office access makes, sends and applies change orders; technicians can't (tested). Another
      business's quotes are not found. Works at 360 px.
- [ ] Tests: each kind of change, a mixed change needing approval, approval, decline, expiry, the
      reduction email, limits, the overrun flow (billed and unbilled job), concurrent applies,
      versions, discount base, roles, tenancy.

## Out of scope

- Changes to recurring series (JOB-10 uses a new quote). Change orders on closed quotes.

## Decisions

- An approved quote can be changed during the work: quantities, discounts, prices, added lines;
  the client is told of every change (owner, 2026-11-22).
- Any added line, or any raised quantity or price, needs the client's approval; only pure
  reductions apply straight away. This replaces "judged by total" (owner, 2026-11-22).
- Overrun work already done: the office's change order is drafted automatically when it's
  logged; once approved, the extra is added to the job that did it, as done work, if that job is
  still unbilled. If that job has already been invoiced, the extra is billed on its own
  invoice, linked to that job (owner, 2026-11-22).
- This replaces QTE-06's "approved quotes can't be revised" for work in progress; the tech can
  instead draft a new quote for the rest (owner, 2026-11-22).
- A change order doesn't count toward plan usage (BIL-02), and is valid for the quote's usual
  period from when it's sent (owner, 2026-11-22).
- Technicians proposing change orders from the field is a later spec (owner, 2026-11-22).
- Changed prices reach to-do work and open jobs (staff see which changed); completed jobs keep
  theirs (owner, 2026-11-22).

## Implementation notes

- `Quote#revise!` edits lines in place and `index_quote_responses_one_approval` allows one
  approval per quote, so a change order is its own row: `quote_change_orders` (quote, number,
  status, proposed lines keyed by line key, expires on, response, applied at). The approval index
  is re-keyed to (quote, change order). Applying writes the lines and a QTE-06 revision snapshot.
