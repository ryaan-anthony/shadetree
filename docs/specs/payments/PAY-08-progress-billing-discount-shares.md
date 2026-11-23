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
client never pays twice. A fixed quote discount is shared across a quote's invoices in proportion
to the work each bills, so a part-done quote never carries the whole discount.

## User stories

- As an owner, I want to bill half the roof now and have it taken off the final invoice.
- As a client, I want $50 off $1,000 to mean $20 off the $400 invoice, not $50.

## Acceptance criteria

- [ ] "Create another invoice" on a job or a quote before the work is done makes a progress
      draft of its unbilled lines that staff can lower. Progress amounts are credits, not bills:
      a line is billed only by its final bill (PAY-06). On autosave and on send, a line's
      progress can't pass what's left of it; under PAY-06's lock.
- [ ] Progress on a job line is credited on that line's final bill. Progress on a quote line is
      credited to its job lines by claimed quantity: round(progress on the line × the claim ÷
      the line's quantity), and the final bill that leaves nothing of it unbilled takes what's
      left. A quote line billed directly takes all of it.
- [ ] A credit is an invoice-level adjustment after tax ("Billed earlier on INV-0003 −$200.00"),
      at most the invoice's total. The total due is the total after tax less credits; balance,
      status, the $0 rule (PAY-01), lists and the PDF all use it. PAY-07's deposits use the same.
- [ ] When progress passes the work done (a shortfall, a lower price), the quote shows
      "Over-billed $X" and the next invoice for the quote credits it the same way.
- [ ] A fixed quote discount D, on a quote subtotal S (after line discounts; the latest approved
      version, QTE-10): with W the quote work on final bills of invoices that aren't void,
      including this one, target = min(D, round(D × W ÷ S)) and this invoice's share = target −
      the shares on other invoices that aren't void, from zero up to its quote-work subtotal.
      Anything the cap holds back falls into the next invoice's target. Lines added on site
      aren't quote work. Progress invoices carry no share.
- [ ] After a void, drafts recompute their share and credits; sent invoices don't change, and
      the next invoice evens up. Drafts recompute at send too. Staff can still change a draft's
      discount; the change is that invoice's alone.
- [ ] A percent quote discount applies to each invoice as now. Jobs from before JOB-09 that
      carry their own fixed discount count it as their share. Recurring quotes don't share
      (JOB-10). Dropped work doesn't keep its part: the discount follows the work billed.
- [ ] The quote page shows progress billed, credited and over-billed; the job page its own.
- [ ] Tests: job and quote progress, the proportional credit and its last remainder, direct
      billing, over-billing and its credit, the cap, the target after a void, a staff discount
      change, percent discounts, legacy jobs, rounding, roles, tenancy.

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

## Implementation notes

- `invoice_credits` (invoice, kind: progress, over-billed or deposit; source invoice and line;
  amount), written under PAY-06's lock and recomputed on drafts at send; a sent invoice's credits
  are fixed. Progress rows are invoice lines with `final` false.
- Totals: `total_due = total − credits`, used by `balance`, `sendable_total?`, the PDF and lists.
