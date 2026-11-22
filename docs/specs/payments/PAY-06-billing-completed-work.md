---
id: PAY-06
title: Billing completed work
domain: payments
milestone: M6
depends_on: [JOB-09, PAY-01]
---
# PAY-06 · Billing completed work

> Requirements: [07-payments](../../plans/07-payments.md) R1, R17

## Summary

With a quote shared among jobs (JOB-09), an invoice bills finished work: a job's own invoice
bills that job, and the quote's bills all its completed jobs not yet billed, again as more
finish. A fixed quote discount is shared in proportion, and nothing is ever billed twice, even
when an automation and a person press at the same moment. Progress billing stays.

## User stories

- As an owner, I want to bill the gutters now and the trees when they're done, from one quote.
- As an owner, I want to be sure an automatic invoice and my own click can't bill a job twice.

## Acceptance criteria

- [ ] A completed job's **Create invoice** bills what's unbilled of its lines, at the figures of
      question 1. The quote's **Create invoice** bills every completed job's unbilled work in one
      invoice, linked to the quote and to each job it bills; it can be used again. Unfinished jobs
      and to-do work aren't billed; with nothing to bill neither is offered, and a direct request
      is refused with the reason.
- [ ] Progress billing stays: "Create another invoice" on a job or quote before the work is done
      makes a draft of the unbilled lines that staff can lower. What's billed is counted per quote
      line (and per line added on a job), drafts included, so a later invoice bills only what's
      left. A line, or a quantity of it, is billed once its full amount is on invoices that aren't
      void. Free-form lines on such an invoice credit nothing; deposits are PAY-07.
- [ ] Voiding an invoice, or deleting a draft, frees what it billed in the same transaction.
- [ ] A fixed quote discount: each invoice's share is its quote work's subtotal ÷ the quote's
      subtotal × the discount, capped at the invoice's subtotal. The invoice that leaves no quote
      work unbilled takes the remainder, so the shares add up to the discount scaled to the work
      billed (dropped work and shortfalls excluded). A percent discount just applies. Staff can
      still change a draft's discount.
- [ ] Tax rates come from the quote. Tax is rounded per invoice, so the invoices' tax can differ
      from the quote's by a few cents; this isn't adjusted, and QTE-09 explains it to the client.
- [ ] Every billing path (both buttons, progress invoices, NTF-04 "invoice the job") locks the
      quote's row, or the job's when it has no quote, and re-reads what's unbilled before writing.
      The database refuses a second bill of the same completed job line (Implementation notes).
- [ ] "Ready to invoice" (jobs list, INS-01) holds a completed job until all its lines are billed
      on invoices that went out; another job's invoice from the same quote no longer hides it. A
      job whose lines were all removed counts as billed. NTF-04 "invoice the job" skips a job with
      nothing unbilled, saying so.
- [ ] Quote page Primary (PLT-14): **Create invoice** when completed work is unbilled; else
      **Create job** when work is to do; else none (question 2). This replaces the interim
      **Reopen job** for a cancelled job (PLT-14 part 2, #353): Create job takes its work again.
- [ ] Every use of an invoice's single job is changed: invoices list each job they bill, a job's
      invoices are found through that list, and the quote page, "Ready to invoice", NTF-04 and
      the export follow it.
- [ ] Existing data: lines on invoices that aren't void are linked to the job or quote lines they
      came from where they match, and everything already billed counts as billed. "Ready to
      invoice" lists the same jobs before and after (tested). Behind JOB-09's flag.
- [ ] Data export: invoice lines get the job and quote line they bill; invoices get the quote and
      every job billed. New columns at the end.
- [ ] Technicians and quote-only members (QTE-07/08) still can't invoice; tests show it.
- [ ] Tests: repeated quote invoices, job and quote invoices crediting each other, progress then
      completion, void and delete freeing, discount shares, cap and remainder, tax drift, the race
      (automation and click), the database backstop, "Ready to invoice", migration, roles, tenancy.

## Out of scope

- Deposits and upfront billing (PAY-07); credit notes (void and reissue stays, PAY-01).

## Decisions

- An invoice bills completed work only, and can take several payments as today (owner, 2026-11-22).
- A job's Create invoice bills that job once completed; the quote's bills all completed, unbilled
  jobs in one invoice and can be used again (owner, 2026-11-22).
- Each invoice takes its proportional share of a fixed quote discount ($50 off $1,000: a $400
  invoice gets $20); a percent discount just applies (owner, 2026-11-22).
- Nothing is billed twice, enforced with locks and a database backstop (owner, 2026-11-22).
- Progress billing stays; once deposits exist, upfront billing becomes "take a deposit"
  (owner, 2026-11-22).

## Implementation notes

- `invoice_line_items.job_line_item_id` and `.quote_line_item_id` (kept through the builder's
  autosave); an `invoice_jobs` join, which `Job#invoices` goes through (`invoices.job_id` is one).
- Backstop: invoice lines carry a copy of their invoice's status, kept by a foreign key on
  (invoice, status) with on update cascade, and a partial unique index allows one completion
  bill per job line among invoices that aren't void. Voiding cascades and frees it. Progress
  amounts are checked under the lock, since a sum can't be a constraint.

## Open questions

1. **(blocking)** Which figures? Recommend the job's lines as done (done quantity, job prices,
   lines added on the job), "the total of completed jobs". Replaces PAY-01's "as agreed".
2. Unbilled work and to-do work both: which is Primary? Recommend Create invoice; Create job
   stays Secondary.
3. Does dropped work keep its part of a fixed discount? Recommend no: the discount follows the
   work billed, as the owner's proportional rule implies.
