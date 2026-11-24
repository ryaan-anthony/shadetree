---
id: PAY-08
title: Progress billing and discount shares
domain: payments
milestone: M6
depends_on: [PAY-06]
---
# PAY-08 · Progress billing and discount shares

> Requirements: [07-payments](../../plans/07-payments.md) R17

## Summary

Some work is billed before it's done: half the roof up front, the rest at the end. Progress
billing stays, and what was billed early is credited when the work is billed for real, so the
client never pays twice and tax is charged once. Staff choose how much of a quote's discount
each invoice takes; what isn't used carries forward, and the last invoice takes the rest.

## User stories

- As an owner, I want to bill half the roof now and have it taken off the final invoice.
- As an owner, I want to choose when a quote's discount comes off, the client getting all of it.

## Acceptance criteria

- [x] "Create progress invoice" (owner, 2026-11-23) on a job or quote before the work is done
      makes a progress invoice of its unbilled lines, which staff can lower; under PAY-06's lock
      a line's progress can't pass what's left of it. Not offered once the work left is needed
      for the quote's discount: "Nothing is left to bill as progress: …".
- [x] Progress on a job line is credited on that line's final bill; on a quote line (or a
      cancelled job's), on its quote line's. Credit = min(progress not yet credited, this bill's
      amount for the line), the job line's own first: a negative line before tax at its rates, so
      tax is charged once. Clients see "Credit from INV-0003" with its tax (owner, 2026-11-23).
- [x] **Over-billed** = progress not yet credited on lines with nothing left to bill (no to-do
      quantity, and every claim billed, cancelled or Not going ahead). The quote shows
      "Over-billed $X" and the next invoice for the quote credits it the same way.
- [x] Credit order: progress, then over-billed (before tax), then deposits (after tax, PAY-07).
- [x] Any invoice billing part of a quote with a discount (a job's, the quote's, progress) asks
      how much of it to apply now: "Quote discount: $X left. Apply now: [$0]", with Apply all.
      A percent discount counts as the quote's discount in dollars. It starts at $0 and goes up
      to what's left; a minimum applies when the work left after it can't absorb the rest ("At
      least $X now: the work left after this invoice can take only $Y"), so the last invoice
      takes all of it. Plain dollars only ("40,00" and "1e3" are refused); an amount held to the
      range says so. It changes only on a draft; a void returns it. Before tax, as its own row
      ("Quote discount"), off the lines charged, at their rates. *Progress from the quote page
      asks on the draft.* A staff discount leaving too little for what must come off blocks send.
- [x] **Shortfall:** once the quote's work is all done (nothing to do; every job completed or
      cancelled) with less than quoted, its discount is D × quoted value done ÷ quoted value,
      rounded once, spread by largest remainder; the rest shows as "not used" (quote, job,
      invoice) and isn't outstanding. A direct bill's own lines count as done.
- [x] A line's fixed discount d over quantity q is shared by quantity billed: target =
      min(d, round(d × quantity billed ÷ q)), less what earlier bills of that line took.
- [x] Shares are kept apart from a staff discount. After a void, drafts work shares and credits
      out again; sent invoices don't change. Recurring quotes don't share (JOB-10).
- [x] The $0 rule (PAY-01) looks at the total before credits; nothing due is Paid at once. The
      quote page shows progress billed, credited, over-billed; the job page its own.
- [x] Tests: #356's examples 1–4, job and quote progress, over-billing, credit order, tax once,
      the line target, chosen amounts, the minimum, a re-tax, a shortfall, voids, $0, tenancy.

## Out of scope

- Refunds of what's owed to the client (later spec; staff refund by hand); deposits (PAY-07).

## Decisions

- Progress billing stays: a job or quote can be billed in part before it's done (owner, 2026-11-22).
- Staff choose how much of a quote's discount each invoice applies; the rest carries and the
  last takes it, fixed or percent, in the quote's taxed/untaxed mix. On progress it only moves
  cash: work invoices give exactly the discount (owner, 2026-11-23). Over-billing is credited on
  the next invoice (owner, 2026-11-22).
- A re-taxed job: the discount comes off the lines charged and lowers tax at their actual rates;
  the client gets all of it, and the tax total may differ from the quote's (owner, 2026-11-23).
- A staff discount on the last final leaving too little for the rest of the quote's discount
  blocks sending until staff lower it, saying what's left (owner, 2026-11-23).
- Shortfall: the discount scales to the quoted value billed; the rest is "not used" (owner,
  2026-11-23). Applied past it already: the last invoice charges the extra back, "Quote discount
  adjusted for work not done +$X", at the rates it came off. More left than the last invoice
  charges: it takes what fits, down to $0, and the rest is "Owed to the client", as is
  over-billing once nothing is left to bill; staff refund it. Neither blocks sending; with a
  staff discount too, staff lower theirs first (owner, 2026-11-24).
- A final deducts only the net a progress invoice charged (unpaid too, which stays owed);
  progress never charges a line more than the final would. Clients see "Credit from INV-0004"
  with tax; staff figures include tax (owner, 2026-11-23).
- Credited progress is voided after the invoice crediting it (the owner's void-first rule,
  2026-11-23). Credits count only from invoices that went out, capped by the bill's line.

## Implementation notes

- `invoices.kind`, `invoice_credits`; `BillingLedger` reads a quote's (or lone job's) bills under
  PAY-06's lock; `BillingCredits` works shares and credits out on each draft save, and again on
  any send or void. A credit is what progress charged for the line (its sent version), net.
- Fit: PAY-07 adds deposit/take_back credits, `nothing_due?` uses `total_due`; JOB-10 skips
  `quote_discount_off!`; QTE-09 adds Not going ahead to `nothing_left?`/`done?`/`all_done?`.
- `quote_discount_chosen_cents` (nil: $0) is held to [min, max] in `quote_discount_share_cents`;
  `QuoteDiscountPlan` places it by line (needs, then credit room first) in `quote_discount_parts`.
- Dev seeds: "Roof replacement" ($500 progress sent; the final draft credits it, applies $100).
- When `split_jobs` goes on (OPS-06): in run-your-day, turn-a-quote-into-a-job,
  invoice-finished-work and job-without-a-quote add back logging each visit's work (The work, How
  many, Add something done on site), say Create invoice bills what was done, recapture their
  screenshots; progress invoices and quote discounts get an article of their own.
