---
id: PAY-07
title: Deposits
domain: payments
milestone: M6
depends_on: [PAY-08, PAY-05, QTE-09]
---
# PAY-07 · Deposits

> Requirements: [07-payments](../../plans/07-payments.md) R18; [05-quotes](../../plans/05-quotes.md) R22

## Summary

Many jobs need money up front: materials, a booking fee. A deposit is an invoice against an
approved quote, not tied to any work. Later invoices for that quote's work credit it until it's
used up, so the client never pays twice and always sees how much of the deposit is left.

## User stories

- As an owner, I want to take 30% before I order materials.
- As a client, I want my deposit taken off the bill when the work is done.

## Acceptance criteria

- [ ] **Take a deposit** on an approved quote makes a deposit invoice for a fixed amount or a
      percent of the quote's total, at most still expected (QTE-09) less deposits not yet
      applied; for a series, still expected is the occurrences left, or the next 12 with no end
      (JOB-10). It has one untaxed
      line ("Deposit for Q-0004"), is sent and paid like any invoice (PAY-02, PAY-04, PAY-05),
      and is marked as a deposit on staff and client pages. A quote can have several.
- [ ] Billing before any work is done becomes "Take a deposit"; progress billing (PAY-08) stays
      for work under way.
- [ ] Work invoices for the quote (PAY-06, job and quote alike, not progress invoices) apply what's
      been paid of its deposits and not yet applied, as a PAY-08 credit after tax ("Deposit
      applied −$300.00"), after the pre-tax progress and over-billed credits, up to the invoice's
      total due, oldest deposit first, until used up. A draft works it out again when sent.
- [ ] A credit applied to an invoice that's later voided is free to apply again. The $0 rule
      looks at the total before credits; a sent invoice the deposit fully covers is Paid (PAY-08).
- [ ] If a refund or a lost dispute (PAY-04) leaves less paid on a deposit than has been applied,
      sent invoices don't change: the quote shows "Deposit over-applied $X", and the next work
      invoice for the quote takes it back as a positive adjustment, "Deposit refunded +$X" (a
      take-back credit). With no work invoice left to come, **Take back** on the quote makes a
      take-back invoice for it.
- [ ] When the quote closes (QTE-09) with deposit money unused, staff see "Unused deposit $X" on
      the quote. Refunds stay in the provider's dashboard (07-payments D4).
- [ ] The client's quote page shows deposits paid, applied and left (QTE-09).
- [ ] Deposits count in the client's balance and the invoice list as any invoice does; the export
      marks deposit invoices and lists credits applied (new columns at the end).
- [ ] Owners, Admins and ACC-07 roles with office access take deposits; technicians can't
      (tested). Another business's quotes are not found.
- [ ] Works at 360 px. Tests: fixed and percent, the cap, several deposits, credit after tax,
      partly paid deposits, oldest first, a recompute at send, a void, a refund after applying,
      unused money, the race under PAY-06's lock, roles, tenancy.

## Out of scope

- Requiring a deposit for the client to approve (05-quotes backlog). Refunds from Shadetree.

## Decisions

- A deposit is money taken up front: an invoice against the quote, not tied to any work; later
  invoices credit it until it's used up. Once deposits exist, upfront billing becomes "take a
  deposit"; this spec defines how progress invoices and deposits are credited (owner, 2026-11-22).
- A deposit isn't taxed; tax is charged on the work's invoices and the deposit credited after tax
  (owner, 2026-11-22).
- Only what's been paid of a deposit is credited; an unpaid deposit stays owed on its own
  (owner, 2026-11-22).
- The cap (coordinator; follows the owner's model).
- With several, the oldest deposit is applied first. Asking for a deposit at approval is a later
  spec, with online payment required (owner, 2026-11-22).
- A refund after a deposit was applied is taken back on the next work invoice, shown as
  "Deposit refunded +$X". Deposits credit work invoices only, not progress invoices
  (owner, 2026-11-22).

## Implementation notes

- Adds `deposit` and `take_back` to PAY-08's `invoices.kind`. Applications are PAY-08's
  `invoice_credits` of kind deposit (sign −) or take-back (sign +), pointing at the deposit
  invoice, recorded under PAY-06's lock. Order on one invoice: progress, over-billed, deposit,
  take-back. They sit after tax: `total_due` drops (or rises) by them, used by balance, lists
  and the PDF; `ZeroTotalGuard` keeps looking at the total before credits.
