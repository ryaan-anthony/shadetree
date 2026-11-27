---
title: Progress invoices and the quote discount
summary: Bill part of a job before it's finished, share a quote's discount across invoices, and what to do when you've billed too much.
category: invoices-payments
topics: []
reviewed: 2026-11-27
screenshots:
  - name: progress-summary
    path: /admin/quotes/:quote
    quote: Roof replacement
    region: "#quote-progress"
  - name: final-invoice-credit
    path: /admin/invoices/:invoice/edit
    invoice: INV-0007
---

Some jobs are big enough that you want paid before they're done. A **progress invoice** bills part
of the work early. When you invoice the finished work, what the client already paid is taken off.

## Bill part of the work early

1. Open the job (or the quote) before the work is done.
2. On a job, press **Create progress invoice** under **Invoices**. On a quote, open **More
   actions** and choose **Create progress invoice**.
3. The invoice opens as a draft. Each line starts at everything that's left to bill.
   Lower the amounts to what you want to charge now, like half of the roof.
4. Send it as you would any invoice.

You can't bill more of a line than is left. A progress invoice that comes to $0.00 can't be sent.

## Share the quote's discount

A quote's discount is shared across all its invoices, never taken twice. Whenever an invoice bills
part of a discounted quote, you're asked **Apply now**: how much of the discount to take on this
invoice.

- It starts at **$0.00**, which means "later". What you don't use carries forward.
- **Apply all** takes everything that's left.
- Sometimes there's a minimum, because the work that's left can't take much more. The page tells
  you.
- The last invoice that finishes the quote takes the rest, so your client always gets the whole
  discount.

A percent discount works the same way, in dollars.

## When you invoice the finished work

![The quote's page shows what you billed as progress, and what has been credited](progress-summary)

The final invoice takes off what the progress invoice charged. In your draft the row reads
**Billed earlier on INV-0006**. Your client sees it as **Credit from INV-0006**. The credit is
exactly what that progress invoice charged, tax included.

![A final invoice draft: the quote discount box beside Apply now, and what was billed earlier taken off the total](final-invoice-credit)

## If you billed too much

- **Over-billed** is progress that went past the work done. It's taken off your client's next
  invoice for the same quote.
- **Owed to the client** is what's left when there's no later invoice to take it off. Shadetree
  credits nothing automatically. You refund it yourself. See [Give a refund, or fix a payment](refunds).

## Voiding

Void in the opposite order to how you sent. If a final invoice credits a progress invoice, void
the final invoice first, then the progress invoice. Shadetree tells you which to void first.
