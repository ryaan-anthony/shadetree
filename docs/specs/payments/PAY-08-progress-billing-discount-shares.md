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
      line's progress can't pass what's left of it. *Labelled "Create progress invoice".*
- [x] Progress on a job line is credited on that line's final bill; progress on a quote line, or
      on the line of a job later cancelled, is credited on its quote line's final bills. Each
      credit = min(progress on the line not yet credited, this bill's amount for that line), the
      job line's own first. It's a negative line before tax, at the credited line's tax rates
      ("Billed earlier on INV-0003"), so tax is charged once.
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
- [x] Tests: the five worked examples in #356, job and quote progress, a cancelled job's progress,
      over-billing and its credit, credit order, tax charged once, both targets, the cap and
      carry, a void, a staff discount edit, percent and legacy discounts, $0 due, roles, tenancy.

## Out of scope

- Refunds and credit notes for over-billing (later spec); deposits (PAY-07).

## Decisions

- Progress billing stays: a job or quote can be billed in part before it's done (owner, 2026-11-22).
- Each invoice takes its proportional share of a fixed quote discount ($50 off a $1,000 quote: a
  $400 invoice gets $20); a percent discount just applies (owner, 2026-11-22).
- Dropped work doesn't keep its part of a fixed discount: it follows the work billed
  (owner, 2026-11-22).
- When progress billing passes the work done, the quote shows "Over-billed $X" and it's credited
  on the next invoice. Refunds and credit notes are a later spec (owner, 2026-11-22).
- The target, the cap and carry, "lines added on site aren't quote work" and "progress invoices
  get no share" (coordinator; follows the owner's model).

- No backwards compatibility: pre-JOB-09 jobs' fixed discounts get no special rule (owner,
  2026-11-23). Progress credited on a sent invoice can't be voided until that one is (follows
  the owner's 2026-11-23 rule that invoiced work changes only by voiding).
- Credits and shares count only from invoices that went out; a draft's are worked out again at
  send. A credit is capped by the bill's line after its share (coordinator; follows the model).

## Implementation notes

- `invoices.kind` (work, progress), `.quote_discount_share_cents`, `invoice_line_items
  .discount_share_cents`; `invoice_credits` (invoice, kind, source invoice and line, amount,
  sign, tax rates, position). `BillingLedger` reads a quote's (or a lone job's) bills under
  PAY-06's lock; `BillingCredits` works shares and credits out on each draft save, and
  `WorkBilling.bill_progress!` makes progress invoices. Behind `split_jobs`.
- Amounts are line subtotals: a credit is a negative line, so the invoice's discount and tax
  apply as they did to the progress; a document discount isn't spread onto credit lines.
- Over-billed counts a line's final bill once it went out. Until QTE-09, a shortfall stands in
  for Not going ahead in tests. A revision keeps its shares and credits for a discard.
- PAY-07: add deposit and take_back to both kind checks and an after-tax `total_due`.
- Flag: with PAY-06 and PAY-08 merged, `split_jobs` can be turned on (Operator → Flags).
- Dev seeds: "Roof replacement" ($500 progress sent; the final draft credits it, $80 share).
