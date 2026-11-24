---
title: Give a refund, or fix a payment
summary: Refund a card payment, correct a cash or check payment you recorded, and what your client's invoice shows afterwards.
category: invoices-payments
topics: []
reviewed: 2026-11-24
screenshots:
  - name: invoice-payments
    path: /admin/invoices/:invoice
    invoice: INV-0001
    region: "#invoice-payments"
---

How you refund depends on how you were paid. Either way, the invoice's balance goes back up by
what you returned, so it's clear what's still owed.

![An invoice's payments: press the pencil beside a payment to correct it](invoice-payments)

## A card payment

Shadetree doesn't send money back itself. Refunds, and disputes, are handled in your card payment
provider's dashboard: open **Settings**, **Card payments** and follow the link there. Once you've
refunded, the invoice shows the amount refunded under that payment, and its balance goes up.

## Cash, check or a transfer you recorded

Pay the client back yourself, then correct the payment so the invoice matches:

1. Open the invoice. Under **Payments**, press the pencil beside the payment. **Change a payment**
   opens.
2. Change the **Amount** to what you kept, or press **Delete payment** if none of it stands.
3. Under **Why it's changing**, say why, like "Refunded $50" or "Check bounced".
4. Press **Save changes** (or confirm the delete).

The reason is kept in the invoice's history. If **Email a receipt** was ticked when you recorded
it, your client already has a receipt; tell them about the refund yourself.

## Refunded everything?

If the work won't be billed at all, and the invoice has no payments left, you can **Void** it with
a reason. See [Invoice finished work and record a payment](invoice-finished-work).
