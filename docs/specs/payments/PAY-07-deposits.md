---
id: PAY-07
title: Deposits
domain: payments
milestone: M6
depends_on: [PAY-06, PAY-05]
---
# PAY-07 · Deposits

> Requirements: [07-payments](../../plans/07-payments.md) R18; [05-quotes](../../plans/05-quotes.md) R13

## Summary

Many jobs need money up front: materials, a booking fee. A deposit is an invoice against an
approved quote, not tied to any work. Later invoices for that quote's work credit it until it's
used up, so the client never pays twice and always sees how much of the deposit is left.

## User stories

- As an owner, I want to take 30% before I order materials.
- As a client, I want my deposit taken off the bill when the work is done.

## Acceptance criteria

- [ ] **Take a deposit** on an approved quote makes a deposit invoice for a fixed amount or a
      percent of the quote's total, at most what's still expected. It has one line ("Deposit
      for Q-0004"), is sent and paid like any invoice (PAY-02, PAY-04, PAY-05), and is marked
      as a deposit on staff and client pages.
- [ ] A quote can have more than one deposit; together they can't exceed its expected total.
- [ ] Invoices for the quote's work (PAY-06, job and quote alike) apply what's been paid of its
      deposits as a credit line, "Deposit applied", after tax, up to the invoice's total, until
      the deposits are used up. The credit shows on the invoice, its PDF and the client page.
- [ ] A deposit applied to an invoice that's then voided is free to apply again. A deposit that
      has been applied can't be voided until those invoices are.
- [ ] Billing before any work is done becomes "Take a deposit": progress billing (PAY-06) stays
      for work under way, and its amounts are credited per line, not from deposits.
- [ ] When the quote closes (QTE-09) with deposit money unused, staff see "Unused deposit $X" on
      the quote. Refunds stay in the provider's dashboard (07-payments D4).
- [ ] The client's quote page (QTE-09) shows deposits paid, applied and left.
- [ ] Deposits count in the client's balance and the invoice list as any invoice does; the data
      export marks deposit invoices and lists credits applied (new columns at the end).
- [ ] Owners, Admins and ACC-07 roles with office access take deposits; technicians can't
      (tested). Another business's quotes are not found.
- [ ] Works at 360 px. Tests: fixed and percent, the cap, several deposits, credit after tax,
      partly paid deposits, void rules, unused money, the race with PAY-06's locks, roles, tenancy.

## Out of scope

- Requiring a deposit for the client to approve (05-quotes backlog; question 2).
- Refunds from Shadetree (07-payments backlog).

## Decisions

- A deposit is money taken up front: an invoice against the quote, not tied to any work; later
  invoices credit it until it's used up (owner, 2026-11-22).
- Once deposits exist, upfront billing becomes "take a deposit"; this spec defines how progress
  invoices and deposits are credited (owner, 2026-11-22).

## Open questions

1. Is a deposit taxed? Recommend no: tax is charged on the work's invoices, and the deposit is
   credited after tax.
2. Ask for the deposit at approval, so the client pays to approve? Recommend a later spec, with
   online payment (PAY-04) required for it.
3. Credit only what's been paid, or what's been invoiced? Recommend paid: an unpaid deposit
   credits nothing and stays owed on its own.
4. Several open invoices: which gets the credit? Recommend the oldest first, as each is created.
