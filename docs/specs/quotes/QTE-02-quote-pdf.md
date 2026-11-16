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
      (and signer/date once approved). *Signer and date arrive with approval (QTE-05).*
- [x] Layout is legible on US Letter and A4, paginates long quotes cleanly (repeated header,
      no split rows) and handles long descriptions.
- [x] Staff can download the PDF from the quote; clients can from the client page (QTE-03).
- [x] The PDF for a sent revision is stable: re-downloading shows the same content.
- [x] Generation happens without blocking the web request for long documents, or is fast
      enough (< 2 s p95) to be inline — decision recorded.
- [x] The rendering approach is shared so invoices can reuse it with minimal work.
- [x] Visual regression or content tests guard the layout.

## Decisions

- **Rendering:** `PdfRenderer` prints self-contained HTML (`PdfDocument` inlines styles, font,
  logo) in headless Chrome with no network and scripts off, one render per process at a time.
  Letter or A4 by country; the image adds Noto CJK fonts (about 50 MB).
- **Background:** a render takes about 2 s, so a sent quote's PDF is made by `QuotePdfJob` when
  its status changes and stored (`HasPdf`); a stored PDF is served in under 0.1 s. Drafts render
  inline, for staff only.
- **Stability:** the stored file is kept until the quote's content or status changes; letterhead
  edits, new links, expiry and deploys don't change it. Its status comes from the status alone.
- **Pagination:** rows stay whole, except long descriptions (over 400 characters). **Date:** the
  prepared date until sending (QTE-04) records when it went out.
- **No QR code:** it would carry one link's token into a file that outlives the link.
- **Invoices (PAY-02):** include `HasPdf`, add its two columns, a template, and `SendsPdf`.

## Out of scope

- Custom PDF templates per business (backlog). Attachments merged into the PDF.

## Open questions

- ~~PDF generation approach and memory budget~~: ADR 0010; about 150 MB while rendering.
