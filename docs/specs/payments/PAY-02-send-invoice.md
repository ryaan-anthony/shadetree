---
id: PAY-02
title: Send invoice & client invoice page
domain: payments
milestone: M4
depends_on: [PAY-01, QTE-02, PLT-12, NTF-01]
---
# PAY-02 · Send invoice & client invoice page

> Requirements: [07-payments](../../plans/07-payments.md) R6, R7

## Summary

Deliver invoices the same way quotes are delivered: a branded email with a button and a PDF, or a
link to copy, opening a clean client page that shows what's owed and — once online payments are
connected — lets the client pay.

## User stories

- As an owner, I want to email an invoice the moment the job is done so that I get paid sooner.
- As a client, I want to see what I owe, what I've paid, and when it's due.
- As a property manager, I want the invoice PDF for my records.

## Acceptance criteria

- [ ] From a draft, Owners/Admins send by email (recipient, CC, subject, personal message
      editable) or copy link; sending freezes the revision and sets status Sent (records who,
      when, channel). Sending requires a confirmed account.
- [ ] The email uses the business-branded layout with amount due, due date, a "View & pay" (or
      "View invoice") button and the PDF attached.
- [x] The client invoice page shows business identity, invoice number and dates, client and
      property, line items, discounts, taxes, total, payments received, balance due, terms and a
      PDF download; a payment area is shown when PAY-03/PAY-04 are enabled.
- [x] Paid and void invoices display clearly as such; the link keeps working after payment for
      record-keeping.
- [x] The invoice PDF reuses the QTE-02 rendering approach and shows payments and balance.
- [ ] Client views are recorded (first view notifies staff in-app via NTF-02 when available).
- [ ] Bounced emails surface on the invoice.
- [ ] Tests cover send paths, page states, PDF content and link isolation.

## Out of scope

- Online payment (PAY-04). Overdue reminders, SMS delivery (backlog).

## Decisions

- Client link expiry for invoices: no expiry until paid, then a year after payment (PLT-12).
  Links are issued without an end; recording the payment that settles an invoice (PAY-04/PAY-05)
  gives its active links their end.

## Implementation notes

- Part 1 (page and PDF): `client/invoices/_invoice` is the client page (also the staff
  preview); `client/invoices/_document` is the document, shared by the page and the PDF
  (`pdfs/invoice`), so the two can't drift. The line table (`client/documents/_lines`), the
  files section (`client/documents/_files`) and the PDF letterhead (`pdfs/_letterhead`) are
  shared with quotes. Files are served through the link (`Client::DocumentFilesController`,
  formerly the quote-only controller), so revoking a link cuts them off.
- The page leads with what's owed and when (overdue in red). The status on the document and
  the PDF comes from the status and balance only, so a stored PDF doesn't go stale when the
  due date passes. A sent invoice's PDF is stored and reused until its revision, status or
  amount paid changes.
- While a sent invoice is revised, its page says it's being updated, without the unfinished
  edits, and isn't counted as a view; the PDF isn't offered.
- The payment area arrives with PAY-03/PAY-04.
