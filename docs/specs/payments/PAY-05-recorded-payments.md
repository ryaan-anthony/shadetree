---
id: PAY-05
title: Recorded payments & balances
domain: payments
milestone: M4
depends_on: [PAY-01]
---
# PAY-05 · Recorded payments & balances

> Requirements: [07-payments](../../plans/07-payments.md) R13, R14, R15

## Summary

Plenty of clients still pay by cash, check or bank transfer. Let staff record those payments
against invoices — including partial payments — so balances, statuses and totals are always
accurate regardless of how the money arrived.

## User stories

- As an owner, I want to record a check I received so that the invoice shows paid.
- As an admin, I want to record a partial payment and see the remaining balance.
- As an owner, I want to fix a payment I recorded by mistake.

## Acceptance criteria

- [ ] Owners/Admins record a payment on a sent invoice: amount (default balance), date, method
      (cash, check, bank transfer, other), reference (e.g. check number) and note.
- [ ] Recording updates balance and status (Partially paid / Paid); overpayment is prevented or
      requires explicit confirmation.
- [ ] Optionally send the client a receipt for a recorded payment.
- [ ] Recorded payments can be edited or deleted by Owners/Admins with a reason; changes are
      kept in the invoice history. Online payments cannot be edited here.
- [ ] Client page shows outstanding balance; invoice list and dashboard totals include recorded
      payments.
- [ ] Payment history on the invoice lists all payments (online and recorded) with who/when.
- [ ] Tests cover partials, overpayment handling, edits/deletes, status recalculation, roles and
      tenancy.

## Out of scope

- Client credit balances, applying one payment across several invoices (backlog).

## Open questions

- Allow recording payments on draft invoices (paid on the spot before sending)? Recommend yes —
  common for small jobs; it marks the invoice sent/paid in one step.
