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
moment. Progress billing, credits and discount shares are PAY-08.

## User stories

- As an owner, I want to bill the gutters now and the trees when they're done, from one quote.
- As an owner, I want to be sure an automatic invoice and my own click can't bill a job twice.

## Acceptance criteria

- [x] A completed job's **Create invoice** bills its unbilled lines as done on the job: the done
      quantity (the technicians' logged work as confirmed, JOB-09; hourly lines from tracked
      time, JOB-11), the job's prices, and lines added on site. The quote's **Create invoice**
      bills every completed job's unbilled lines in one invoice, linked to the quote and each job,
      and can be used again. Unfinished jobs and to-do work aren't billed; with nothing to bill
      neither is offered, and a direct request is refused with the reason.
      *Hourly lines bill the hours logged until JOB-11 ships.*
- [x] A quote with no jobs (automatic jobs off, or every job cancelled) is billed as today: its
      Create invoice bills the quote's lines directly, as done and billed with no job, so no job
      can take them; voiding the invoice makes them to do again. Not for recurring quotes.
- [x] A line is billed once a final bill for it is on an invoice that isn't void. Voiding, or
      deleting a draft, frees it, and its claim (JOB-09), in the same transaction.
- [x] A quote invoice can combine jobs with different tax rates: each line keeps its job's rates.
      Tax is rounded per invoice, and split lines and discount shares can each leave a rounding
      cent, so invoices can differ from the quote by a few cents; this isn't adjusted (QTE-09
      explains it).
- [x] Every billing path (both buttons, direct billing, PAY-08's progress invoices, NTF-04
      "invoice the job") locks the quote, then its jobs by id, then the lines by id (the job
      alone without a quote), and re-reads what's unbilled. The database refuses a second final
      bill for a line (Implementation notes).
- [x] "Ready to invoice" (jobs list, INS-01) holds a completed job until all its lines have final
      bills on invoices that went out; another job's invoice from the same quote no longer hides
      it. A job whose lines were all removed counts as billed. NTF-04 "invoice the job" skips a
      job with nothing unbilled, saying so. Jobs without a quote work as today.
- [x] Quote page Primary (PLT-14): **Create invoice** when completed work is unbilled; else
      **Create job** when work is to do; else none. This replaces the interim **Reopen job**
      for a cancelled job (PLT-14 part 2, #353, still open); the job page's Reopen stays.
- [x] Every use of an invoice's single job is changed (list in #356): its source and links, the
      job's photos for attachments, changing the client, the job's invoices, "Ready to invoice",
      NTF-04 and the export. Recurring occurrences are billed per job (JOB-10).
- [x] Existing data: lines on invoices that aren't void are linked to the job or quote lines they
      came from. A quote invoice on a quote with a job links to that job's lines. Where a line
      matches more than one such invoice, the earliest is its final bill and later ones become
      progress (final false). Nothing is credited after the fact, and over-billing isn't worked
      out for these quotes. "Ready to invoice" lists the same jobs before and after (tested).
- [x] Export (new columns at the end): invoice lines get the job and quote line they bill and
      whether final; invoices the quote and every job. All of it behind JOB-09's flag.
- [x] Technicians and quote-only members (QTE-07/08) still can't invoice; tests show it.
- [x] Tests: repeated quote invoices, job and quote invoices together, direct billing and its
      void, mixed tax rates, void and delete freeing, the race (automation and click), the
      backstop, "Ready to invoice", legacy duplicates, roles, tenancy.

## Out of scope

- Progress billing, credits, discount shares and over-billing (PAY-08); deposits (PAY-07).

## Decisions

- An invoice bills completed work only and can take several payments as today (owner, 2026-11-22).
- A job's invoice uses its lines as done on the job, including quantity changes and lines added
  on site. A job's Create invoice bills that job once completed; the quote's bills all completed,
  unbilled jobs in one invoice and can be used again (owner, 2026-11-22).
- With automatic jobs off, the quote's Create invoice still bills the quote's lines directly
  (owner, 2026-11-22).
- Nothing is billed twice: locks plus a database backstop (owner, 2026-11-22).
- With both unbilled and to-do work, Create invoice is the Primary; Create job is Secondary
  (owner, 2026-11-22). Billing directly isn't completed work: its Create invoice is Secondary.
- Tax rounds per invoice and the difference isn't adjusted (coordinator; follows the owner's model).

## Implementation notes

- `WorkBilling` builds every invoice from work. Behind `split_jobs`; off, billing is as before
  (any status, again, the quote's lines as agreed), each line linked, repeats `final` false.
- `invoice_line_items.job_line_item_id`, `.quote_line_item_id`, `.final` and `.tax_rates` (the
  job's, when an invoice's jobs differ); `invoice_jobs`, which `Job#invoices` goes through
  (`invoices.job_id` holds the first). Revision snapshots keep each line's key and links.
- Backstop DDL: unique `invoices (id, status)`; `invoice_line_items.invoice_status` NOT NULL
  DEFAULT 'draft', `attr_readonly`, backfilled; FK `(invoice_id, invoice_status)` → `invoices
  (id, status)` ON UPDATE/DELETE CASCADE (lines go on drafts only); unique `(job_line_item_id)`
  and `(quote_line_item_id) WHERE job_line_item_id IS NULL`, both `WHERE final AND
  invoice_status <> 'void'`. `void!`, `discard_revision!` and a draft's save take the quote lock.
- Direct billing: a claim with no job, made by the line, following its quantity on a draft, freed
  on delete or void. `Quote#recurring?` is false until JOB-10.
- Migration: matched by item, name and price, then item and name. Dev seeds: "Front hedges and
  fence" (two completed jobs; the hedges billed, the fence ready to invoice).
