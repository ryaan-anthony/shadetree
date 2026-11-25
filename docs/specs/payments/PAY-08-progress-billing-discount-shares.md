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
- As an owner, I want to choose whether a quote's discount comes off now or later, knowing the
  client always gets all of it.

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
- [x] Credit order on one invoice: progress, then over-billed (both before tax), then deposits
      and take-backs (after tax, PAY-07). Total due = total − after-tax credits.
- [x] Any invoice billing part of a quote with a discount (a job's, the quote's, progress) asks
      how much of it to apply now: "Quote discount: $X left. Apply now: [$0]", with Apply all.
      A percent discount counts as the quote's discount in dollars. It starts at $0 and goes up
      to what's left; a minimum applies when the work left after it can't absorb the rest ("At
      least $X now; there's only $Y of work left"), so the last invoice takes all of it. It
      changes only on a draft; a void returns it. Before tax, as its own row ("Quote discount"),
      spread over the quote's tax mix. *The quote page's progress item asks on the draft.*
- [x] A line's fixed discount d over quantity q is shared by quantity billed: target =
      min(d, round(d × quantity billed ÷ q)), less what earlier bills of that line took.
- [x] Shares are kept apart from any discount staff type on a draft. After a void, drafts work
      out shares and credits again; sent invoices don't change. Recurring quotes don't share
      (JOB-10). *No legacy rule for pre-JOB-09 fixed discounts (owner, 2026-11-23).*
- [x] The $0 rule (PAY-01) looks at the total before credits; a sent invoice with nothing due is
      Paid at once. NTF-04 "invoice the job" sends such an invoice as any other.
- [x] The quote page shows progress billed, credited and over-billed; the job page its own.
- [x] Tests: #356's worked examples 1–4 (5 is JOB-11's), job and quote progress, a cancelled
      job's progress, over-billing and its credit, credit order, tax charged once, the line target,
      chosen amounts, the minimum, carry and the rest, a void, $0 due, roles, tenancy.

## Out of scope

- Refunds and credit notes for over-billing (later spec); deposits (PAY-07).

## Decisions

- Progress billing stays: a job or quote can be billed in part before it's done (owner, 2026-11-22).
- When invoicing part of a quote with a discount, staff choose how much to apply now; the rest
  carries forward and the last invoice takes it. Fixed and percent alike, spread over the
  quote's tax mix so total tax matches the quote's. A discount taken on progress only moves cash:
  work invoices give exactly the quote's discount. Replaces the proportional share (owner,
  2026-11-23). Over-billing is credited on the next invoice (owner, 2026-11-22).
- A progress invoice's discounts apply to the cash it collected: the final deducts only the net
  it charged (an unpaid one still does, and stays owed). Progress never charges a line more than
  the final would after the discount still to come, or a lone job's own. Clients see
  "Credit from INV-0004" with tax; staff figures include tax (owner, 2026-11-23).
- Credited progress is voided only after the invoice crediting it (owner's void-first rule).
- Credits count only from invoices that went out; a draft's are worked out again at send. A credit
  is capped by the bill's line after the applied discount; a staff percent applies before it.

## Implementation notes

- `invoices.kind` (work, progress), `.quote_discount_share_cents`, `invoice_line_items
  .discount_share_cents`; `invoice_credits` (invoice, kind, source invoice and line, amount,
  sign, tax rates, position). `BillingLedger` reads a quote's (or a lone job's) bills under
  PAY-06's lock; `BillingCredits` works shares and credits out on each draft save, and
  `WorkBilling.bill_progress!` makes progress invoices. Behind `split_jobs`.
- A credit is what the progress invoice charged for the line (the sent version while revised),
  net of its discounts, before tax; it comes off after the final's discount at its work's rates
  (quote progress: those of the live job holding the line; a final can be matched on its draft).
- Over-billed counts a final bill once it went out. Fit: PAY-07 adds deposit and take_back to
  both kind checks, keeps deposit credits in `work_out_credits`, and `nothing_due?` uses
  `total_due`; JOB-10 skips `quote_discount_off!` on recurring quotes; QTE-09 adds Not going ahead to
  `nothing_left?`/`done?` (shortfalls stand in until then) with taxed figures; QTE-10: a percent's
  amount and the tax mix follow current quote prices.
- `invoices.quote_discount_chosen_cents` (nil: $0) is held on each draft save to [minimum, max] in
  `quote_discount_share_cents`, split by tax mix in `quote_discount_parts`; the minimum is checked
  overall and per taxed part: outstanding − (work left − uncredited progress).
- `split_jobs` can go on once PAY-06 and PAY-08 merge (Operator → Flags). Dev seeds: "Roof
  replacement" ($500 progress sent; the final draft credits it and applies $100).
