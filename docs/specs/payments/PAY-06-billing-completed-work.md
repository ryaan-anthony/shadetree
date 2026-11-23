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
finish. Nothing is ever billed twice, even when an automation and a person press at the same
moment. Progress billing and the quote discount's share are PAY-08.

## User stories

- As an owner, I want to bill the gutters now and the trees when they're done, from one quote.
- As an owner, I want to be sure an automatic invoice and my own click can't bill a job twice.

## Acceptance criteria

- [ ] A completed job's **Create invoice** bills its unbilled lines as done on the job: the done
      quantity, the job's prices, and lines added on site. The quote's **Create invoice** bills
      every completed job's unbilled lines in one invoice, linked to the quote and each job; it
      can be used again. Unfinished jobs and to-do work aren't billed. With nothing to bill
      neither is offered, and a direct request is refused with the reason.
- [ ] A quote with no jobs (automatic jobs off, or every job cancelled) is billed as today: its
      Create invoice bills the quote's lines directly. Those lines count as done and billed with
      no job, so no job can take them; voiding the invoice makes them to do again.
- [ ] A job line, or a quote line billed directly, is billed once a final bill for it is on an
      invoice that isn't void. Voiding, or deleting a draft, frees it in the same transaction.
- [ ] One quote invoice can combine jobs with different tax rates: each line keeps its job's
      rates. Tax is rounded per invoice, and split lines can each carry a rounding cent, so the
      invoices can differ from the quote by a few cents. This isn't adjusted; QTE-09 explains it.
- [ ] Every billing path (both buttons, direct billing, PAY-08's progress invoices, NTF-04
      "invoice the job") locks the quote, then the job, then its lines (JOB-09's order), or the
      job alone without a quote, and re-reads what's unbilled. The database refuses a second
      final bill for a line (Implementation notes).
- [ ] "Ready to invoice" (jobs list, INS-01) holds a completed job until all its lines have final
      bills on invoices that went out; another job's invoice from the same quote no longer hides
      it. A job whose lines were all removed counts as billed. NTF-04 "invoice the job" skips a
      job with nothing unbilled, saying so. Jobs without a quote work as today.
- [ ] Quote page Primary (PLT-14): **Create invoice** when completed work is unbilled; else
      **Create job** when work is to do; else none. This replaces the interim **Reopen job**
      for a cancelled job (PLT-14 part 2, #353); the job page's Reopen stays.
- [ ] Every use of an invoice's single job is changed (list in #356): its source and links, the
      job's photos for attachments, changing the client, the job's invoices, "Ready to invoice",
      NTF-04 and the export. Recurring occurrences are billed per job (JOB-10).
- [ ] Existing data: lines on invoices that aren't void are linked to the job or quote lines they
      came from where they match, as final bills; anything unmatched on such an invoice marks its
      job's or quote's lines billed. "Ready to invoice" lists the same jobs before and after
      (tested). Export: invoice lines get the job and quote line they bill and whether final;
      invoices the quote and every job. New columns at the end; behind JOB-09's flag.
- [ ] Technicians and quote-only members (QTE-07/08) still can't invoice; tests show it.
- [ ] Tests: repeated quote invoices, job and quote invoices together, direct billing and its
      void, mixed tax rates, void and delete freeing, the race (automation and click), the
      backstop, "Ready to invoice", the migration, roles, tenancy.

## Out of scope

- Progress billing, discount shares and over-billing (PAY-08); deposits (PAY-07).

## Decisions

- An invoice bills completed work only and can take several payments as today (owner, 2026-11-22).
- A job's invoice uses its lines as done on the job, including quantity changes and lines added
  on site. A job's Create invoice bills that job once completed; the quote's bills all completed,
  unbilled jobs in one invoice and can be used again (owner, 2026-11-22).
- With automatic jobs off, the quote's Create invoice still bills the quote's lines directly
  (owner, 2026-11-22).
- Nothing is billed twice: locks plus a database backstop (owner, 2026-11-22).
- With both unbilled and to-do work, Create invoice is the Primary; Create job is Secondary
  (owner, 2026-11-22).

## Implementation notes

- `invoice_line_items.job_line_item_id`, `.quote_line_item_id` and `.final` (a final bill rather
  than a progress amount), kept through the builder's autosave. An `invoice_jobs` join, which
  `Job#invoices` goes through (`invoices.job_id` holds one). Lines keep their own tax rates when
  an invoice's jobs differ.
- Backstop DDL: a unique index on `invoices (id, status)`; `invoice_line_items.invoice_status`,
  NOT NULL and never written by the app; a foreign key `(invoice_id, invoice_status)` →
  `invoices (id, status)` ON UPDATE CASCADE ON DELETE CASCADE; and unique indexes on
  `(job_line_item_id)` and on `(quote_line_item_id) WHERE job_line_item_id IS NULL`, both
  `WHERE final AND invoice_status <> 'void'`. Voiding cascades the status and frees the line.
- Direct billing records a claim with no job (JOB-09's claims), so the claim check holds.
