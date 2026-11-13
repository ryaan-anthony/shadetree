---
id: QTE-02
title: Quote PDF
domain: quotes
milestone: M2
depends_on: [QTE-01, CAT-02]
---
# QTE-02 · Quote PDF

> Requirements: [05-quotes](../../plans/05-quotes.md) R19

## Summary

Many clients still print, forward or file quotes. Every quote renders as a clean, branded PDF
that matches the web view, can be attached to emails, and is downloadable by staff and clients.
The approach should be reusable for invoices (PAY-02).

## User stories

- As an owner, I want a professional PDF with my logo so that I look as established as larger
  competitors.
- As a property manager client, I want to download and file the quote for my records.

## Acceptance criteria

- [ ] A quote PDF includes: business branding and contact details, client and property, quote
      number, dates (issued, expiry), title, message, line items (name, description, quantity,
      unit, unit price, line total), discounts, tax per rate, total, terms, and approval status
      (and signer/date once approved).
- [ ] Layout is legible on US Letter and A4, paginates long quotes cleanly (repeated header,
      no split rows) and handles long descriptions.
- [ ] Staff can download the PDF from the quote; clients can from the client page (QTE-03).
- [ ] The PDF for a sent revision is stable: re-downloading shows the same content.
- [ ] Generation happens without blocking the web request for long documents, or is fast
      enough (< 2 s p95) to be inline — decision recorded.
- [ ] The rendering approach is shared so invoices can reuse it with minimal work.
- [ ] Visual regression or content tests guard the layout.

## Out of scope

- Custom PDF templates per business (backlog). Attachments merged into the PDF.

## Open questions

- PDF generation approach and hosting memory budget — decided in PLT-01 ADR.
- Include a "scan to view/approve online" QR code on the PDF? Recommend yes — cheap and useful.
