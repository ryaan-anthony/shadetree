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

- [ ] Owners/Admins create an invoice from a job (items from the job), from an approved quote,
      or from scratch for a client/property; sources are linked both ways.
- [ ] Line items, discounts and taxes behave exactly as in the quote builder (shared behavior,
      not a copy).
- [ ] Invoice fields: number (sequential per business, prefix from settings), issue date, payment
      terms (due on receipt, net 7/15/30, custom date) and computed due date, message, terms,
      internal notes, attachments (e.g. completion photos selectable from the job).
- [ ] Statuses: Draft, Sent, Partially paid, Paid, Void; Overdue is derived from due date and
      shown as an indicator. Status changes are recorded.
- [ ] Sent invoices can only be changed by revision (recorded, client sees latest) while unpaid;
      invoices with any payment cannot change line items; Void requires a reason.
- [ ] Invoice list: filter by status/overdue, search by client/number, totals outstanding and
      overdue for the filtered set.
- [ ] Invoices appear on the client and job pages; the job's "Create invoice" prompt (JOB-01)
      works.
- [ ] Technicians have no access; tests cover creation paths, totals, status rules, roles and
      tenancy.

## Out of scope

- Sending and client page (PAY-02). Payments (PAY-04, PAY-05). Batch/recurring invoicing,
  deposits, progress billing (backlog).

## Open questions

- Should multiple invoices per job be allowed (progress billing)? Recommend yes technically,
  without special UI at launch.
- Credit notes vs void-and-reissue: recommend void-and-reissue only at launch.
