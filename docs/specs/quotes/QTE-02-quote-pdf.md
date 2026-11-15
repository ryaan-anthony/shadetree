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
      (and signer/date once approved). *All but signer and date, which arrive with approval
      (QTE-05).*
- [x] Layout is legible on US Letter and A4, paginates long quotes cleanly (repeated header,
      no split rows) and handles long descriptions.
- [x] Staff can download the PDF from the quote; clients can from the client page (QTE-03).
- [x] The PDF for a sent revision is stable: re-downloading shows the same content.
- [x] Generation happens without blocking the web request for long documents, or is fast
      enough (< 2 s p95) to be inline — decision recorded.
- [x] The rendering approach is shared so invoices can reuse it with minimal work.
- [x] Visual regression or content tests guard the layout.

## Decisions

- **Rendering:** `PdfRenderer` prints self-contained HTML (`PdfDocument`: the `pdf` layout with
  the stylesheet, font and logo inlined) in headless Chrome via Ferrum. All network requests
  are refused, and one render runs at a time per process. Business countries that use US Letter
  get Letter; everyone else gets A4.
- **Inline or background:** a render takes about 2 s (mostly Chrome starting), which is over the
  2 s p95 budget for inline. So sent quotes keep their PDF (`HasPdf`: a blob plus a digest of
  the HTML), and `QuotePdfJob` makes it ahead of the first download. Sending (QTE-04) enqueues
  the job. A stored PDF is served in under 0.1 s. Drafts are rendered inline for staff only.
- **Stability:** the stored file is reused while the document's HTML is unchanged. A change
  that shows on the PDF (approval, say) makes a new file and purges the old one.
- **QR code:** yes. Sent quotes with an active link carry a QR code to the client page.
- **Reuse for invoices (PAY-02):** include `HasPdf`, add `pdf_blob_id`/`pdf_digest`, write a
  `pdfs/invoice` template, and use `SendsPdf` in the controllers.

## Out of scope

- Custom PDF templates per business (backlog). Attachments merged into the PDF.

## Open questions

- ~~PDF generation approach and hosting memory budget~~: ADR 0010. One Chrome per process at a
  time (about 150 MB while rendering); the image installs `chromium`.
- ~~Include a "scan to view/approve online" QR code on the PDF?~~ Yes, see Decisions.
