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

- [x] When the business has an active payment account, the client invoice page shows a Pay
      button for the balance due; card entry happens in provider-hosted fields or pages.
- [x] Wallet payments are available where the provider and device support them.
- [x] If the business allows partial payments (setting, default off), the client may enter an
      amount between a minimum and the balance.
- [x] Payment results are confirmed from the provider's notifications; the invoice becomes Paid
      or Partially paid; duplicate notifications or retries never double-record.
- [x] The client sees a clear success page; failures and declines show friendly messages with
      a retry; abandoned payments leave the invoice unchanged.
- [x] A receipt email (amount, date, method summary, invoice link) goes to the client; the
      business is notified (email/in-app per NTF-02).
- [x] Refunds and disputes notified by the provider are reflected on the invoice and payment.
- [x] Payments appear on the invoice, job and client pages with provider reference.
- [x] Tests cover success, failure, partial, duplicate events and refund reflection using the
      provider's test mode or mocks.

## Out of scope

- Saved cards, autopay, ACH, tips, surcharges, deposits on quotes, in-app refunds (backlog).

## Decisions

- Stripe Checkout on the business's own Standard account (direct charges; PAY-03, ADR 0024),
  card only: Apple Pay and Google Pay come with it; ACH and other delayed methods aren't offered.
- Part payments are a business setting, off by default (07-payments open question 4, accepted);
  a part is at least $1.00 and leaves nothing or at least $1.00 owing (the owner may change
  `OnlinePayments::MINIMUM_PART`). Balances under 50¢ (Stripe's least) can't be paid online.
- One payment account per business (CAT-07, approved): every location's invoices are paid to it.
- The platform fee is a per-plan setting (basis points, editable in the operator console), 0 on
  every plan, so no fee is taken or mentioned; Settings → Payments names it only when it isn't 0.
- Money Stripe confirms is always recorded: a revision being prepared is dropped (the client paid
  what they were sent), a void invoice keeps its status, and a suspended business's payments
  still settle (OPS-04). A lost dispute stops counting as paid, like a refund.

## Implementation notes

- Pay (`POST /c/:token/invoice/pay`) shows when `Invoice#online_payable?`: sent with a balance,
  not revising, client not erased (INS-02), business active (suspended: links unavailable,
  OPS-04) and its account taking charges. It reuses the invoice's open Checkout Session for the
  same amount, or expires it and makes a new one (1 hour; recording a payment, voiding, revising
  or disconnecting expires it too), then redirects (Stripe's host only). Only an invoice page
  with Pay allows `checkout.stripe.com` in `form-action`. Rate limited per link and per link and
  IP. Cancel returns with a "nothing was charged" note; start failures say so with a retry.
- `ConnectEventHandler` records from `checkout.session.completed` / `async_payment_succeeded`
  and `payment_intent.succeeded` (`OnlinePayments.record!`): once per PaymentIntent (unique
  index, invoice lock), with "Visa ending 4242 (Apple Pay)", the charge date, and any refund or
  dispute Stripe already has; overpaid ones ask staff to refund the rest. Then: invoice
  history, CLI-05 timeline (so NTF-04's `payment_received` fires), the PAY-05 receipt (client's
  email; owner confirmed; waits for the hourly cap) and an "Online payments" notification.
- `charge.refunded` sets the refunded amount; `charge.dispute.*` the dispute (open, won, lost,
  inquiry closed); one arriving before its payment is retried. A refund or lost dispute that
  reopens the invoice skips overdue automations for it and tells the team. Totals, the client
  page, dashboard, receipts and the export count payments less refunds and lost disputes.
- Staff see online payments (method, Stripe reference, refund or dispute badge) on the invoice
  and job, and in the client timeline; they can't be changed here.
- Dev seeds: part payments on; $50 of INV-0001 paid online.

## Open questions

- Platform fee on these payments (09-billing open question 3): built as a per-plan setting at 0;
  disclosure copy appears only when it's set.
- Do we show "processing" for bank-delayed methods? Only relevant if ACH is added.
