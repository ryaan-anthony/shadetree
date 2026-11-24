---
title: Invoice finished work and record a payment
summary: Make an invoice from a job, send it, record cash and check payments, and fix or take tax off an invoice.
category: invoices-payments
topics: [invoices]
reviewed: 2026-11-24
screenshots:
  - name: invoice-draft
    path: /admin/invoices/:invoice/edit
    invoice: INV-0002
  - name: invoice-sent
    path: /admin/invoices/:invoice
    invoice: INV-0003
  - name: record-a-payment
    path: /admin/invoices/:invoice/payments/new
    invoice: INV-0003
---

Make the invoice from the job, so its lines and prices come across. Then send it, and record
what you're paid.

## Make the invoice

1. Open the finished job and press **Create invoice**. (Or press **New invoice** on **Invoices**,
   or on the client's page, to start one from scratch.)
2. The invoice opens as a draft with the job's items. Change anything you need: it saves as you
   go, just like a quote.
3. Press **Preview as client** to see it as your client will.

![A draft invoice: its lines, totals and tax, with Preview as client and Send invoice at the top](invoice-draft)

## Take tax off one invoice

On the draft, untick **Taxed** on the lines that shouldn't have tax, or untick the rate under
**Tax** in the totals. This changes only this invoice; your tax settings stay as they are.

## Send it

Press **Send invoice**. As with a quote, you can **Email it** (your message, a button to the
invoice and the PDF) or **Get the link** to send yourself. The due date comes from **Days to pay,
after it's issued** in **Settings**; change it for one invoice under **Payment terms** on the
draft.

If you take card payments, your client can pay online from the invoice. You'll see the payment on
the invoice when it arrives.

## Record a payment

When you're paid by cash, check or bank transfer:

![A sent invoice with its Status, Issued, Due and Balance, and Record payment at the top](invoice-sent)

1. Open the invoice and press **Record payment**.
2. Enter the **Amount** and the **Date received**.
3. Choose the **Method**: **Cash**, **Check**, **Bank transfer** or **Other**.
4. Add a **Reference**, like the check number, if you like.
5. Leave **Email a receipt** ticked to send your client what was received and what's left to pay.
6. Press **Record payment**.

![Record a payment: amount, date received, method, reference, and Email a receipt](record-a-payment)

The invoice's **Balance** goes down. When it reaches zero, the invoice is **Paid**.

## Made a mistake?

- **Revise** reopens a sent invoice as a draft to correct. Until you send the new version, your
  client's link says the invoice is being updated. Press **Send revision** when it's right.
- **Void** cancels an invoice that shouldn't exist, with a reason. An invoice with payments can't
  be voided or have its items changed.
