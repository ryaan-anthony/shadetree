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

- [x] "Create another invoice" on a job or a quote before the work is done makes a progress
      invoice (kind progress) of its unbilled lines, which staff can lower. Its lines are
      progress amounts, not final bills (PAY-06). On autosave and on send, under PAY-06's lock, a
      line's progress can't pass what's left of it. *"Create progress invoice" (owner, 2026-11-23).*
- [x] Progress on a job line is credited on that line's final bill; progress on a quote line, or
      on the line of a job later cancelled, is credited on its quote line's final bills. Each
      credit = min(progress on the line not yet credited, this bill's amount for that line), the
      job line's own first. It's a negative line before tax, at the credited line's tax rates
      ("Billed earlier on INV-0003"), so tax is charged once. Clients see "Credit from INV-0003"
      with its tax (owner, 2026-11-23). *No tax rate's base goes below zero; the rest carries.*
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
      asks on the draft.* A work invoice charging too little for what must come off can't be sent.
- [x] **Shortfall:** once the quote's work is all done (nothing to do; every job completed or
      cancelled) with less than quoted, its discount is D × quoted value done ÷ quoted value,
      rounded once; the rest shows as "not used" (quote, job, invoice) and isn't outstanding.
- [x] A line's fixed discount d over quantity q is shared by quantity billed: target =
      min(d, round(d × quantity billed ÷ q)), less what earlier bills of that line took.
- [x] Shares are kept apart from a staff discount. After a void, drafts work shares and credits
      out again; sent invoices don't change. Recurring quotes don't share (JOB-10).
- [x] The $0 rule (PAY-01) looks at the total before credits; nothing due is Paid at once.
- [x] The quote page shows progress billed, credited, over-billed; the job page its own.
- [x] Tests: #356's examples 1–4, job and quote progress, over-billing, credit order, tax once,
      the line target, chosen amounts, the minimum, a re-tax, a shortfall, voids, $0, tenancy.

## Out of scope

- Refunds and credit notes for over-billing (later spec); deposits (PAY-07).

## Decisions

- Progress billing stays: a job or quote can be billed in part before it's done (owner, 2026-11-22).
- When invoicing part of a quote with a discount, staff choose how much to apply now; the rest
  carries forward and the last invoice takes it. Fixed and percent alike, in the quote's mix
  (taxed and untaxed) so tax matches the quote's. A discount taken on progress only moves cash:
  work invoices give exactly the quote's discount. Replaces the proportional share (owner,
  2026-11-23). Over-billing is credited on the next invoice (owner, 2026-11-22).
- A re-taxed job: the discount comes off the lines charged and lowers tax at their actual rates;
  the client gets all of it, and the tax total may differ from the quote's (owner, 2026-11-23).
- A staff discount on the last final leaving too little for the rest of the quote's: sending is
  refused until staff lower it, saying how much is left, as for progress (owner, 2026-11-23).
- Shortfall: the discount scales to the quoted value billed; the rest is "not used" (owner,
  2026-11-23). *Open: a scaled discount below what earlier invoices applied, or above what the
  last can take; asked of the owner.*
- A progress invoice's discounts apply to the cash it collected: the final deducts only the net
  it charged (an unpaid one still does, and stays owed). Progress never charges a line more than
  the final would after the discount still to come, or a lone job's own. Clients see
  "Credit from INV-0004" with tax; staff figures include tax (owner, 2026-11-23).
- Credited progress is voided only after the invoice crediting it (void-first). Credits count
  only from invoices that went out, capped by the bill's line after its discounts.

## Implementation notes

- `invoices.kind`, `invoice_line_items.discount_share_cents`, `invoice_credits`. `BillingLedger`
  reads a quote's (or lone job's) bills under PAY-06's lock; `BillingCredits` works shares and
  credits out on each draft save; `WorkBilling.bill_progress!`. Behind `split_jobs`.
- A credit is what the progress invoice charged for the line (its sent version), net, before
  tax, at its work's rates (quote progress: the live job's; a final can match on its draft).
- Fit: PAY-07 adds deposit/take_back credits, `nothing_due?` uses `total_due`; JOB-10 skips
  `quote_discount_off!`; QTE-09 adds Not going ahead to `nothing_left?`/`done?`/`all_done?`.
- `quote_discount_chosen_cents` (nil: $0) is held on each draft save to [min, max] (by choice,
  no more than leaves its credits whole) in `quote_discount_share_cents`; `QuoteDiscountPlan`
  places it line by line (taxed or untaxed group, needs first; credit room first) in
  `quote_discount_parts` ({from, key, rates, cents}), so tax and credits use one base.
- Dev seeds: "Roof replacement" ($500 progress sent; the final draft credits it, applies $100).
