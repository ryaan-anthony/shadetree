# 0010. PDFs rendered from HTML with headless Chrome

- **Status:** Accepted
- **Date:** 2026-11-14
- **Specs:** QTE-02, PAY-02, INS-02

## Context

Quotes and invoices need branded PDFs that match the client web page (QTE-02). A second,
hand-built layout would drift from the HTML and double the work. PDFs are generated at send time
and downloaded often, and the VPS has limited memory (ADR 0009).

## Options considered

1. **Prawn** (draws PDFs in Ruby code). Light and fast, but every layout is built a second time
   in Ruby, and keeping it identical to the web page is manual work.
2. **wkhtmltopdf** (WickedPDF). HTML-based, but the engine is archived and has outdated CSS
   support.
3. **Puppeteer or Grover.** Headless Chrome, but needs Node.js in the image.
4. **Headless Chrome driven from Ruby over the DevTools protocol** (Ferrum), rendering the same
   HTML and CSS as the client page with print styles.

## Decision

Render PDFs from **the same HTML templates as the client page**, with a print stylesheet, using
**headless Chrome driven from Ruby (Ferrum)**. No Node.js. Generate PDFs in a **background job**
when a document is sent, store them with Active Storage (ADR 0008), and serve the stored file.
Regenerate only when a new revision is sent.

## Consequences

- One layout for web and PDF; print CSS handles pagination (repeated headers, no split rows).
- Chrome must be installed in the production image (+~300 MB), and rendering uses ~150–300 MB of
  memory per render. Limit to one render at a time on a small VPS.
- If memory becomes a problem, rendering can move to a separate worker or an external rendering
  service without changing templates.
- Implemented in QTE-02: `PdfRenderer` (Chrome with no network and scripts off, one render per
  process at a time) and `HasPdf`. A sent document's PDF is made in a background job and stored
  until the document itself changes, so downloads are served from storage.
- **Cost:** none beyond VPS memory headroom.
