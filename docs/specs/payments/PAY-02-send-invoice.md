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
- [ ] The client invoice page shows business identity, invoice number and dates, client and
      property, line items, discounts, taxes, total, payments received, balance due, terms and a
      PDF download; a payment area is shown when PAY-03/PAY-04 are enabled.
- [ ] Paid and void invoices display clearly as such; the link keeps working after payment for
      record-keeping.
- [ ] The invoice PDF reuses the QTE-02 rendering approach and shows payments and balance.
- [ ] Client views are recorded (first view notifies staff in-app via NTF-02 when available).
- [ ] Bounced emails surface on the invoice.
- [ ] Tests cover send paths, page states, PDF content and link isolation.

## Out of scope

- Online payment (PAY-04). Overdue reminders, SMS delivery (backlog).

## Open questions

- Client link expiry for invoices: recommend no expiry until paid + 1 year (PLT-12).
