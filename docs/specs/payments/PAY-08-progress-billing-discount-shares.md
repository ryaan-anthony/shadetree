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
client never pays twice and tax is charged once. Fixed discounts are shared across a quote's
invoices in proportion to the work each bills, so a part-done quote never carries all of them.

## User stories

- As an owner, I want to bill half the roof now and have it taken off the final invoice.
- As a client, I want $50 off $1,000 to mean $20 off the $400 invoice, not $50.

## Acceptance criteria

- [x] "Create another invoice" on a job or a quote before the work is done makes a progress
      invoice (kind progress) of its unbilled lines, which staff can lower. Its lines are
      progress amounts, not final bills (PAY-06). On autosave and on send, under PAY-06's lock, a
      line's progress can't pass what's left of it. *"Create progress invoice"; capped at what's
      left after the line's expected share of a fixed discount (owner, 2026-11-23).*
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
- [x] Fixed quote discount D: S = the quote's value after line discounts, with completed or
      billed quantity at the price it was kept at and the rest at the current price (QTE-10); W
      = quote work (lines added on site aren't) on final bills not void, this one included. target =
      min(D, round(D × W ÷ S)); this invoice's share = target − shares on other such invoices,
      from zero up to its quote-work subtotal; what the cap holds back falls into the next target.
- [x] A line's fixed discount d over quantity q is shared the same way: target = min(d, round(d ×
      quantity billed ÷ q)), less what earlier bills of that line took.
- [x] Shares are kept apart from any discount staff type on a draft, so an edit never skews later
      targets. After a void, drafts recompute shares and credits; sent invoices don't change.
- [x] A percent discount applies to each invoice as now. Jobs from before JOB-09 that carry a
      fixed discount count it as their share. Recurring quotes don't share (JOB-10). Dropped work
      doesn't keep its part: the discount follows the work billed. *No legacy rule (owner,
      2026-11-23): an invoice from quote work copies only a percent discount.*
- [x] The $0 rule (PAY-01) looks at the total before credits; a sent invoice with nothing due is
      Paid at once. NTF-04 "invoice the job" sends such an invoice as any other.
- [x] The quote page shows progress billed, credited and over-billed; the job page its own.
- [x] Tests: #356's worked examples 1–4 (5 is JOB-11's), job and quote progress, a cancelled
      job's progress, over-billing and its credit, credit order, tax charged once, both targets,
      the cap and carry, a void, a staff discount edit, percent discounts, $0 due, roles, tenancy.

## Out of scope

- Refunds and credit notes for over-billing (later spec); deposits (PAY-07).

## Decisions

- Progress billing stays: a job or quote can be billed in part before it's done (owner, 2026-11-22).
- Each invoice takes its proportional share of a fixed quote discount ($50 off a $1,000 quote: a
  $400 invoice gets $20); a percent discount just applies (owner, 2026-11-22).
- Dropped work keeps no part of a fixed discount; over-billing shows on the quote and is
  credited on the next invoice (owner, 2026-11-22).
- The target, the cap and carry, "lines added on site aren't quote work" and "progress invoices
  get no share" (coordinator; follows the owner's model).
- A progress invoice's discounts apply to the cash it collected: the final deducts only the net
  it charged (an unpaid one still does, and stays owed). Progress is capped at, and defaults to,
  what's left after the line's expected share of a fixed discount. Clients see "Credit from
  INV-0004" with tax; staff figures include tax; "Create progress invoice" (owner, 2026-11-23).
- No legacy rule for pre-JOB-09 fixed discounts (owner, 2026-11-23). Credited progress is voided
  only after the invoice crediting it (follows the owner's void-first rule, 2026-11-23).
- Credits and shares count only from invoices that went out; a draft's are worked out again at
  send; a sent invoice's stay (a revision can't go below them). A credit is capped by the bill's
  line after its share; a staff percent applies to the subtotal before the share (implementation).

## Implementation notes

- `invoices.kind` (work, progress), `.quote_discount_share_cents`, `invoice_line_items
  .discount_share_cents`; `invoice_credits` (invoice, kind, source invoice and line, amount,
  sign, tax rates, position). `BillingLedger` reads a quote's (or a lone job's) bills under
  PAY-06's lock; `BillingCredits` works shares and credits out on each draft save, and
  `WorkBilling.bill_progress!` makes progress invoices. Behind `split_jobs`.
- A credit is what the progress invoice charged for the line, net of its discounts, before tax;
  it comes off after the final's discount, at the same rates (a final taxed otherwise is refused).
- Over-billed counts a final bill once it went out. Fit: PAY-07 adds deposit and take_back to
  both kind checks, keeps deposit credits in `work_out_credits`, and `nothing_due?` uses
  `total_due`; JOB-10 skips `percent_only!` on recurring quotes; QTE-09 adds Not going ahead to
  `nothing_left?`/`done?` (shortfalls stand in until then) with taxed figures; QTE-10's base
  reads current quote lines.
- `split_jobs` can go on once PAY-06 and PAY-08 merge (Operator → Flags). Dev seeds: "Roof
  replacement" ($500 progress sent; the final draft credits it, $80 share).
