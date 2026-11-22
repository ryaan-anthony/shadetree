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

- [x] Owners/Admins record a payment on a sent invoice: amount (default balance), date, method
      (cash, check, bank transfer, other), reference (e.g. check number) and note.
- [x] Recording updates balance and status (Partially paid / Paid); overpayment is prevented or
      requires explicit confirmation.
- [x] Optionally send the client a receipt for a recorded payment.
- [x] No method is chosen for them: the person picks one, and is told to if they don't. "Email
      a receipt" starts ticked.
- [x] Recorded payments can be edited or deleted by Owners/Admins with a reason; changes are
      kept in the invoice history. Online payments cannot be edited here.
- [x] Client page shows outstanding balance; invoice list and dashboard totals include recorded
      payments. (The dashboard comes with INS-01, from the same amounts.)
- [x] Payment history on the invoice lists all payments (online and recorded) with who/when.
- [x] Tests cover partials, overpayment handling, edits/deletes, status recalculation, roles and
      tenancy.

## Out of scope

- Client credit balances, applying one payment across several invoices (backlog).

## Decisions

- Payments can be recorded on a draft (paid on the spot): it marks the invoice sent and paid in
  one step. Not on a revision being prepared: send or discard it first.
- Overpayment is refused: a payment can't be more than the balance.
- Recording a payment has no default method: the person must choose one ("Choose how it was
  paid." if they don't), and "Email a receipt" is ticked by default (owner, 2026-11-22).

## Implementation notes

- Part 1: `Payment` (source recorded or online, method, amount, date received, reference,
  note, who recorded it). `Invoice#record_payment!`, `#change_payment!` and `#delete_payment!`
  lock the invoice and recalculate it (`#apply_payments!`): the amount paid, the status (Paid,
  Partly paid, or back to Sent) and `paid_at`, which starts the client link's last year
  (PLT-12); unpaid again, the link stops expiring. Changes and deletions need a reason, and
  the invoice's history keeps the before and after. Online payments (PAY-04) are listed but
  can't be changed here.
- Part 2: the optional receipt (`PaymentMailer#receipt`, catalog type `payment_receipt`, which
  PAY-04 reuses for online payments): a box on the record form, ticked by default since
  2026-11-22 (kept as they left it after a mistake), shown when the
  client has an email and the account may email clients. It goes to the client's email on file
  within the hourly cap, at most five receipts a day per client, and not to a refused address;
  its delivery shows on the payment. It states the balance as of its payment, and one queued
  for a payment deleted since isn't sent (marked failed).
