---
id: PAY-01
title: Invoice builder
domain: payments
milestone: M4
depends_on: [QTE-01, JOB-01]
---
# PAY-01 · Invoice builder

> Requirements: [07-payments](../../plans/07-payments.md) R1–R5

## Summary

Turn finished work into an invoice in one tap. Invoices reuse the quote's line-item, discount
and tax behavior, carry payment terms and a due date, and track their status through to paid.

## User stories

- As an owner, I want to invoice a completed job in one tap with everything pre-filled.
- As an admin, I want to create a quick invoice for a walk-in job with no quote.
- As an owner, I want to see what's outstanding and what's overdue.

## Acceptance criteria

- [x] Owners/Admins create an invoice from a job (items from the job), from an approved quote,
      or from scratch for a client/property; sources are linked both ways.
      *A job or quote can be invoiced more than once (progress billing, no special screen).*
- [x] Line items, discounts and taxes behave exactly as in the quote builder (shared behavior,
      not a copy). *`PricedDocument`, `BuiltDocument` and `DocumentLine` (models), `DocumentBuilder`
      (controllers), and the quote builder's partials and script with `scope: "invoice"`.*
- [ ] Invoice fields: number (sequential per business, prefix from settings), issue date, payment
      terms (due on receipt, net 7/15/30, custom date) and computed due date, message, terms,
      internal notes, attachments (e.g. completion photos selectable from the job).
- [ ] Statuses: Draft, Sent, Partially paid, Paid, Void; Overdue is derived from due date and
      shown as an indicator. Status changes are recorded.
- [ ] Sent invoices can only be changed by revision (recorded, client sees latest) while unpaid;
      invoices with any payment cannot change line items; Void requires a reason.
- [ ] Invoice list: filter by status/overdue, search by client/number, totals outstanding and
      overdue for the filtered set.
- [x] Invoices appear on the client and job pages; the job's "Create invoice" prompt (JOB-01)
      works.
- [ ] Technicians have no access; tests cover creation paths, totals, status rules, roles and
      tenancy.

## Implementation notes

- Part 1: invoices from a job, an approved quote or scratch; the builder; the invoice's page;
  invoices on job, quote and client pages (with what's owed). Part 2: the list (filters, search,
  totals), revising and voiding sent invoices, attachments from the job's photos.
- Payment terms: due on receipt, net 7/15/30, or a custom date. New invoices take the business's
  "invoice due days" setting: one of the terms when it matches, else a custom date that many days
  out. Overdue isn't stored: a sent or partly paid invoice past its due date, for the business's today.
- An invoice from a quote bills the quote's lines as agreed; one from a job bills the job's lines
  as they are now (with changes made on site). Either way it stays with that client.

## Out of scope

- Sending and client page (PAY-02). Payments (PAY-04, PAY-05). Batch/recurring invoicing,
  deposits, progress billing (backlog).

## Open questions

- Should multiple invoices per job be allowed (progress billing)? Recommend yes technically,
  without special UI at launch.
- Credit notes vs void-and-reissue: recommend void-and-reissue only at launch.
