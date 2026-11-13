---
id: PAY-04
title: Client pays online
domain: payments
milestone: M4
depends_on: [PAY-02, PAY-03]
---
# PAY-04 · Client pays online

> Requirements: [07-payments](../../plans/07-payments.md) R10, R11, R12, R16

## Summary

"Get paid faster" is the hook. From the invoice page, a client pays by card (or wallet) in a few
taps. The invoice updates, the client gets a receipt, and the business is told — reliably, even
if the client closes the browser mid-payment.

## User stories

- As a client, I want to pay my invoice from my phone with Apple Pay or a card in seconds.
- As an owner, I want the invoice to show Paid automatically so that I don't chase clients who
  already paid.

## Acceptance criteria

- [ ] When the business has an active payment account, the client invoice page shows a Pay
      button for the balance due; card entry happens in provider-hosted fields or pages.
- [ ] Wallet payments are available where the provider and device support them.
- [ ] If the business allows partial payments (setting, default off), the client may enter an
      amount between a minimum and the balance.
- [ ] Payment results are confirmed from the provider's notifications; the invoice becomes Paid
      or Partially paid; duplicate notifications or retries never double-record.
- [ ] The client sees a clear success page; failures and declines show friendly messages with
      a retry; abandoned payments leave the invoice unchanged.
- [ ] A receipt email (amount, date, method summary, invoice link) goes to the client; the
      business is notified (email/in-app per NTF-02).
- [ ] Refunds and disputes notified by the provider are reflected on the invoice and payment.
- [ ] Payments appear on the invoice, job and client pages with provider reference.
- [ ] Tests cover success, failure, partial, duplicate events and refund reflection using the
      provider's test mode or mocks.

## Out of scope

- Saved cards, autopay, ACH, tips, surcharges, deposits on quotes, in-app refunds (backlog).

## Open questions

- Platform fee on these payments (09-billing open question 3) — affects disclosure copy.
- Do we show "processing" for bank-delayed methods? Only relevant if ACH is added.
